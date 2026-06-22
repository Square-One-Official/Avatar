// E27.6 (Tier 3): off-main thumbnail-decoder. Decodeert cutout-Data DIRECT op
// doelmaat via ImageIO (`kCGImageSourceThumbnailMaxPixelSize`) i.p.v. een
// volledige `NSImage(data:)`-decode + redraw — veel goedkoper, en draait buiten
// de main-thread (pure functie, geen state) zodat first-paint en in-beeld-
// scrollen op de board niet hitchen. De niet-destructieve Adjust-laag wordt in
// dezelfde pass off-main toegepast (PortraitEnhancer gebruikt een thread-safe
// gedeelde CIContext). Gedeeld door board + (later) sidebar.

import AvatarKit
import CoreGraphics
import Foundation
import ImageIO

enum ThumbnailRenderer {
    /// Decodeer + downscale `data` zodat de langste zijde ≤ `maxPixelSize` px en
    /// pas (indien niet-neutraal) de Adjust-laag toe. Alpha (cutout-transparantie)
    /// blijft behouden. nil bij ongeldige data of renderfout.
    static func render(data: Data, maxPixelSize: Int, adjust: PortraitAdjust) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        guard !adjust.isNeutral else { return thumb }
        return PortraitEnhancer.colorAdjust(
            thumb,
            brightness: adjust.brightness, contrast: adjust.contrast,
            saturation: adjust.saturation, temperatureShift: adjust.temperature
        ) ?? thumb
    }
}

/// `CGImage` is immutable CF-data → veilig over een actor-grens te reiken
/// (Sendable-box voor `targeted` strict-concurrency).
struct SendableCGImage: @unchecked Sendable {
    let cgImage: CGImage
}
