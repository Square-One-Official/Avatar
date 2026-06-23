// Portrait-modus achtergrond-blur (Thierry 2026-06-23). Eén vaste, smaakvolle
// Gaussiaanse blur op de achtergrondLAAG (origineel of custom afbeelding),
// gedeeld door álle render-paden (live canvas, export, board) zodat ze WYSIWYG
// matchen. De radius is een FRACTIE van de langste zijde, zodat dezelfde sterkte
// op elke resolutie (canvas-punten, 1024-export, board-thumb) gelijk oogt.
//
// Het onderwerp (scherpe cutout) composit de aanroeper er BOVENOP; hier vervagen
// we alleen het achtergrondbeeld. Een vlakke kleur-achtergrond heeft geen blur
// nodig (blur van één kleur = dezelfde kleur) — aanroepers slaan die over.

import CoreGraphics
import CoreImage

enum BackgroundBlur {
    /// Blur-radius als fractie van de langste zijde (≈ macOS-Portrait-sterkte).
    static let radiusFraction: CGFloat = 0.04

    /// Gedeelde GPU-CIContext — de blur draait los van de main-thread-decode.
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Gaussiaanse blur op `image`. Clampt eerst (geen transparante rand-halo) en
    /// snijdt terug naar de originele extent. nil bij renderfout.
    static func blurred(_ image: CGImage) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let radius = radiusFraction * CGFloat(max(image.width, image.height))
        guard radius > 0, let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        filter.setValue(CIImage(cgImage: image).clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage,
              let out = context.createCGImage(output, from: extent) else { return nil }
        return out
    }

    /// SwiftUI-blur-radius voor een live-canvas-laag van `side` punten, zodat de
    /// preview dezelfde fractie-blur toont als de export.
    static func canvasRadius(side: CGFloat) -> CGFloat { radiusFraction * side }
}
