import CoreGraphics
import CoreImage
import Foundation
import Vision

/// On-device tandenbleek (E32.2) — het gratis alternatief voor de cloud-arm
/// van "Whiten teeth". Anders dan de cloud-edit (volledige her-render door
/// nano-banana) is dit een strikt gelokaliseerde bewerking: alleen de RGB
/// binnen het mondgebied verandert, afmetingen en alpha blijven per
/// constructie identiek. Daarmee zijn de drie gerapporteerde defecten
/// (globaal lichter beeld, ander formaat, nauwelijks wittere tanden)
/// structureel uitgesloten in plaats van weg-geprompt.
///
/// Pijplijn: Vision-landmarks (innerLips) → polygon-masker met feather →
/// emaille-kleurpoort (CIColorCube: licht genoeg, weinig verzadigd, niet
/// rood/blauw — sluit lippen, tandvlees en mondholte uit) → adaptieve
/// sterkte gemeten op de maskerregio → desaturatie + gamma-lift alléén
/// binnen het masker (CIBlendWithMask).
///
/// Bekende beperking: landmarks vergen een herkenbaar gezicht — extreme
/// mond-close-ups vallen terug op `.noFaceFound` (de UI verwijst dan naar
/// de cloud-optie). Een face-parsing-model met echte tandsegmentatie is
/// het genoteerde vervolg (E32, follow-up).
public struct TeethWhitener: Sendable {
    public enum Failure: Error, Equatable {
        /// Geen gezicht/landmarks gevonden (bv. extreme close-up crop).
        case noFaceFound
        /// Mond dicht of geen emaille-achtige pixels na de kleurpoort —
        /// bewuste no-op in plaats van een slechte edit.
        case mouthNotVisible
        /// Core Image kon het eindresultaat niet renderen.
        case renderFailed
    }

    // MARK: - Afstelconstanten (genoemd zodat tests gedrag pinnen terwijl
    // smoke-tuning de waarden kan verschuiven)

    /// Minimale mondopening als fractie van de face-rect-oppervlakte;
    /// daaronder is de mond dicht en bleken we niet.
    static let minApertureAreaFraction: CGFloat = 0.003
    /// Minimale dekking van het uiteindelijke tandmasker binnen de mond-
    /// bbox; daaronder vond de kleurpoort geen emaille (donkere mondholte).
    static let minMaskCoverage: Double = 0.02
    /// Feather van het polygon-masker, als fractie van de gezichtsbreedte.
    static let geometryFeatherFraction: CGFloat = 0.02
    /// Tweede, kleinere feather ná de kleurpoort (zachte emaille-rand).
    static let detailFeatherFraction: CGFloat = 0.01
    /// Emaille is nooit sterk verzadigd; erboven = lip/tandvlees/tong.
    static let maxEnamelSaturation: Double = 0.42
    /// Doel-luminantie (sRGB) voor de gamma-lift van de tanden.
    static let targetLuma: Double = 0.82
    /// Klemgrenzen tegen grijze/platte tanden resp. onzichtbaar effect.
    static let desaturationRange: ClosedRange<Double> = 0.20...0.65
    static let minGammaPower: Double = 0.75

    public init() {}

    /// Bleekt de tanden. Output: identieke afmetingen + alpha als input;
    /// alleen RGB binnen het mondgebied verandert.
    public func whiten(_ image: CGImage) async throws -> CGImage {
        let source = CIImage(cgImage: image)
        let extent = source.extent
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0 else {
            throw Failure.renderFailed
        }

        // Gepinde revision — zelfde verzekering tegen stille OS-gedrags-
        // wijziging als VisionCutoutEngine/ClothesMaskGenerator.
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw Failure.noFaceFound
        }

        guard let face = Self.largestFace(request.results) else {
            throw Failure.noFaceFound
        }
        let bb = face.boundingBox
        let faceW = bb.width * imageSize.width
        let faceH = bb.height * imageSize.height
        guard let innerLips = face.landmarks?.innerLips, innerLips.pointCount >= 3 else {
            throw Failure.mouthNotVisible
        }
        let normalized = (0..<innerLips.pointCount).map { innerLips.normalizedPoints[$0] }
        let mouthPoints = Self.pixelPoints(
            normalized: normalized, boundingBox: bb, imageSize: imageSize
        )

        // Mond dicht? De innerLips-polygon is dan een sliver.
        let faceArea = faceW * faceH
        guard faceArea > 0,
              Self.polygonArea(mouthPoints) >= Self.minApertureAreaFraction * faceArea else {
            throw Failure.mouthNotVisible
        }

        let feather = max(1, faceW * Self.geometryFeatherFraction)
        let geometry = Self.polygonMask(points: mouthPoints, extent: extent, feather: feather)
        let mouthRect = Self.boundingRect(
            of: mouthPoints, padding: feather * 2, clampedTo: extent
        )

        // Adaptieve poortvloer: tanden zijn lichter dan het mondgemiddelde,
        // dus schaduw/mondholte valt onder de vloer.
        let mouthMean = Self.meanColor(of: source, in: mouthRect)
        let mouthLuma = Self.luma(r: mouthMean.r, g: mouthMean.g, b: mouthMean.b)
        let luminanceFloor = min(max(mouthLuma * 1.15, 0.30), 0.55)

        let gate = Self.enamelGate(on: source, luminanceFloor: luminanceFloor)
        let teethMask = Self.combinedMask(
            geometry: geometry, gate: gate, extent: extent,
            feather: max(1, faceW * Self.detailFeatherFraction)
        )

        let masked = Self.maskedAverage(source, mask: teethMask, in: mouthRect)
        guard masked.coverage >= Self.minMaskCoverage else {
            throw Failure.mouthNotVisible
        }

        let params = Self.whiteningParams(r: masked.r, g: masked.g, b: masked.b)
        let whitenedLayer = Self.whitened(
            source, desaturation: params.desaturation, gammaPower: params.gammaPower
        )
        let result = Self.composite(source: source, whitened: whitenedLayer, mask: teethMask)

        guard let cg = EngineRendering.standardContext.createCGImage(
            result.cropped(to: extent), from: extent, format: .RGBA8,
            colorSpace: EngineRendering.outputColorSpace(for: image)
        ) else {
            throw Failure.renderFailed
        }
        return cg
    }

    // MARK: - Bouwstenen (intern, deterministisch getest — Vision herkent
    // synthetische testbeelden niet als gezicht, dus de geometrie- en
    // kleurwiskunde is pure-function getest, het happy path handmatig)

    static func largestFace(_ observations: [VNFaceObservation]?) -> VNFaceObservation? {
        observations?.max {
            $0.boundingBox.width * $0.boundingBox.height
                < $1.boundingBox.width * $1.boundingBox.height
        }
    }

    /// Genormaliseerde landmark-punten (t.o.v. de face-bbox, bottom-left)
    /// naar pixelcoördinaten, origin BOTTOM-LEFT (CI-ruimte). Let op: dit
    /// wijkt bewust af van AutoFramer/ClothesMaskGenerator (top-left) —
    /// alle geometrie hier voedt CGContext/CI, beide bottom-left, zodat er
    /// nergens een y-flip nodig is.
    static func pixelPoints(
        normalized: [CGPoint], boundingBox: CGRect, imageSize: CGSize
    ) -> [CGPoint] {
        normalized.map { p in
            CGPoint(
                x: (boundingBox.origin.x + p.x * boundingBox.width) * imageSize.width,
                y: (boundingBox.origin.y + p.y * boundingBox.height) * imageSize.height
            )
        }
    }

    /// Shoelace-oppervlakte van een gesloten polygon.
    static func polygonArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// Bounding-rect van de polygon, met padding, geklemd op de extent.
    static func boundingRect(
        of points: [CGPoint], padding: CGFloat, clampedTo extent: CGRect
    ) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(
            x: minX - padding, y: minY - padding,
            width: (maxX - minX) + padding * 2, height: (maxY - minY) + padding * 2
        ).intersection(extent)
    }

    /// Grayscale masker (wit = binnen de polygon) met Gaussische feather.
    /// Punten in bottom-left pixelcoördinaten (zie `pixelPoints`).
    static func polygonMask(points: [CGPoint], extent: CGRect, feather: CGFloat) -> CIImage {
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: extent)
        let w = Int(extent.width.rounded()), h = Int(extent.height.rounded())
        guard points.count >= 3, w > 0, h > 0,
              let ctx = CGContext(
                  data: nil, width: w, height: h, bitsPerComponent: 8,
                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            return black
        }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.beginPath()
        ctx.addLines(between: points)
        ctx.closePath()
        ctx.fillPath()
        guard let cg = ctx.makeImage() else { return black }
        var mask = CIImage(cgImage: cg)
        if feather > 0 {
            mask = mask.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather])
        }
        return mask.cropped(to: extent)
    }

    /// Cube-data (RGBA floats, r snelst) voor de emaille-poort: wit waar
    /// een sRGB-kleur als tand-emaille kwalificeert, zwart elders.
    /// Regels: luminantie ≥ vloer, verzadiging ≤ `maxEnamelSaturation`,
    /// niet uitgesproken rood (lip/tandvlees) en niet blauw-dominant.
    static func enamelGateCubeData(dimension: Int, luminanceFloor: Double) -> Data {
        var values = [Float]()
        values.reserveCapacity(dimension * dimension * dimension * 4)
        let n = Double(dimension - 1)
        for bi in 0..<dimension {
            let b = Double(bi) / n
            for gi in 0..<dimension {
                let g = Double(gi) / n
                for ri in 0..<dimension {
                    let r = Double(ri) / n
                    let pass = isEnamel(r: r, g: g, b: b, luminanceFloor: luminanceFloor)
                    let v: Float = pass ? 1 : 0
                    values.append(contentsOf: [v, v, v, 1])
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// De poortregel zelf, op sRGB-componenten [0,1].
    static func isEnamel(r: Double, g: Double, b: Double, luminanceFloor: Double) -> Bool {
        guard luma(r: r, g: g, b: b) >= luminanceFloor else { return false }
        let saturation = max(r, g, b) - min(r, g, b)
        guard saturation <= maxEnamelSaturation else { return false }
        // Lippen/tandvlees: rood domineert groen én blauw.
        if r - g > 0.15 && r - b > 0.25 { return false }
        // Blauw-dominant (koele achtergrond-doorschijn): geen emaille.
        if b - (r + g) / 2 > 0.08 { return false }
        return true
    }

    /// Past de emaille-poort toe. Via CIColorCubeWithColorSpace zodat de
    /// cube op sRGB-waarden werkt (de poortdrempels zijn sRGB-getuned),
    /// onafhankelijk van de (lineaire) working space.
    static func enamelGate(on image: CIImage, luminanceFloor: Double) -> CIImage {
        let dimension = 32
        return image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": enamelGateCubeData(
                dimension: dimension, luminanceFloor: luminanceFloor
            ),
            "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!,
        ])
    }

    /// tandmasker = geometrie × poort, geklemd, met een kleine tweede
    /// feather zodat de emaille-rand zacht overloopt.
    static func combinedMask(
        geometry: CIImage, gate: CIImage, extent: CGRect, feather: CGFloat
    ) -> CIImage {
        var mask = gate.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: geometry
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ])
        if feather > 0 {
            mask = mask.cropped(to: extent).clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather])
        }
        return mask.cropped(to: extent)
    }

    /// Gemiddelde kleur (sRGB-gecodeerd, [0,1]) over een sub-rect via
    /// CIAreaAverage. Het gemiddelde wordt in de lineaire working space
    /// genomen en daarna per kanaal sRGB-gecodeerd, zodat de poort- en
    /// sterkteconstanten in vertrouwde sRGB-termen staan.
    static func meanColor(of image: CIImage, in rect: CGRect) -> (r: Double, g: Double, b: Double) {
        let pixel = averagePixel(of: image, in: rect)
        return (srgbEncoded(pixel.0), srgbEncoded(pixel.1), srgbEncoded(pixel.2))
    }

    /// Masker-gewogen gemiddelde kleur binnen `rect` (sRGB-gecodeerd) plus
    /// de dekking. De deling gebeurt in linear (mean(beeld × masker) /
    /// mean(masker)); de dekking blijft linear omdat het gemiddelde van een
    /// 0/1-masker dáár precies de oppervlaktefractie is.
    static func maskedAverage(
        _ image: CIImage, mask: CIImage, in rect: CGRect
    ) -> (r: Double, g: Double, b: Double, coverage: Double) {
        // CIAreaAverage middelt alleen over de eigen extent van het beeld;
        // een masker kleiner dan `rect` zou de dekking kunstmatig opblazen.
        // Op zwart uitvullen maakt de dekking een echte oppervlaktefractie.
        let mask = mask.composited(
            over: CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: rect)
        )
        let product = image.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: mask
        ])
        let productMean = averagePixel(of: product, in: rect)
        let coverage = averagePixel(of: mask, in: rect).0
        guard coverage > 0.0001 else { return (0, 0, 0, 0) }
        return (
            srgbEncoded(productMean.0 / coverage),
            srgbEncoded(productMean.1 / coverage),
            srgbEncoded(productMean.2 / coverage),
            coverage
        )
    }

    /// Adaptieve sterkte uit de gemeten tandkleur: hoe geler, hoe meer
    /// desaturatie (geklemd tegen grijze tanden); gamma-lift richting
    /// `targetLuma` (macht < 1 licht middentonen zonder highlight-clipping,
    /// ≈ no-op wanneer de tanden al licht zijn).
    static func whiteningParams(
        r: Double, g: Double, b: Double
    ) -> (desaturation: Double, gammaPower: Double) {
        let yellowness = max(0, (r + g) / 2 - b)
        let desaturation = min(
            max(2.2 * yellowness + 0.15, desaturationRange.lowerBound),
            desaturationRange.upperBound
        )
        let measuredLuma = min(max(luma(r: r, g: g, b: b), 0.05), 0.98)
        let gammaPower: Double
        if measuredLuma >= targetLuma {
            gammaPower = 1.0
        } else {
            gammaPower = min(max(log(targetLuma) / log(measuredLuma), minGammaPower), 1.0)
        }
        return (desaturation, gammaPower)
    }

    /// De bleeklaag: desaturatie (haalt het geel weg) + gamma-lift.
    /// Machten commuteren met de sRGB-gamma, dus de in sRGB gemeten
    /// `gammaPower` klopt ook in de lineaire working space.
    static func whitened(
        _ source: CIImage, desaturation: Double, gammaPower: Double
    ) -> CIImage {
        var current = source.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1 - desaturation,
            kCIInputBrightnessKey: 0,
            kCIInputContrastKey: 1,
        ])
        if gammaPower < 1 {
            current = current.applyingFilter("CIGammaAdjust", parameters: [
                "inputPower": gammaPower
            ])
        }
        return current
    }

    /// Composiet: bleeklaag alléén binnen het masker, origineel elders.
    /// Beide lagen dragen de bron-alpha → alpha per constructie behouden.
    static func composite(source: CIImage, whitened: CIImage, mask: CIImage) -> CIImage {
        whitened.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: source,
            "inputMaskImage": mask,
        ]).cropped(to: source.extent)
    }

    /// Rec. 709-luminantie op sRGB-componenten.
    static func luma(r: Double, g: Double, b: Double) -> Double {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Standaard sRGB-transfercurve (linear → gecodeerd).
    static func srgbEncoded(_ v: Double) -> Double {
        let c = min(max(v, 0), 1)
        return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055
    }

    /// 1×1 CIAreaAverage-render over een sub-rect. `colorSpace: nil` zoals
    /// ClothesMaskGenerator.meanLuminance: rauwe working-space-waarden
    /// (linear), zonder outputconversie.
    private static func averagePixel(
        of image: CIImage, in rect: CGRect
    ) -> (Double, Double, Double) {
        let average = image.applyingFilter("CIAreaAverage", parameters: [
            kCIInputExtentKey: CIVector(cgRect: rect)
        ])
        var pixel = [UInt8](repeating: 0, count: 4)
        EngineRendering.standardContext.render(
            average, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil
        )
        return (Double(pixel[0]) / 255.0, Double(pixel[1]) / 255.0, Double(pixel[2]) / 255.0)
    }
}
