import CoreGraphics
import Foundation

/// E02.5 (audit-B1): normaliseert importbeelden naar sRGB-RGBA8.
///
/// De cutout-engines renderen hun eindresultaat naar `.RGBA8`; dat formaat
/// is alleen compatibel met een RGB-kleurruimte. Een grayscale-PNG
/// (DeviceGray) of CMYK-JPEG gaf daardoor `createCGImage` = nil →
/// `renderFailed` — in béide engines, dus de router-cascade redde niets.
/// Deze helper is de éne plek waar elke import vóór de engines naar
/// sRGB-RGBA gaat (ShellModel.runCutout); hij dekt daarmee ook toekomstige
/// consumers van het importbeeld (AutoFramer, ClothesMaskGenerator).
public enum SRGBNormalizer {
    /// Geeft het beeld terug in 8-bit sRGB-RGBA. Al genormaliseerd →
    /// hetzelfde object, zonder kopie. Kan het hertekenen onverhoopt niet
    /// (CGContext/makeImage nil), dan komt het origineel terug — de
    /// engine-guards (`EngineRendering.outputColorSpace`) vangen dat geval
    /// alsnog op.
    public static func normalized(_ image: CGImage) -> CGImage {
        if isNormalized(image) { return image }
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: image.width, height: image.height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return image }
        ctx.interpolationQuality = .none // 1:1-hertekening, geen resample
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    /// Is dit al 8-bit sRGB-RGBA (in gewone big-endian bytevolgorde)?
    /// Wide-gamut (Display P3 e.d.) telt bewust níét als genormaliseerd:
    /// élke import gaat naar sRGB, zodat alles downstream (engines,
    /// PNG-opslag, export) in één kleurruimte leeft.
    static func isNormalized(_ image: CGImage) -> Bool {
        guard let name = image.colorSpace?.name,
              (name as String) == (CGColorSpace.sRGB as String),
              image.bitsPerComponent == 8,
              image.bitsPerPixel == 32 else { return false }
        let byteOrder = image.bitmapInfo.intersection(.byteOrderMask)
        guard byteOrder == [] || byteOrder == .byteOrder32Big else { return false }
        switch image.alphaInfo {
        case .premultipliedLast, .last, .noneSkipLast: return true
        default: return false
        }
    }
}
