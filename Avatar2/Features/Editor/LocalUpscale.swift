// E41.2 — Lokale, on-device "Boost resolution" voor de localOnly-privacymodus.
// Geen cloud, geen credits, geen model-download (dus geen app-bloat): een
// hoogwaardige Core Image Lanczos-upscale (2×) gevolgd door een milde unsharp-
// mask. Géén AI-superresolutie — het verzint geen detail — maar een eerlijke,
// snelle "scherper + groter" die volledig offline draait. Behoudt de alpha van
// de cutout (Core Image schaalt RGBA mee).
//
// Werkt op PNG-`Data` (in→uit) zodat het Sendable over een achtergrond-Task kan;
// de gedeelde `CIContext` (GPU) is duur om te maken, dus één keer.

import AppKit
import CoreImage

enum LocalUpscale {
    /// Gedeelde GPU-context (duur om te maken → hergebruik).
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Upscalet en verscherpt een PNG (met alpha). `scale` = lineaire factor.
    /// nil bij een decode-/render-fout. Pure functie → veilig op een
    /// achtergrond-Task aan te roepen.
    static func boost(pngData: Data, scale: CGFloat = 2.0) -> Data? {
        guard let src = CIImage(data: pngData) else { return nil }

        // Hoge-kwaliteit Lanczos-upscale.
        guard let lanczos = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        lanczos.setValue(src, forKey: kCIInputImageKey)
        lanczos.setValue(scale, forKey: kCIInputScaleKey)
        lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let scaled = lanczos.outputImage else { return nil }

        // Milde unsharp-mask voor crispness (laag genoeg om alpha-randhalo's te
        // vermijden op de cutout).
        guard let sharpen = CIFilter(name: "CIUnsharpMask") else { return nil }
        sharpen.setValue(scaled, forKey: kCIInputImageKey)
        sharpen.setValue(2.0, forKey: kCIInputRadiusKey)
        sharpen.setValue(0.5, forKey: kCIInputIntensityKey)
        guard let output = sharpen.outputImage else { return nil }

        // Rasteren binnen de geschaalde extent → PNG (behoudt alpha).
        let rect = scaled.extent
        guard !rect.isInfinite,
              let cg = context.createCGImage(output, from: rect) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }
}
