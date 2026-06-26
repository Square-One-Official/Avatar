// E37.8 + E37.11 + E37.13–37.15 — Canvas-overlay: Freeform tekst, logo en achtergrond-image.

import AppKit
import AvatarUI
import SwiftUI

struct BannerCanvasOverlay: View {
    @Bindable var doc: BannerDoc
    @Binding var selection: BannerCanvasSelection?
    @Binding var isEditingText: Bool
    @Binding var logoFilename: String
    @Binding var backgroundFilename: String
    let activeTool: BannerTool?
    let canvasSize: CGSize
    let undoManager: UndoManager?

    @State private var dragStartLayers: BannerLayers?
    @State private var dragStartDocument: BannerDocUndo.DocumentSnapshot?
    @State private var dragStartCanvasPoint: CGPoint?
    @State private var dragMode: DragMode?
    @State private var didMoveDuringDrag = false

    private enum DragMode {
        case moveLayer
        case reframeBackground
        case pendingTap
    }

    private static let space = "bannerCanvas"
    private static let tapThreshold: CGFloat = 4

    private var dropEnabled: Bool {
        activeTool == .logo || activeTool == .background
    }

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.size
            let scale = min(frame.width / canvasSize.width, frame.height / canvasSize.height)
            let drawn = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
            let origin = CGPoint(
                x: (frame.width - drawn.width) / 2,
                y: (frame.height - drawn.height) / 2
            )
            let layout = BannerCanvasChromeMetrics.Layout(drawn: drawn, origin: origin, scale: scale)

            ZStack {
                chrome(for: layout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(canvasGesture(layout: layout))
            .bannerCanvasDrop(isEnabled: dropEnabled, onDrop: handleDroppedImage)
            .onDeleteCommand { deleteSelectedText() }
            .coordinateSpace(name: Self.space)
        }
    }

    @ViewBuilder
    private func chrome(for layout: BannerCanvasChromeMetrics.Layout) -> some View {
        switch selection {
        case let .text(id):
            BannerCanvasTextChrome(
                doc: doc,
                selection: $selection,
                layerID: id,
                activeTool: activeTool,
                canvasSize: canvasSize,
                drawn: layout.drawn,
                origin: layout.origin,
                scale: layout.scale,
                undoManager: undoManager,
                isEditing: $isEditingText
            )
        case .logo:
            BannerCanvasImageChrome(
                doc: doc,
                selection: $selection,
                activeTool: activeTool,
                canvasSize: canvasSize,
                layout: layout,
                undoManager: undoManager,
                filename: logoFilename,
                onReplace: { replaceLogo() }
            )
        case .backgroundFill:
            BannerCanvasBackgroundChrome(
                doc: doc,
                selection: $selection,
                activeTool: activeTool,
                canvasSize: canvasSize,
                layout: layout,
                undoManager: undoManager,
                filename: backgroundFilename,
                onReplace: { replaceBackgroundImage() }
            )
        case nil:
            EmptyView()
        }
    }

    // MARK: Gestures

    private func canvasGesture(layout: BannerCanvasChromeMetrics.Layout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let canvasPoint = screenToCanvas(value.location, layout: layout)
                if hypot(value.translation.width, value.translation.height) > Self.tapThreshold {
                    didMoveDuringDrag = true
                }
                if dragMode == nil {
                    beginDrag(at: canvasPoint, layout: layout)
                }
                applyDrag(to: canvasPoint)
            }
            .onEnded { value in
                let canvasPoint = screenToCanvas(value.location, layout: layout)
                finishDrag(at: canvasPoint)
            }
    }

    private func beginDrag(at canvasPoint: CGPoint, layout: BannerCanvasChromeMetrics.Layout) {
        _ = layout
        dragStartCanvasPoint = canvasPoint
        didMoveDuringDrag = false

        if activeTool == .background, doc.layers.fill == .image, doc.fillImageData != nil {
            selection = .backgroundFill
            dragMode = .reframeBackground
            dragStartDocument = BannerDocUndo.snapshot(of: doc)
            return
        }

        if activeTool == .text {
            dragMode = .pendingTap
            if let hit = BannerLayoutMetrics.hitTest(at: canvasPoint, doc: doc, canvas: canvasSize) {
                selection = hit
                if case .text = hit {
                    isEditingText = false
                    dragMode = .moveLayer
                    dragStartLayers = doc.layers
                } else if case .logo = hit {
                    dragMode = .moveLayer
                    dragStartLayers = doc.layers
                }
            }
            return
        }

        if activeTool == .logo {
            dragMode = .pendingTap
            if let hit = BannerLayoutMetrics.hitTest(at: canvasPoint, doc: doc, canvas: canvasSize),
               case .logo = hit {
                selection = .logo
                dragMode = .moveLayer
                dragStartLayers = doc.layers
            }
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
        case .pendingTap:
            if didMoveDuringDrag, selection != nil {
                dragMode = .moveLayer
                dragStartLayers = doc.layers
                moveSelection(to: canvasPoint)
            }
        }
    }

    private func finishDrag(at canvasPoint: CGPoint) {
        if dragMode == .moveLayer, !didMoveDuringDrag {
            if case .text = selection, activeTool == .text {
                isEditingText = true
            }
            endDrag()
            return
        }

        guard dragMode == .pendingTap, !didMoveDuringDrag else {
            endDrag()
            return
        }
        switch activeTool {
        case .text:
            let hit = BannerLayoutMetrics.hitTest(at: canvasPoint, doc: doc, canvas: canvasSize)
            if hit == nil {
                if selection != nil {
                    finalizeSelectedTextLayer()
                    selection = nil
                    isEditingText = false
                } else {
                    addText(at: canvasPoint)
                }
            } else if case let .text(id) = hit {
                selection = .text(id)
                isEditingText = true
            }
        case .logo:
            if case .logo = BannerLayoutMetrics.hitTest(at: canvasPoint, doc: doc, canvas: canvasSize) {
                break
            } else {
                addLogo(at: canvasPoint)
            }
        case .background:
            if doc.layers.fill != .image || doc.fillImageData == nil {
                addBackgroundImage()
            } else {
                selection = .backgroundFill
            }
        default:
            break
        }
        endDrag()
    }

    private func finalizeSelectedTextLayer() {
        guard case let .text(id) = selection,
              let index = doc.layers.texts.firstIndex(where: { $0.id == id }) else { return }
        let layer = doc.layers.texts[index]
        guard BannerTextPresets.isEmptyOrPlaceholder(layer.string) else { return }
        let before = doc.layers
        var layers = doc.layers
        layers.texts.remove(at: index)
        doc.layers = layers
        BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: layers, actionName: "Delete text")
    }

    private func deleteSelectedText() {
        guard case let .text(id) = selection else { return }
        let before = doc.layers
        var layers = doc.layers
        layers.texts.removeAll { $0.id == id }
        guard layers != before else { return }
        doc.layers = layers
        BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: layers, actionName: "Delete text")
        selection = nil
        isEditingText = false
    }

    // MARK: Mutations

    private func addText(at canvasPoint: CGPoint) {
        let before = doc.layers
        let nx = min(1, max(0, canvasPoint.x / canvasSize.width))
        let ny = min(1, max(0, canvasPoint.y / canvasSize.height))
        let layer = BannerTextLayer(
            string: "",
            fontSize: 50,
            colorHex: "#FFFFFF",
            alignRaw: 1,
            x: nx,
            y: ny
        )
        var layers = doc.layers
        layers.texts.append(layer)
        doc.layers = layers
        BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: layers, actionName: "Add text")
        selection = .text(layer.id)
        isEditingText = true
    }

    private func addLogo(at canvasPoint: CGPoint, picked prePicked: PickedImage? = nil) {
        guard let picked = prePicked ?? BannerNativePanels.pickImage(maxSide: 1024) else { return }
        let before = BannerDocUndo.snapshot(of: doc)
        let nx = min(1, max(0, canvasPoint.x / canvasSize.width))
        let ny = min(1, max(0, canvasPoint.y / canvasSize.height))
        doc.logoImageData = picked.data
        logoFilename = picked.filename
        var layers = doc.layers
        layers.logo = BannerLogoLayer(x: nx, y: ny, scale: 0.25)
        doc.layers = layers
        let after = BannerDocUndo.snapshot(of: doc)
        BannerDocUndo.registerDocument(undoManager, doc: doc, from: before, to: after, actionName: "Add logo")
        selection = .logo
    }

    private func replaceLogo() {
        guard let picked = BannerNativePanels.pickImage(maxSide: 1024) else { return }
        let before = BannerDocUndo.snapshot(of: doc)
        doc.logoImageData = picked.data
        logoFilename = picked.filename
        if doc.layers.logo == nil {
            var layers = doc.layers
            layers.logo = BannerLogoLayer()
            doc.layers = layers
        }
        let after = BannerDocUndo.snapshot(of: doc)
        BannerDocUndo.registerDocument(undoManager, doc: doc, from: before, to: after, actionName: "Replace logo")
        selection = .logo
    }

    private func handleDroppedImage(_ picked: PickedImage) {
        switch activeTool {
        case .logo:
            addLogo(
                at: CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5),
                picked: picked
            )
        case .background:
            applyBackgroundImage(picked, actionName: "Add background")
        default:
            break
        }
    }

    private func addBackgroundImage() {
        guard let picked = BannerNativePanels.pickImage(maxSide: 2048) else { return }
        applyBackgroundImage(picked, actionName: "Add background")
    }

    private func replaceBackgroundImage() {
        guard let picked = BannerNativePanels.pickImage(maxSide: 2048) else { return }
        applyBackgroundImage(picked, actionName: "Replace background")
    }

    private func applyBackgroundImage(_ picked: PickedImage, actionName: String) {
        let before = BannerDocUndo.snapshot(of: doc)
        doc.fillImageData = picked.data
        doc.fillImageFocalX = 0.5
        doc.fillImageFocalY = 0.5
        backgroundFilename = picked.filename
        var layers = doc.layers
        layers.fill = .image
        doc.layers = layers
        let after = BannerDocUndo.snapshot(of: doc)
        BannerDocUndo.registerDocument(undoManager, doc: doc, from: before, to: after, actionName: actionName)
        selection = .backgroundFill
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
        case .backgroundFill, nil:
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
        didMoveDuringDrag = false
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

    private func screenToCanvas(_ point: CGPoint, layout: BannerCanvasChromeMetrics.Layout) -> CGPoint {
        CGPoint(
            x: (point.x - layout.origin.x) / layout.scale,
            y: (point.y - layout.origin.y) / layout.scale
        )
    }
}
