import CoreImage
import CoreImage.CIFilterBuiltins

/// Set-brede lichtnormalisatie (E12.2): trekt de globale belichting/kleur-
/// balans van meerdere portretten naar één referentie, zodat een set er als
/// één fotoshoot uitziet. Lokaal (Core Image), geen cloud/credits.
///
/// Bekende beperking (v1-pariteit): dit is een **globale** gemiddelde-kleur-
/// match (per-kanaal gain), geen lokale relighting of contrast-matching —
/// sterk afwijkende opnames trekken niet perfect gelijk. De gemiddelden
/// worden op een grijs-geflattende kopie berekend (vaste neutrale
/// achtergrond, dus alpha-onafhankelijk en stabiel); de gain wordt op het
/// originele cutout (met alpha) toegepast.
public enum SetLightingNormalizer {
    public struct Stats: Equatable, Sendable {
        public let r: Double
        public let g: Double
        public let b: Double
        public init(r: Double, g: Double, b: Double) {
            self.r = r; self.g = g; self.b = b
        }
        /// Rec. 601-luma, handig voor tests/sortering.
        public var luma: Double { 0.299 * r + 0.587 * g + 0.114 * b }
    }

    private static let context = CIContext()
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Gemiddelde kleur van het portret, berekend op een grijs-geflattende
    /// kopie zodat transparante randen het gemiddelde niet vertekenen.
    public static func referenceStats(of image: CGImage) -> Stats? {
        flattenedAverage(of: image)
    }

    /// Past per-kanaal gain toe zodat het gemiddelde van `image` naar `ref`
    /// schuift. Gains geklemd op [0.6, 1.6] om uitschieters te dempen. De
    /// alpha blijft behouden (cutout blijft een cutout). nil bij renderfout.
    public static func match(_ image: CGImage, to ref: Stats) -> CGImage? {
        guard let s = flattenedAverage(of: image) else { return nil }
        let gr = gain(ref.r, s.r)
        let gg = gain(ref.g, s.g)
        let gb = gain(ref.b, s.b)

        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = CIImage(cgImage: image)
        matrix.rVector = CIVector(x: gr, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: gg, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: gb, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        guard let out = matrix.outputImage else { return nil }
        return render(out, like: image)
    }

    private static func gain(_ reference: Double, _ value: Double) -> CGFloat {
        CGFloat(min(max(reference / max(value, 0.01), 0.6), 1.6))
    }

    private static func flattenedAverage(of image: CGImage) -> Stats? {
        let ci = CIImage(cgImage: image)
        let grey = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: ci.extent)
        let composited = ci.composited(over: grey)

        let avg = CIFilter.areaAverage()
        avg.inputImage = composited
        avg.extent = composited.extent
        guard let out = avg.outputImage else { return nil }

        var px = [UInt8](repeating: 0, count: 4)
        context.render(
            out, toBitmap: &px, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: sRGB
        )
        return Stats(r: Double(px[0]) / 255, g: Double(px[1]) / 255, b: Double(px[2]) / 255)
    }

    private static func render(_ ci: CIImage, like image: CGImage) -> CGImage? {
        let extent = CIImage(cgImage: image).extent
        let colorSpace = image.colorSpace ?? sRGB
        return context.createCGImage(
            ci.cropped(to: extent), from: extent, format: .RGBA8, colorSpace: colorSpace
        )
    }
}
