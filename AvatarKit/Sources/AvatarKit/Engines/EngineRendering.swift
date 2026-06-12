import CoreGraphics
import CoreImage
import Foundation

/// Gedeelde Core Image-contexten voor de cutout-engines.
enum EngineRendering {
    /// Matte-wiskunde (guided filter, blends, mask-composite) klopt alleen
    /// in linear licht; RGBAh voorkomt 8-bit banding in de zachte alpha.
    /// Input krijgt sRGB→linear, output linear→sRGB.
    static let linearContext: CIContext = {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        return CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: linear,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .workingFormat: NSNumber(value: CIFormat.RGBAh.rawValue),
        ])
    }()

    /// Default-context voor renders die juist *niet* in linear moeten —
    /// zoals de modelinput van OrmbgEngine: het model verwacht gewone
    /// sRGB-bytes (de ×1/255-preprocessing zit in het model gebakken).
    static let standardContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Schaalt een masker naar de doel-extent (Vision/CoreML-maskers komen
    /// op model- of inputresolutie terug).
    static func scaled(_ mask: CIImage, to extent: CGRect) -> CIImage {
        let sx = extent.width / mask.extent.width
        let sy = extent.height / mask.extent.height
        return mask
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .cropped(to: extent)
    }
}
