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

    private static func faceRegion(in image: CGImage) -> CGRect? {
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
