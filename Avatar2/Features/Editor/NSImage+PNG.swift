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
}
