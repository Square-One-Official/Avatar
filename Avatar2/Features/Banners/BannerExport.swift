// Banner-export via NSSavePanel (E37.6). Gedeeld door de studio en de shell-topbar.

import AppKit
import UniformTypeIdentifiers

enum BannerExport {
    /// Rendert off-main via de gedeelde `BannerDocRenderer.composedImageAsync`
    /// (geen eigen render→bake→watermark-kopie meer; identiek beeld) en toont
    /// daarna de save-panel op de main-actor.
    @MainActor
    static func presentSavePanel(doc: BannerDoc, isPro: Bool) async {
        guard let cg = await BannerDocRenderer.composedImageAsync(doc, watermark: !isPro),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (doc.name.isEmpty ? "banner" : doc.name) + ".png"
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }
}
