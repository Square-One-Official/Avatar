// E37.16 — Chrome voor een multi-selectie (≥2 elementen): een lichte omlijning per
// element, de gezamenlijke bounding box, 4 hoek-handles om de groep uniform te
// schalen, en de floating uitlijn-toolbar. Schaal-handles meten in de stabiele
// `bannerCanvas`-coordinate space (zoals de single-handles) zodat ze niet
// oscilleren wanneer de box onder de cursor meebeweegt.

import AvatarUI
import SwiftUI

struct BannerCanvasMultiSelectChrome: View {
    @Bindable var doc: BannerDoc
    @Binding var selection: Set<BannerElementRef>
    let canvasSize: CGSize
    let layout: BannerCanvasChromeMetrics.Layout
    let undoManager: UndoManager?

    @State private var scaleStartDistance: CGFloat?
    @State private var scaleAnchorScreen: CGPoint?
    @State private var scaleAnchorCanvas: CGPoint?
    @State private var baseLayers: BannerLayers?
    @State private var layersBeforeScale: BannerLayers?

    var body: some View {
        if selection.count >= 2,
           let boundsCanvas = BannerGroupTransform.combinedRect(selection, doc: doc, canvas: canvasSize) {
            let bounds = BannerCanvasChromeMetrics.screenRect(canvasRect: boundsCanvas, layout: layout)
            ZStack {
                ForEach(elementRects(), id: \.0) { _, rect in
                    Rectangle()
                        .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .frame(width: bounds.width + 12, height: bounds.height + 12)
                    .position(x: bounds.midX, y: bounds.midY)
                    .allowsHitTesting(false)

                let box = bounds.insetBy(dx: -6, dy: -6)
                cornerHandle(at: CGPoint(x: box.minX, y: box.minY))
                cornerHandle(at: CGPoint(x: box.maxX, y: box.minY))
                cornerHandle(at: CGPoint(x: box.minX, y: box.maxY))
                cornerHandle(at: CGPoint(x: box.maxX, y: box.maxY))

                BannerMultiSelectToolbar(count: selection.count, onAlign: align)
                    .fixedSize()
                    .position(x: bounds.midX, y: bounds.minY - 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Schermrects (id + rect) van elk geselecteerd element, voor de omlijningen.
    private func elementRects() -> [(String, CGRect)] {
        selection.compactMap { ref in
            guard let r = BannerGroupTransform.rect(of: ref, doc: doc, canvas: canvasSize) else { return nil }
            let screen = BannerCanvasChromeMetrics.screenRect(canvasRect: r, layout: layout)
            let key: String = {
                switch ref {
                case let .text(id): return "t-\(id.uuidString)"
                case .logo: return "logo"
                }
            }()
            return (key, screen)
        }
    }

    private func cornerHandle(at point: CGPoint) -> some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .contentShape(Circle())
            .position(x: point.x, y: point.y)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(BannerCanvasOverlay.space))
                    .onChanged { value in beginOrUpdateScale(value) }
                    .onEnded { _ in endScale() }
            )
    }

    private func beginOrUpdateScale(_ value: DragGesture.Value) {
        if scaleStartDistance == nil {
            guard let boundsCanvas = BannerGroupTransform.combinedRect(selection, doc: doc, canvas: canvasSize) else { return }
            let bounds = BannerCanvasChromeMetrics.screenRect(canvasRect: boundsCanvas, layout: layout)
            let anchorScreen = CGPoint(x: bounds.midX, y: bounds.midY)
            scaleAnchorScreen = anchorScreen
            scaleAnchorCanvas = CGPoint(x: boundsCanvas.midX, y: boundsCanvas.midY)
            scaleStartDistance = max(8, hypot(value.startLocation.x - anchorScreen.x,
                                              value.startLocation.y - anchorScreen.y))
            baseLayers = doc.layers
            layersBeforeScale = doc.layers
        }
        guard let startDist = scaleStartDistance,
              let anchorScreen = scaleAnchorScreen,
              let anchorCanvas = scaleAnchorCanvas,
              let base = baseLayers else { return }
        let dist = hypot(value.location.x - anchorScreen.x, value.location.y - anchorScreen.y)
        let factor = max(0.05, dist / startDist)
        doc.layers = BannerGroupTransform.scaled(
            base, refs: selection, canvas: canvasSize, factor: factor, anchor: anchorCanvas
        )
    }

    private func endScale() {
        if let before = layersBeforeScale, before != doc.layers {
            BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: doc.layers, actionName: "Scale selection")
        }
        scaleStartDistance = nil
        scaleAnchorScreen = nil
        scaleAnchorCanvas = nil
        baseLayers = nil
        layersBeforeScale = nil
    }

    private func align(_ axis: BannerGroupTransform.AlignAxis) {
        let before = doc.layers
        let after = BannerGroupTransform.aligned(before, refs: selection, doc: doc, canvas: canvasSize, axis: axis)
        guard before != after else { return }
        doc.layers = after
        BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: after, actionName: "Align")
    }
}
