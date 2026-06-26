// E37.15 — Freeform-stijl achtergrond-image: canvas-rand + floating toolbar.

import AvatarUI
import SwiftUI

struct BannerCanvasBackgroundChrome: View {
    @Bindable var doc: BannerDoc
    @Binding var selection: BannerCanvasSelection?
    let activeTool: BannerTool?
    let canvasSize: CGSize
    let layout: BannerCanvasChromeMetrics.Layout
    let undoManager: UndoManager?
    let filename: String
    var onReplace: () -> Void

    var body: some View {
        if case .backgroundFill = selection,
           doc.layers.fill == .image,
           let data = doc.fillImageData {
            let rect = BannerCanvasChromeMetrics.fullCanvasScreenRect(
                canvasSize: canvasSize,
                layout: layout
            )
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.85), lineWidth: 2)
                    .frame(width: rect.width - 4, height: rect.height - 4)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)

                BannerImageFloatingToolbar(
                    kind: .backgroundFill,
                    filename: filename,
                    byteCount: data.count,
                    imageData: data,
                    onReplace: onReplace,
                    onRemove: removeBackgroundImage
                )
                .fixedSize()
                .position(x: rect.midX, y: rect.maxY - 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func removeBackgroundImage() {
        let before = BannerDocUndo.snapshot(of: doc)
        doc.fillImageData = nil
        var layers = doc.layers
        layers.fill = .solid(hex: "#111111")
        doc.layers = layers
        let after = BannerDocUndo.snapshot(of: doc)
        BannerDocUndo.registerDocument(undoManager, doc: doc, from: before, to: after, actionName: "Remove background")
        if selection == .backgroundFill { selection = nil }
    }
}
