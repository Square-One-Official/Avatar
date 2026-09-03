import CoreGraphics
import CoreImage
import Foundation

/// Dominante-kleur-bemonstering (E34.1): leidt een vlakke kleur af uit een
/// beeld. Gebruikt door de banner-"Match avatar"-modus wanneer de portret-
/// achtergrond géén vlakke kleur is (transparant/origineel): dan wordt de
/// achtergrondkleur uit het beeld gesampled i.p.v. geraden.
///
/// Bemonstering via `CIAreaAverage` (zelfde precedent als
/// `ClothesMaskGenerator.meanLuminance`). Waarden in [0,1], device-sRGB.
public enum DominantColor {

    /// Gemiddelde kleur van het hele beeld.
    public static func average(_ image: CGImage) -> (r: Double, g: Double, b: Double)? {
        let ci = CIImage(cgImage: image)
        return areaAverage(ci, extent: ci.extent)
    }

    /// Gemiddelde kleur van een RAND-frame rond het beeld (vier strips). Beter
    /// voor "de achtergrondkleur" van een portret waar het onderwerp het
    /// midden domineert — de rand is doorgaans pure achtergrond. `inset` is de
    /// stripdikte als fractie van de kortste zijde (default 4%).
    public static func edge(_ image: CGImage, inset: CGFloat = 0.04) -> (r: Double, g: Double, b: Double)? {
        let ci = CIImage(cgImage: image)
        let ext = ci.extent
        guard ext.width > 1, ext.height > 1 else { return average(image) }
        let t = max(1, min(ext.width, ext.height) * inset)

        // CIImage heeft een bottom-left origin. Vier strips langs de randen;
        // elk area-gemiddelde wordt gewogen op zijn oppervlak gemiddeld (de
        // hoeken tellen zo licht dubbel, verwaarloosbaar t.o.v. de winst van
        // één pass per strip).
        let strips: [CGRect] = [
            CGRect(x: ext.minX, y: ext.maxY - t, width: ext.width, height: t),   // top
            CGRect(x: ext.minX, y: ext.minY, width: ext.width, height: t),       // bottom
            CGRect(x: ext.minX, y: ext.minY, width: t, height: ext.height),      // left
            CGRect(x: ext.maxX - t, y: ext.minY, width: t, height: ext.height),  // right
        ]

        var rSum = 0.0, gSum = 0.0, bSum = 0.0, wSum = 0.0
        for strip in strips {
            guard let c = areaAverage(ci, extent: strip) else { continue }
            let weight = Double(strip.width * strip.height)
            rSum += c.r * weight; gSum += c.g * weight; bSum += c.b * weight; wSum += weight
        }
        guard wSum > 0 else { return average(image) }
        return (rSum / wSum, gSum / wSum, bSum / wSum)
    }

    private static func areaAverage(_ image: CIImage, extent: CGRect) -> (r: Double, g: Double, b: Double)? {
        guard extent.width > 0, extent.height > 0 else { return nil }
        let average = image.applyingFilter("CIAreaAverage", parameters: [
            kCIInputExtentKey: CIVector(cgRect: extent)
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
