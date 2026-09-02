// Gedeelde PNG-encode (audit-cleanup, SwiftUI/DDD): de subject-panelen
// (Effects/Hair/Clothes) + EditorView hadden elk een identieke private
// `pngData(from:)`. Eén `NSImage.pngData()` vervangt die duplicaten.

import AppKit

extension NSImage {
    /// PNG-bytes van het beeld via de TIFF-rep (zelfde pad als de oude
    /// per-feature helpers). `nil` als er geen bitmap-rep te maken is.
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Bitmap-afmetingen in pixels, ongeacht DPI / `size` (punten).
    ///
    /// AutoFramer, export en de canvas-transform rekenen in deze ruimte.
    /// Cloud-boost (en PNG-roundtrips) leveren vaak 72-DPI-bytes terwijl de
    /// bron-cutout 144 DPI had — `size` springt dan terwijl de pixels de
    /// echte schaal zijn. Layout op `size` zou het onderwerp groter tekenen
    /// en Auto-frame buiten het canvas duwen.
    var pixelLayoutSize: CGSize {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width > 0, cg.height > 0 else { return size }
        return CGSize(width: cg.width, height: cg.height)
    }

    /// Zelfde pixels, `size` = pixelmaat (72 DPI). Zo blijft een later
    /// `NSImage(data:)`-decode in de pas met AutoFramer/export.
    func normalizedToPixelSize() -> NSImage {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width > 0, cg.height > 0 else { return self }
        let px = NSSize(width: cg.width, height: cg.height)
        guard size != px else { return self }
        return NSImage(cgImage: cg, size: px)
    }
}
