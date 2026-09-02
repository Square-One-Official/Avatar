import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Set-brede lichtnormalisatie: herkent de **belichting** van een referentie
/// (exposure, kleurtemperatuur, contrast) en past alleen kleurcorrecties toe.
/// Geen gezicht-regeneratie, en geen RGB-mean-transfer — dat laatste kopieerde
/// huidtint en maakte andere huidskleuren onnatuurlijk rood/oranje.
///
/// Schatting gebeurt op ondoorzichtige pixels in het gezicht (Vision, anders
/// het hele cutout): highlights voor witbalans/exposure, luma-spreiding voor
/// contrast. De referentie zelf wordt niet herschreven.
///
/// E50.3: de app bakt de correctie niet meer in pixels. `adjustSuggestion` +
/// `refine` drukken dezelfde match uit als Adjust-laag-waarden (brightness/
/// contrast/temperature, de filters van `PortraitEnhancer.colorAdjust`) zodat
/// de sliders de match tonen en Reset 'm terugdraait; `chooseTarget` kiest het
/// doel (patroon van de set óf het best belichte portret). `match(_:to:)` blijft
/// als pixel-pad voor de tests/referentie.
///
/// GESCHRAPT (Thierry, 2026-09-02): de feature staat achter
/// `AppFeatureFlags.matchLightingEnabled` (uit). Een globale slider-match kan
/// lichtrichting en clippende highlights niet matchen; een latere AI-relighting
/// kan `chooseTarget`/`referenceStats` hergebruiken voor de referentiekeuze.
public enum SetLightingNormalizer {
    public struct Stats: Equatable, Sendable {
        /// Highlight-luma (p80), proxy voor belichtingssterkte.
        public let exposure: Double
        /// Geschatte illuminant in Kelvin (huid-bias is per foto vergelijkbaar,
        /// dus het verschil is de lichtkleur).
        public let kelvin: Double
        /// Groen↔magenta, zelfde schaal als `CITemperatureAndTint` y (~±150).
        public let tint: Double
        /// p80 − p20 luma: hard licht (groot) vs fill (klein).
        public let contrast: Double
        /// Rec. 601-luma van de sample (tests / sortering).
        public var luma: Double { exposure }

        public init(exposure: Double, kelvin: Double, tint: Double, contrast: Double) {
            self.exposure = exposure
            self.kelvin = kelvin
            self.tint = tint
            self.contrast = contrast
        }
    }

    private static let context = CIContext()
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let evRange: ClosedRange<Double> = -1.25...1.25
    private static let kelvinDeltaRange: ClosedRange<Double> = -1200...1200

    public static func referenceStats(of image: CGImage, in region: CGRect? = nil) -> Stats? {
        let extent = region ?? faceRegion(in: image) ?? fullExtent(of: image)
        return lighting(of: image, in: extent)
    }

    /// Kleurcorrectie van `image` naar de belichting van `ref`.
    /// `sourceRegion` override't gezichtdetectie (tests). Alpha blijft behouden.
    public static func match(
        _ image: CGImage,
        to ref: Stats,
        sourceRegion: CGRect? = nil
    ) -> CGImage? {
        guard let src = referenceStats(of: image, in: sourceRegion) else { return nil }
        var current = CIImage(cgImage: image)

        let ev = log2(max(ref.exposure, 0.04) / max(src.exposure, 0.04))
            .clamped(to: evRange)
        if abs(ev) > 0.02 {
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = current
            exposure.ev = Float(ev)
            if let out = exposure.outputImage { current = out }
        }

        let kelvinDelta = (ref.kelvin - src.kelvin).clamped(to: kelvinDeltaRange)
        let tintDelta = (ref.tint - src.tint).clamped(to: -40...40)
        if abs(kelvinDelta) > 40 || abs(tintDelta) > 4 {
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage = current
            temp.neutral = CIVector(x: 6500, y: 0)
            temp.targetNeutral = CIVector(x: 6500 + kelvinDelta, y: tintDelta)
            if let out = temp.outputImage { current = out }
        }

        let extraContrast = src.contrast - ref.contrast
        if extraContrast > 0.04 {
            let fill = CIFilter.highlightShadowAdjust()
            fill.inputImage = current
            fill.shadowAmount = Float(min(0.4, extraContrast * 1.2))
            fill.highlightAmount = 1.0
            if let out = fill.outputImage { current = out }
        }

        return render(current, like: image)
    }

    // MARK: - Adjust-suggestie (E50.3)

    /// De belichtings-match als Adjust-laag-waarden. Saturation blijft buiten het
    /// model (geen huidtint-transfer); tint valt weg (de Adjust-slider heeft 'm niet
    /// en 'ie was al tot ±40 geklemd).
    public struct AdjustSuggestion: Equatable, Sendable {
        public var brightness: Double
        public var contrast: Double
        public var temperature: Double

        public static let neutral = AdjustSuggestion(brightness: 0, contrast: 1, temperature: 0)
        public var isNeutral: Bool { self == .neutral }

        public init(brightness: Double, contrast: Double, temperature: Double) {
            self.brightness = brightness
            self.contrast = contrast
            self.temperature = temperature
        }
    }

    public static let brightnessRange: ClosedRange<Double> = -0.35...0.35
    /// Bewust smal: contrast draait om 0.5 lineair en versterkt zijlicht/schaduw
    /// op een gezicht — een groot verschil in spreiding is meestal lichtRICHTING
    /// (studio vs. vlak), en dat kan een globale slider niet matchen (E50.3-review
    /// Thierry: "way too oversaturated, contrast rich on one side").
    public static let contrastRange: ClosedRange<Double> = 0.85...1.15
    public static let temperatureRange: ClosedRange<Double> = -0.8...0.8

    /// Toleranties waarbinnen twee belichtingen als "gelijk" gelden: zo'n portret
    /// blijft ongemoeid (geen undo-stap, sliders onveranderd).
    public static let exposureTolerance = 0.04
    public static let kelvinTolerance = 150.0
    public static let contrastTolerance = 0.05

    public static func isWithinTolerance(_ a: Stats, _ b: Stats) -> Bool {
        abs(a.exposure - b.exposure) < exposureTolerance
            && abs(a.kelvin - b.kelvin) < kelvinTolerance
            && abs(a.contrast - b.contrast) < contrastTolerance
    }

    /// Exacte oplossing (in lineair licht) van de Adjust-waarden die `src` naar
    /// `ref` trekken. Empirisch geverifieerd model van `PortraitEnhancer.colorAdjust`
    /// (CIColorControls): `out = (lin(in) − 0.5) · contrast + 0.5 + brightness` —
    /// contrast draait om 0.5 in LINEAIR licht (≈ sRGB 0.735), daarna wordt
    /// brightness opgeteld. Contrast volgt uit de verhouding van de lineaire
    /// p20–p80-spreiding, brightness sluit daarna p80 exact aan. Loopt brightness
    /// tegen z'n klem, dan gaat contrast terug naar 1 (nooit p80 via contrast
    /// najagen — dat wast het beeld uit). Temperature = kelvin-delta op de
    /// ±1500K-schaal van de slider. Neutraal binnen tolerantie.
    public static func adjustSuggestion(from src: Stats, to ref: Stats) -> AdjustSuggestion {
        let dExposure = ref.exposure - src.exposure
        let dKelvin = ref.kelvin - src.kelvin
        let dContrast = ref.contrast - src.contrast

        var brightness = 0.0
        var contrast = 1.0
        if abs(dExposure) >= exposureTolerance || abs(dContrast) >= contrastTolerance {
            let s80 = linear(src.exposure), s20 = linear(max(0, src.exposure - src.contrast))
            let r80 = linear(ref.exposure), r20 = linear(max(0, ref.exposure - ref.contrast))
            let flat = (s80 - s20) < 0.01 || (r80 - r20) < 0.01
            var c = flat ? 1 : ((r80 - r20) / (s80 - s20)).clamped(to: contrastRange)
            var b = r80 - ((s80 - 0.5) * c + 0.5)
            if !brightnessRange.contains(b) {
                // De slider haalt de belichting niet: zover als 'ie kan, zónder
                // contrast erbovenop — dat draait om 0.5 lineair en maakt een te
                // donker beeld alleen donkerder (of wast het uit).
                c = 1
                b = (r80 - s80).clamped(to: brightnessRange)
            }
            brightness = b
            contrast = c
            if abs(brightness) < 0.005 { brightness = 0 }
            if abs(contrast - 1) < 0.01 { contrast = 1 }
        }
        let temperature = abs(dKelvin) < kelvinTolerance
            ? 0 : (dKelvin / 1500).clamped(to: temperatureRange)
        return AdjustSuggestion(brightness: brightness, contrast: contrast, temperature: temperature)
    }

    /// Eén verificatie-pass: rendert de suggestie op een ≤128px-kopie van `raw`,
    /// meet p80 opnieuw en corrigeert alléén brightness met het lineaire residu
    /// (het model is exact; dit vangt sampling-verschillen in het gezichtsgebied
    /// op). Contrast en temperature blijven staan — iteratief bijsturen op de
    /// kelvin-/spreidingsmetriek liep weg naar de klemwaarden (E50.3-diagnose).
    /// `region` = gezichtsgebied in `raw`-coördinaten (nil = detectie);
    /// `saturation` = de saturation-stand waarmee het portret straks rendert.
    public static func refine(
        _ suggestion: AdjustSuggestion,
        raw: CGImage,
        region: CGRect? = nil,
        to ref: Stats,
        saturation: Double = 1,
        iterations: Int = 1
    ) -> AdjustSuggestion {
        guard !suggestion.isNeutral, suggestion.brightness != 0 else { return suggestion }
        let fullRegion = region ?? faceRegion(in: raw) ?? fullExtent(of: raw)
        guard let scaled = downscaled(raw, maxSide: 128) else { return suggestion }
        let small = scaled.image
        let smallRegion = fullRegion.applying(CGAffineTransform(scaleX: scaled.scale, y: scaled.scale))
        var s = suggestion
        for _ in 0..<max(0, iterations) {
            guard let rendered = PortraitEnhancer.colorAdjust(
                small, brightness: s.brightness, contrast: s.contrast,
                saturation: saturation, temperatureShift: s.temperature
            ), let measured = lighting(of: rendered, in: smallRegion) else { break }
            let residual = linear(ref.exposure) - linear(measured.exposure)
            guard abs(residual) >= 0.01 else { break }
            s.brightness = (s.brightness + residual).clamped(to: brightnessRange)
        }
        return s
    }

    /// sRGB → lineair licht (de ruimte waarin CIColorControls rekent).
    public static func linear(_ srgb: Double) -> Double {
        let v = min(max(srgb, 0), 1)
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    // MARK: - Doelkeuze (E50.3)

    public enum Target: Equatable, Sendable {
        /// Eén portret uit de set is de referentie (index in de invoer).
        case portrait(Int)
        /// Het gedeelde patroon van de set (mediaan van de meerderheidscluster).
        case centroid(Stats)
    }

    /// 0 = goed belicht portret; hoger = verder van het ideaal (exposure-band
    /// 0.50…0.75, contrast 0.30…0.65 — studiolicht is contrastrijk en hoort
    /// hier niet afgestraft —, kelvin 4500…6500, genormaliseerd).
    public static func qualityScore(_ s: Stats) -> Double {
        bandDistance(s.exposure, 0.50...0.75) / 0.12
            + bandDistance(s.contrast, 0.30...0.65) / 0.10
            + bandDistance(s.kelvin, 4500...6500) / 400
    }

    /// Kiest waar de set naartoe moet. Is er een meerderheid (≥ 50% én ≥ 2) die
    /// dezelfde belichting deelt → dat patroon (mediaan) is het doel en alleen de
    /// buitenstaanders worden aangepast. Anders (N = 2, of alles verschillend) →
    /// het best belichte portret is de referentie en de rest volgt. Bij gelijke
    /// stand wint `preferred` (het aangeklikte/jongste portret), anders het
    /// portret met het krachtigste licht (hoogste contrast). nil bij lege invoer;
    /// één portret → niets aan te passen.
    public static func chooseTarget(_ stats: [Stats], preferred: Int? = nil) -> (target: Target, adjust: [Int])? {
        let n = stats.count
        guard n > 0 else { return nil }
        guard n > 1 else { return (.portrait(0), []) }

        // Single-link clustering op genormaliseerde afstand ≤ 1 (union-find).
        var parent = Array(0..<n)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for i in 0..<n {
            for j in (i + 1)..<n where distance(stats[i], stats[j]) <= 1 {
                let (a, b) = (root(i), root(j))
                if a != b { parent[max(a, b)] = min(a, b) }
            }
        }
        var clusters: [Int: [Int]] = [:]
        for i in 0..<n { clusters[root(i), default: []].append(i) }
        let largest = clusters.values.max { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            // Gelijke grootte: de cluster mét `preferred`, anders de laagste index.
            let lp = preferred.map(lhs.contains) ?? false
            let rp = preferred.map(rhs.contains) ?? false
            if lp != rp { return rp }
            return (lhs.min() ?? 0) > (rhs.min() ?? 0)
        } ?? []

        if largest.count >= 2, largest.count * 2 >= n {
            let members = largest.map { stats[$0] }
            let centroid = Stats(
                exposure: median(members.map(\.exposure)),
                kelvin: median(members.map(\.kelvin)),
                tint: median(members.map(\.tint)),
                contrast: median(members.map(\.contrast))
            )
            let outside = (0..<n).filter { !largest.contains($0) }
            return (.centroid(centroid), outside)
        }

        let scores = stats.map(qualityScore)
        let bestScore = scores.min() ?? 0
        let ties = (0..<n).filter { abs(scores[$0] - bestScore) < 1e-9 }
        let crispest = ties.max { lhs, rhs in
            if stats[lhs].contrast != stats[rhs].contrast { return stats[lhs].contrast < stats[rhs].contrast }
            return lhs > rhs // gelijk contrast: laagste index
        } ?? ties[0]
        let best = preferred.flatMap { ties.contains($0) ? $0 : nil } ?? crispest
        return (.portrait(best), (0..<n).filter { $0 != best })
    }

    /// Genormaliseerde afstand tussen twee belichtingen (1 ≈ "duidelijk anders").
    public static func distance(_ a: Stats, _ b: Stats) -> Double {
        let de = (a.exposure - b.exposure) / 0.12
        let dk = (a.kelvin - b.kelvin) / 400
        let dc = (a.contrast - b.contrast) / 0.10
        return (de * de + dk * dk + dc * dc).squareRoot()
    }

    private static func bandDistance(_ v: Double, _ r: ClosedRange<Double>) -> Double {
        if v < r.lowerBound { return r.lowerBound - v }
        if v > r.upperBound { return v - r.upperBound }
        return 0
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Verkleinde kopie (langste zijde ≤ `maxSide`) + de gebruikte schaal — voor
    /// meten/renderen op werkformaat (de stats samplen toch op ≤128px).
    public static func downscaled(_ image: CGImage, maxSide: CGFloat) -> (image: CGImage, scale: CGFloat)? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let scale = min(1, maxSide / max(w, h, 1))
        let width = max(1, Int((w * scale).rounded(.down)))
        let height = max(1, Int((h * scale).rounded(.down)))
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let out = ctx.makeImage() else { return nil }
        return (out, CGFloat(width) / w)
    }

    // MARK: - Lighting estimate

    private static func lighting(of image: CGImage, in region: CGRect) -> Stats? {
        guard let samples = opaqueSamples(of: image, in: region), samples.count >= 4 else {
            return nil
        }
        let lumas = samples.map(\.luma).sorted()
        let p20 = percentile(lumas, 0.20)
        let p80 = percentile(lumas, 0.80)
        let exposure = max(p80, 0.04)

        let highlightCut = p80
        var hr = 0.0, hg = 0.0, hb = 0.0, hn = 0.0
        for s in samples where s.luma >= highlightCut && s.luma > 0.08 {
            hr += s.r; hg += s.g; hb += s.b; hn += 1
        }
        if hn < 2 {
            for s in samples { hr += s.r; hg += s.g; hb += s.b; hn += 1 }
        }
        hn = max(hn, 1)
        hr /= hn; hg /= hn; hb /= hn

        return Stats(
            exposure: exposure,
            kelvin: kelvin(r: hr, g: hg, b: hb),
            tint: tint(r: hr, g: hg, b: hb),
            contrast: max(0, p80 - p20)
        )
    }

    private struct Sample {
        var r: Double
        var g: Double
        var b: Double
        var luma: Double
    }

    private static func opaqueSamples(of image: CGImage, in region: CGRect) -> [Sample]? {
        let ci = CIImage(cgImage: image)
        let extent = region.intersection(ci.extent)
        guard extent.width >= 1, extent.height >= 1 else { return nil }

        let maxSide: CGFloat = 128
        let scale = min(1, maxSide / max(extent.width, extent.height))
        let width = max(1, Int((extent.width * scale).rounded(.down)))
        let height = max(1, Int((extent.height * scale).rounded(.down)))
        let cropped = ci.cropped(to: extent)
        let scaled = cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let bounds = CGRect(
            x: scaled.extent.minX, y: scaled.extent.minY,
            width: CGFloat(width), height: CGFloat(height)
        )

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            scaled, toBitmap: &pixels, rowBytes: width * 4,
            bounds: bounds, format: .RGBA8, colorSpace: sRGB
        )

        var samples: [Sample] = []
        samples.reserveCapacity(width * height / 2)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Double(pixels[i + 3]) / 255
            guard a >= 0.35 else { continue }
            let r = Double(pixels[i]) / 255
            let g = Double(pixels[i + 1]) / 255
            let b = Double(pixels[i + 2]) / 255
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            samples.append(Sample(r: r, g: g, b: b, luma: luma))
        }
        return samples
    }

    /// Neutraal (R=G=B) → 6500K. Meer rood t.o.v. blauw → warmer (lager K).
    private static func kelvin(r: Double, g: Double, b: Double) -> Double {
        let rb = r / max(b, 0.04)
        return (6500 - (rb - 1.0) * 2800).clamped(to: 3200...9000)
    }

    private static func tint(r: Double, g: Double, b: Double) -> Double {
        ((g - (r + b) / 2) * 120).clamped(to: -80...80)
    }

    private static func percentile(_ sorted: [Double], _ t: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let i = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * t).rounded())))
        return sorted[i]
    }

    // MARK: - Face region

    public static func faceRegion(in image: CGImage) -> CGRect? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        _ = try? handler.perform([request])
        guard let bb = request.results?.max(by: {
            $0.boundingBox.width * $0.boundingBox.height
                < $1.boundingBox.width * $1.boundingBox.height
        })?.boundingBox else { return nil }

        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        var rect = CGRect(
            x: bb.origin.x * w,
            y: bb.origin.y * h,
            width: bb.width * w,
            height: bb.height * h
        )
        rect = rect.insetBy(dx: -rect.width * 0.1, dy: -rect.height * 0.1)
        return rect.intersection(CGRect(x: 0, y: 0, width: w, height: h))
    }

    private static func fullExtent(of image: CGImage) -> CGRect {
        CGRect(x: 0, y: 0, width: image.width, height: image.height)
    }

    private static func render(_ ci: CIImage, like image: CGImage) -> CGImage? {
        let extent = CIImage(cgImage: image).extent
        let colorSpace = image.colorSpace ?? sRGB
        return context.createCGImage(
            ci.cropped(to: extent), from: extent, format: .RGBA8, colorSpace: colorSpace
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
