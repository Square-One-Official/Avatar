// E37.8 + E37.11 — Interactieve canvas-overlay: tik om te selecteren, sleep om
// tekst/logo te verplaatsen of (Background-tool) het image-fill te reframen.

import AppKit
import AvatarUI
import SwiftUI

struct BannerCanvasOverlay: View {
    @Bindable var doc: BannerDoc
    @Binding var selection: BannerCanvasSelection?
    let activeTool: BannerTool?
    let canvasSize: CGSize
    let undoManager: UndoManager?

    @State private var dragStartLayers: BannerLayers?
    @State private var dragStartDocument: BannerDocUndo.DocumentSnapshot?
    @State private var dragStartCanvasPoint: CGPoint?
    @State private var dragMode: DragMode?

    private enum DragMode {
        case moveLayer
        case reframeBackground
    }

    private static let space = "bannerCanvas"

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.size
            let scale = min(frame.width / canvasSize.width, frame.height / canvasSize.height)
            let drawn = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
            let origin = CGPoint(
                x: (frame.width - drawn.width) / 2,
                y: (frame.height - drawn.height) / 2
            )

            ZStack {
                selectionRing(drawn: drawn, origin: origin, scale: scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(canvasGesture(drawn: drawn, origin: origin, scale: scale))
            .coordinateSpace(name: Self.space)
        }
    }

    // MARK: Selection ring

    @ViewBuilder
    private func selectionRing(drawn: CGSize, origin: CGPoint, scale: CGFloat) -> some View {
        if let rect = selectedRect(scale: scale) {
            let screen = CGRect(
                x: origin.x + rect.minX * scale,
                y: origin.y + rect.minY * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(DSColor.Action.primaryForeground.opacity(0.9), lineWidth: 1.5)
                .frame(width: screen.width, height: screen.height)
                .position(x: screen.midX, y: screen.midY)
                .allowsHitTesting(false)
                .animation(DSMotion.micro, value: selection)
        }
    }

    private func selectedRect(scale: CGFloat) -> CGRect? {
        _ = scale
        switch selection {
        case let .text(id):
            guard let layer = doc.layers.texts.first(where: { $0.id == id }) else { return nil }
            return BannerLayoutMetrics.textRect(layer: layer, canvas: canvasSize)
        case .logo:
            guard let logo = doc.layers.logo,
                  let data = doc.logoImageData,
                  let cg = BannerDocRenderer.cgImage(from: data) else { return nil }
            return BannerLayoutMetrics.logoRect(layer: logo, logoImage: cg, canvas: canvasSize)
        case nil:
            return nil
        }
    }

    // MARK: Gestures

    private func canvasGesture(drawn: CGSize, origin: CGPoint, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let canvasPoint = screenToCanvas(value.location, drawn: drawn, origin: origin, scale: scale)
                if dragMode == nil {
                    beginDrag(at: canvasPoint, startLocation: value.startLocation, drawn: drawn, origin: origin, scale: scale)
                }
                applyDrag(to: canvasPoint)
            }
            .onEnded { _ in
                endDrag()
            }
    }

    private func beginDrag(
        at canvasPoint: CGPoint,
        startLocation: CGPoint,
        drawn: CGSize,
        origin: CGPoint,
        scale: CGFloat
    ) {
        _ = startLocation; _ = drawn; _ = origin; _ = scale
        dragStartCanvasPoint = canvasPoint
        if activeTool == .background, doc.layers.fill == .image, doc.fillImageData != nil {
            dragMode = .reframeBackground
            dragStartDocument = BannerDocUndo.snapshot(of: doc)
            return
        }
        if selection == nil {
            selection = BannerLayoutMetrics.hitTest(at: canvasPoint, doc: doc, canvas: canvasSize)
        }
        if selection != nil {
            dragMode = .moveLayer
            dragStartLayers = doc.layers
        }
    }

    private func applyDrag(to canvasPoint: CGPoint) {
        guard let mode = dragMode else { return }
        switch mode {
        case .moveLayer:
            moveSelection(to: canvasPoint)
        case .reframeBackground:
            reframeBackground(dragDelta: canvasPoint)
        }
    }

    private func moveSelection(to canvasPoint: CGPoint) {
        let nx = min(1, max(0, canvasPoint.x / canvasSize.width))
        let ny = min(1, max(0, canvasPoint.y / canvasSize.height))
        var layers = doc.layers
        switch selection {
        case let .text(id):
            guard let i = layers.texts.firstIndex(where: { $0.id == id }) else { return }
            layers.texts[i].x = nx
            layers.texts[i].y = ny
        case .logo:
            guard layers.logo != nil else { return }
            layers.logo?.x = nx
            layers.logo?.y = ny
        case nil:
            return
        }
        doc.layers = layers
    }

    private func reframeBackground(dragDelta canvasPoint: CGPoint) {
        guard let start = dragStartDocument, let origin = dragStartCanvasPoint else { return }
        let dx = (canvasPoint.x - origin.x) / canvasSize.width
        let dy = (canvasPoint.y - origin.y) / canvasSize.height
        doc.fillImageFocalX = min(1, max(0, start.fillImageFocalX - dx * 0.6))
        doc.fillImageFocalY = min(1, max(0, start.fillImageFocalY - dy * 0.6))
    }

    private func endDrag() {
        let mode = dragMode
        let beforeLayers = dragStartLayers
        let beforeDocument = dragStartDocument
        dragMode = nil
        dragStartLayers = nil
        dragStartDocument = nil
        dragStartCanvasPoint = nil
        if mode == .moveLayer, let before = beforeLayers, before != doc.layers {
            BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: doc.layers, actionName: "Move")
        }
        if mode == .reframeBackground, let before = beforeDocument {
            let after = BannerDocUndo.snapshot(of: doc)
            if before != after {
                BannerDocUndo.registerDocument(undoManager, doc: doc, from: before, to: after, actionName: "Background")
            }
        }
    }

    private func screenToCanvas(_ point: CGPoint, drawn: CGSize, origin: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: (point.x - origin.x) / scale,
            y: (point.y - origin.y) / scale
        )
    }
}
