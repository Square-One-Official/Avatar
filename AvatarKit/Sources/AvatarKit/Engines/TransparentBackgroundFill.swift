// Alpha-bewuste achtergrondvulling vóór het matten (2026-09-03, Thierry:
// Figma-avatars op een gradient-schijf met transparante hoeken). Matting-
// modellen zien transparant als zwart; een schijf wordt dan een harde vorm
// op zwart en gaat als "object" mee in de matte. Vullen we de transparante
// pixels met de doorgetrokken randkleur (meerlaagse genormaliseerde blur —
// rgb·α / α, van grof naar fijn), dan verdwijnt de vorm en ziet het model
// gewoon een persoon op een gradient, precies als bij een vierkante foto.
// De uiteindelijke cutout wordt daarna weer op het bron-alpha begrensd.

import CoreGraphics
import CoreImage
import Foundation
import ImageIO

enum TransparentBackgroundFill {

    /// Gevulde variant van `image`, of nil als er niets te vullen is (geen
    /// alpha-kanaal, of nergens transparant).
    static func filled(_ image: CGImage) -> CGImage? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return nil
        default: break
        }
        let source = CIImage(cgImage: image)
        let extent = source.extent
        guard minimumAlpha(of: source, extent: extent) < 0.98 else { return nil }

        let longEdge = Double(max(extent.width, extent.height))
        // Grof → fijn: per laag een genormaliseerde blur (rgb·α / α = lokaal
        // gemiddelde van de opake buren) met een HARDE dekkingsdrempel, zodat de
        // fijnste laag die überhaupt buren heeft wint. Dat benadert "kleur van
        // de dichtstbijzijnde randpixel": een gradient-schijf loopt naadloos
        // door in de hoeken. Een zachte overgang zou de schijfkleuren tot een
        // grauw gemiddelde mengen en de schijf als heldere cirkel laten staan.
        // Startvlak = grof gemiddelde voor de allerverste hoeken.
        let coarse = source.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: longEdge * 0.5])
            .cropped(to: extent)
        var fill = coarse.unpremultiplyingAlpha().settingAlphaOne(in: extent)
        for fraction in [0.25, 0.12, 0.06, 0.03, 0.015, 0.0075, 0.003] {
            let blurred = source
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: longEdge * fraction])
                .cropped(to: extent)
            let extended = blurred.unpremultiplyingAlpha().settingAlphaOne(in: extent)
            let coverage = alphaAsGray(blurred, extent: extent)
                .applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.02])
                .cropped(to: extent)
            fill = extended.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: fill,
                "inputMaskImage": coverage,
            ]).cropped(to: extent)
        }
        let composed = source.composited(over: fill).cropped(to: extent)
        let result = EngineRendering.linearContext.createCGImage(
            composed, from: extent, format: .RGBA8, colorSpace: EngineRendering.outputColorSpace(for: image)
        )
        #if DEBUG
        if let dumpDir = ProcessInfo.processInfo.environment["AVATAR_CUTOUT_PROBE_DUMP"], let result,
           let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: "\(dumpDir)/fill-input.png") as CFURL, "public.png" as CFString, 1, nil
           ) {
            CGImageDestinationAddImage(dest, result, nil); CGImageDestinationFinalize(dest)
        }
        #endif
        return result
    }

    /// `cutout` begrensd op het alpha van `original`: buiten de opake bron
    /// mag niets overblijven (vulkleur, matte-lek).
    static func confine(_ cutout: CGImage, toAlphaOf original: CGImage) -> CGImage? {
        let result = CIImage(cgImage: cutout)
        let extent = result.extent
        let mask = alphaAsGray(CIImage(cgImage: original), extent: extent)
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        let confined = result.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            "inputMaskImage": mask,
        ]).cropped(to: extent)
        return EngineRendering.linearContext.createCGImage(
            confined, from: extent, format: .RGBA8, colorSpace: EngineRendering.outputColorSpace(for: cutout)
        )
    }

    /// Alpha-kanaal als grijswaarde (alpha zelf = 1).
    static func alphaAsGray(_ image: CIImage, extent: CGRect) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: extent)
    }

    private static func minimumAlpha(of image: CIImage, extent: CGRect) -> Float {
        let minimum = image.applyingFilter("CIAreaMinimumAlpha", parameters: [
            kCIInputExtentKey: CIVector(cgRect: extent)
        ])
        var pixel = [Float](repeating: 1, count: 4)
        EngineRendering.linearContext.render(
            minimum, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBAf, colorSpace: nil
        )
        return pixel[3]
    }
}
