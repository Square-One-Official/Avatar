import AppKit
import CoreImage
import Foundation

/// E55.13 — deterministische die-cut-afwerking van een sticker-resultaat.
///
/// Waarom: het Sticker-effect laat gpt-image een sticker mét witte rand op
/// gekleurd papier tekenen; daarna her-isoleert de client het resultaat met
/// de cutout-engine (Vision foreground-instance ∪ person-seg). Die engines
/// kennen de witte rand niet: soms zit 'ie (deels) in de foreground-
/// instantie, meestal niet → de rand overleeft als een wazige, hobbelige,
/// onderbroken zoom (Thierry, 2026-09-04: "outline soms blurry en niet
/// helemaal rond; soms gaat het wél goed"). Bovendien houdt het model zich
/// niet altijd aan HEAD ONLY en blijven schouders/shirt staan.
///
/// Wat: na de her-isolatie renderen we de rand zélf, pixel-deterministisch:
///   1. hoofd-alleen-clip — met een gezicht in het resultaat wordt alles
///      onder de kin + halsstuk weggesneden via een U-vorm (rounded-rect
///      met grote onderhoeken), zodat de sticker ook zónder model-
///      medewerking om het hoofd sluit; geen gezicht of niets onder de
///      snede → geen clip;
///   2. alpha hard op 0,5 drempelen (haar-wisps maken de rand anders
///      rafelig), cirkelvormig dilateren met de randbreedte → witte plaat
///      met een harde, overal even brede, rondom gesloten rand;
///   3. onderwerp over de plaat compositen. De plaatkleur volgt de model-
///      rand: zit er (deels) nog een crème/witte papierrand van het model in
///      de matte, dan krijgt onze plaat diezelfde kleur (`plateColor`) zodat
///      het één band wordt i.p.v. crème-binnen-wit; anders zuiver wit.
///
/// Pure functies (`borderRadius`, `headClip`, `render`) zijn testbaar zonder
/// Vision; `finish` doet detectie + render off-main en faalt stil (origineel
/// terug) zodat het effect nooit verloren gaat.
enum DieCutRenderer {

    /// Wat de renderer van het geïsoleerde resultaat moet weten — top-left
    /// pixelcoördinaten, zoals `AutoFramer.Metrics`.
    struct Geometry: Equatable {
        /// Kin-lijn (onderkant Vision-face-rect). nil = geen gezicht → geen clip.
        var chinY: CGFloat?
        var faceHeight: CGFloat?
        /// Opaque-bbox van de rijen boven de kin (haar incl.), nil zonder gezicht.
        var headRect: CGRect?
        /// Opaque-bbox van het hele onderwerp.
        var contentRect: CGRect?

        init(chinY: CGFloat? = nil, faceHeight: CGFloat? = nil, headRect: CGRect? = nil, contentRect: CGRect? = nil) {
            self.chinY = chinY
            self.faceHeight = faceHeight
            self.headRect = headRect
            self.contentRect = contentRect
        }

        init(metrics: AutoFramer.Metrics) {
            chinY = metrics.faceRect?.maxY
            faceHeight = metrics.faceRect?.height
            headRect = metrics.headContentRect
            contentRect = metrics.contentRect
        }
    }

    /// Snede voor de hoofd-alleen-clip: rect + hoekradius van de onderhoeken
    /// (top-left px). De rect steekt boven het beeld uit zodat alleen de
    /// onderkant rondt.
    struct HeadClip: Equatable {
        var rect: CGRect
        var cornerRadius: CGFloat
    }

    // MARK: - Afstemming

    /// Randbreedte als fractie van de hoofdbreedte (haar incl.).
    static let borderFraction: CGFloat = 0.045
    /// Ondergrens in px — onder ~8 px leest een rand niet meer als sticker.
    static let minBorderPx: CGFloat = 8
    /// Bovengrens als fractie van de korte beeldzijde.
    static let maxBorderFraction: CGFloat = 0.12
    /// Halsstuk dat onder de kin blijft staan (× gezichtshoogte).
    static let neckAllowance: CGFloat = 0.45
    /// Radius van de onderhoeken van de U (× gezichtshoogte, gecapt op halve breedte).
    static let bottomCornerFraction: CGFloat = 0.6
    /// Alpha-drempel voor de plaat: wisps en halo's eronder tellen niet mee.
    static let alphaThreshold: Float = 0.5
    /// Band langs de matte-rand waarin we naar model-randresten zoeken
    /// (× randbreedte). Gemeten op zes e55-bakeoff-stickers: bij 1,0 haalt
    /// elke rest de fractie (0,23–0,49), bij 1,5 vallen er twee onder.
    static let sampleBandFactor: CGFloat = 1.0
    /// "Papierachtig": licht én bijna kleurloos (unpremultiplied, 0…1). Gemeten
    /// op de e55-bakeoff-stickers: de retro crème rand zit rond (0,89 0,84 0,76)
    /// met grain → min-kanaal ≈ 0,72–0,78, chroma ≈ 0,13–0,17; strakker
    /// (0,78/0,14) miste 'm en gaf crème-binnen-wit.
    static let paperMinChannel: Double = 0.70
    static let paperMaxChroma: Double = 0.20
    /// Minimale fractie papierachtige pixels in de band om de kleur over te
    /// nemen — hoog genoeg dat een lichte hals/hand aan de rand alléén niet telt.
    static let paperMinFraction: Double = 0.2
    /// Langste zijde van het sample-raster (kleur, geen geometrie → grof is zat).
    static let sampleMaxEdge = 512

    /// Plaatkleur (0…1 sRGB) — de kleur van de model-rand die nog in de matte
    /// zit, of wit. Zie `plateColor(of:bandWidth:)`.
    struct PlateColor: Equatable {
        var red: Double, green: Double, blue: Double
        static let white = PlateColor(red: 1, green: 1, blue: 1)
    }

    // MARK: - Pure geometrie

    /// Randbreedte in px voor dit resultaat.
    static func borderRadius(geometry: Geometry, imageSize: CGSize) -> CGFloat {
        let shortSide = min(imageSize.width, imageSize.height)
        let reference = geometry.headRect?.width ?? geometry.contentRect?.width ?? shortSide
        let raw = reference * borderFraction
        return min(max(raw, minBorderPx), shortSide * maxBorderFraction).rounded()
    }

    /// De U-vormige snede onder de kin, of nil als er niets te snijden valt
    /// (geen gezicht, of het onderwerp eindigt al boven de snede — dan hield
    /// het model zich aan HEAD ONLY en laten we z'n eigen onderrand staan).
    static func headClip(geometry: Geometry, imageSize: CGSize) -> HeadClip? {
        guard let chinY = geometry.chinY, let faceHeight = geometry.faceHeight, faceHeight > 0 else {
            return nil
        }
        let content = geometry.contentRect ?? CGRect(origin: .zero, size: imageSize)
        let bottom = (chinY + neckAllowance * faceHeight).rounded()
        guard content.maxY > bottom + 2 else { return nil }
        let head = geometry.headRect ?? content
        // Minimaal de gezichtsbreedte (≈ 0,8 × hoogte) zodat een smal hoofd-
        // bbox (kaal, strak haar) de hals niet afknijpt.
        let width = max(head.width, faceHeight * 0.8)
        let radius = min(width / 2, bottomCornerFraction * faceHeight).rounded()
        let top = -(2 * radius + 16)
        let rect = CGRect(x: (head.midX - width / 2).rounded(), y: top, width: width.rounded(), height: bottom - top)
        return HeadClip(rect: rect, cornerRadius: radius)
    }

    // MARK: - Plaatkleur

    /// Samplet de band van `bandWidth` px langs de buitenrand van de matte
    /// (opaak = alpha ≥ 0,5) en neemt de mediaankleur van de papierachtige
    /// pixels daarin over als minstens `paperMinFraction` van de band
    /// papierachtig is; anders wit. Rekent op een verkleind raster (CPU,
    /// O(N·k)) — kleur hoeft niet pixel-exact.
    static func plateColor(of image: CGImage, bandWidth: CGFloat) -> PlateColor {
        paperSample(of: image, bandWidth: bandWidth).color
    }

    /// Meetbare variant van `plateColor`: de gekozen kleur plus de fractie
    /// papierachtige pixels in de band (diagnose/dump-test).
    static func paperSample(of image: CGImage, bandWidth: CGFloat) -> (color: PlateColor, fraction: Double) {
        let scale = min(1, CGFloat(sampleMaxEdge) / CGFloat(max(image.width, image.height)))
        let w = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let h = max(1, Int((CGFloat(image.height) * scale).rounded()))
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return (.white, 0) }

        // Kern (alpha ≥ 0,5) en erosie met een vierkant venster van k px —
        // band = kern − erosie(kern).
        let k = max(1, Int((bandWidth * scale).rounded()))
        var core = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) { core[i] = buf[i * 4 + 3] >= 128 }
        var rowMin = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var all = true
                var dx = -k
                while all && dx <= k {
                    let xx = x + dx
                    if xx < 0 || xx >= w || !core[y * w + xx] { all = false }
                    dx += 1
                }
                rowMin[y * w + x] = all
            }
        }
        var reds: [Double] = [], greens: [Double] = [], blues: [Double] = []
        var bandCount = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                guard core[i] else { continue }
                var eroded = true
                var dy = -k
                while eroded && dy <= k {
                    let yy = y + dy
                    if yy < 0 || yy >= h || !rowMin[yy * w + x] { eroded = false }
                    dy += 1
                }
                if eroded { continue }
                bandCount += 1
                let a = Double(buf[i * 4 + 3]) / 255
                guard a > 0 else { continue }
                let r = min(1, Double(buf[i * 4]) / 255 / a)
                let g = min(1, Double(buf[i * 4 + 1]) / 255 / a)
                let b = min(1, Double(buf[i * 4 + 2]) / 255 / a)
                let lo = min(r, g, b), hi = max(r, g, b)
                if lo >= paperMinChannel, hi - lo <= paperMaxChroma {
                    reds.append(r); greens.append(g); blues.append(b)
                }
            }
        }
        let fraction = bandCount > 0 ? Double(reds.count) / Double(bandCount) : 0
        guard fraction >= paperMinFraction else { return (.white, fraction) }
        func median(_ v: [Double]) -> Double { let s = v.sorted(); return s[s.count / 2] }
        return (PlateColor(red: median(reds), green: median(greens), blue: median(blues)), fraction)
    }

    // MARK: - Render

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Rendert de sticker: (clip →) drempel → dilatie → witte plaat → onderwerp erover.
    /// nil als Core Image niet kan renderen; de caller houdt dan het origineel.
    static func render(_ image: CGImage, geometry: Geometry) -> CGImage? {
        let source = CIImage(cgImage: image)
        let extent = source.extent
        let size = CGSize(width: image.width, height: image.height)
        guard size.width > 0, size.height > 0 else { return nil }
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)

        // 1. Hoofd-alleen-clip (zachte 1px-rand tegen trapjes).
        var subject = source
        if let clip = headClip(geometry: geometry, imageSize: size),
           let clipMask = roundedRectMask(clip, imageHeight: size.height, extent: extent) {
            subject = source.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: clear,
                kCIInputMaskImageKey: clipMask,
            ]).cropped(to: extent)
        }

        // 2. Alpha → grijswaarde, hard drempelen, cirkelvormig dilateren.
        let alpha = subject.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: extent)
        let core = alpha.applyingFilter("CIColorThreshold", parameters: [
            "inputThreshold": alphaThreshold,
        ]).cropped(to: extent)
        let radius = borderRadius(geometry: geometry, imageSize: size)
        let dilated = core.applyingFilter("CIMorphologyMaximum", parameters: [
            kCIInputRadiusKey: Float(radius),
        ]).cropped(to: extent)
        // Trapjes van de aliased drempel wegronden, daarna één zachte pixel
        // als anti-alias — de rand blijft hard (overgang ≈ 1–2 px).
        let plate = dilated
            .applyingGaussianBlur(sigma: 1.2)
            .applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.5])
            .applyingGaussianBlur(sigma: 0.6)
            .cropped(to: extent)

        // 3. Plaat onder het onderwerp — in de kleur van de model-randrest (of wit).
        let color: PlateColor
        if let clipped = context.createCGImage(subject, from: extent) {
            color = plateColor(of: clipped, bandWidth: radius * sampleBandFactor)
        } else {
            color = .white
        }
        let fill = CIImage(color: CIColor(
            red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1
        )).cropped(to: extent)
        let filledPlate = fill.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: plate,
        ]).cropped(to: extent)
        let composed = subject.composited(over: filledPlate).cropped(to: extent)
        return context.createCGImage(composed, from: extent)
    }

    /// Witte rounded-rect als clip-masker (CI-coördinaten: oorsprong linksonder).
    private static func roundedRectMask(_ clip: HeadClip, imageHeight: CGFloat, extent: CGRect) -> CIImage? {
        let ciRect = CGRect(
            x: clip.rect.minX,
            y: imageHeight - clip.rect.maxY,
            width: clip.rect.width,
            height: clip.rect.height
        )
        guard let generator = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: ciRect),
            "inputRadius": Float(clip.cornerRadius),
            "inputColor": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]), let rect = generator.outputImage else { return nil }
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        return rect.composited(over: clear).applyingGaussianBlur(sigma: 0.8).cropped(to: extent)
    }

    // MARK: - Actie

    /// Detectie (Vision op het geïsoleerde resultaat) + render, off-main.
    /// Faalt stil: zonder render komt het geïsoleerde beeld ongewijzigd terug.
    static func finish(_ image: NSImage) async -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let rendered: CGImage? = await Task.detached(priority: .userInitiated) {
            let metrics = AutoFramer.metrics(for: cg)
            return render(cg, geometry: Geometry(metrics: metrics))
        }.value
        guard let rendered else { return image }
        return NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
    }
}
