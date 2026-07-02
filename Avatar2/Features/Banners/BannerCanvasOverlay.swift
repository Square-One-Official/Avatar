// E37.8 + E37.11 + E37.13–37.16 — Canvas-overlay: Freeform tekst, logo en
// achtergrond-image + multi-selectie (cmd/shift-klik, marquee, groep-verplaatsen).

import AppKit
import AvatarUI
import SwiftUI

struct BannerCanvasOverlay: View {
    @Bindable var doc: BannerDoc
    @Binding var selection: Set<BannerElementRef>
    @Binding var backgroundSelected: Bool
    @Binding var isEditingText: Bool
    @Binding var textToolbarVisible: Bool
    @Binding var isManipulatingText: Bool
    @Binding var logoFilename: String
    @Binding var backgroundFilename: String
    let activeTool: BannerTool?
    let canvasSize: CGSize
    @Binding var camera: CanvasCamera
    let undoManager: UndoManager?
    /// true wanneer een open bottom-paneel (Background/Effects/Size) op canvas-tik
    /// dicht i.p.v. een tool-actie (bv. Finder) te starten.
    var dismissesBottomPanelOnTap: Bool = false
    var onDismissBottomPanel: (() -> Void)?

    @State private var dragStartLayers: BannerLayers?
    @State private var dragStartDocument: BannerDocUndo.DocumentSnapshot?
    @State private var dragStartCanvasPoint: CGPoint?
    @State private var dragMode: DragMode?
    @State private var didMoveDuringDrag = false
    @State private var pressWasSelected = false
    @State private var pressedRef: BannerElementRef?
    @State private var dragGrabOffset: CGPoint = .zero
    @State private var groupStartCenter: CGPoint?
    @State private var activeSnap = SnapGuides()
    @State private var marquee: CGRect?
    @State private var marqueeBase: Set<BannerElementRef> = []

    private enum DragMode {
        case moveLayer
        case groupMove
        case reframeBackground
        case marquee
        case pendingTap
        /// Selectie is al in `beginDrag` afgehandeld (cmd/shift-toggle); niets meer doen.
        case noop
    }

    /// Genormaliseerde posities (0…1) waar tijdens het slepen een snap-guide
    /// getekend moet worden. `nil` betekent geen snap op die as.
    private struct SnapGuides: Equatable {
        var xNorm: Double?
        var yNorm: Double?
    }

    static let space = "bannerCanvas"
    private static let tapThreshold: CGFloat = 4
    /// Magnetische snap-afstand in scherm-punten (onafhankelijk van zoom).
    private static let snapScreenPt: CGFloat = 7

    private var dropEnabled: Bool {
        activeTool == .logo || activeTool == .background
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = BannerCanvasChromeMetrics.fitLayout(
                canvasSize: canvasSize,
                viewport: proxy.size,
                camera: camera
            )

            ZStack {
                chrome(for: layout)
                snapGuides(for: layout)
                marqueeRect(for: layout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(canvasGesture(layout: layout))
            .bannerCanvasDrop(isEnabled: dropEnabled, onDrop: handleDroppedImage)
            .coordinateSpace(name: Self.space)
        }
    }

    @ViewBuilder
    private func chrome(for layout: BannerCanvasChromeMetrics.Layout) -> some View {
        if backgroundSelected {
            BannerCanvasBackgroundChrome(
                doc: doc,
                backgroundSelected: $backgroundSelected,
                activeTool: activeTool,
                canvasSize: canvasSize,
                layout: layout,
                undoManager: undoManager,
                filename: backgroundFilename,
                onReplace: { replaceBackgroundImage() }
            )
        } else if selection.count >= 2 {
            BannerCanvasMultiSelectChrome(
                doc: doc,
                selection: $selection,
                canvasSize: canvasSize,
                layout: layout,
                undoManager: undoManager
            )
        } else if let single = selection.singleElement {
            switch single {
            case let .text(id):
                BannerCanvasTextChrome(
                    doc: doc,
                    selection: $selection,
                    layerID: id,
                    canvasSize: canvasSize,
                    layout: layout,
                    undoManager: undoManager,
                    isEditing: $isEditingText,
                    toolbarVisible: $textToolbarVisible,
                    isManipulating: $isManipulatingText
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
            }
        }
    }

    // MARK: Snap guides + marquee

    @ViewBuilder
    private func snapGuides(for layout: BannerCanvasChromeMetrics.Layout) -> some View {
        if dragMode == .moveLayer || dragMode == .groupMove {
            let snapColor = Color(red: 1.0, green: 0.27, blue: 0.52)
            ZStack {
                if let xn = activeSnap.xNorm {
                    let local = CGPoint(
                        x: layout.origin.x + CGFloat(xn) * layout.drawn.width,
                        y: layout.origin.y + layout.drawn.height / 2
                    )
                    Rectangle()
                        .fill(snapColor)
                        .frame(width: 1, height: layout.drawn.height * layout.camera.scale)
                        .position(layout.mapLocalToScreen(local))
                }
                if let yn = activeSnap.yNorm {
                    let local = CGPoint(
                        x: layout.origin.x + layout.drawn.width / 2,
                        y: layout.origin.y + CGFloat(yn) * layout.drawn.height
                    )
                    Rectangle()
                        .fill(snapColor)
                        .frame(width: layout.drawn.width * layout.camera.scale, height: 1)
                        .position(layout.mapLocalToScreen(local))
                }
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func marqueeRect(for layout: BannerCanvasChromeMetrics.Layout) -> some View {
        if let marquee {
            let rect = BannerCanvasChromeMetrics.screenRect(canvasRect: marquee, layout: layout)
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }

    // MARK: Gestures

    private func canvasGesture(layout: BannerCanvasChromeMetrics.Layout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let canvasPoint = layout.screenToCanvas(value.location)
                if hypot(value.translation.width, value.translation.height) > Self.tapThreshold {
                    didMoveDuringDrag = true
                }
                if dragMode == nil {
                    beginDrag(at: canvasPoint, layout: layout)
                }
                applyDrag(to: canvasPoint, layout: layout)
            }
            .onEnded { value in
                let canvasPoint = layout.screenToCanvas(value.location)
                finishDrag(at: canvasPoint)
            }
    }

    private func beginDrag(at canvasPoint: CGPoint, layout: BannerCanvasChromeMetrics.Layout) {
        _ = layout
        dragStartCanvasPoint = canvasPoint
        didMoveDuringDrag = false
        pressWasSelected = false
        pressedRef = nil

        // Achtergrond-reframe alleen in de Background-tool met een image-fill.
        if activeTool == .background, doc.layers.fill == .image, doc.fillImageData != nil {
            backgroundSelected = true
            selection = []
            dragMode = .reframeBackground
            dragStartDocument = BannerDocUndo.snapshot(of: doc)
            return
        }

        // Cmd = additief (toggle/marquee-uitbreiden). Shift is gereserveerd voor
        // de as-vergrendeling tijdens het slepen, dus niet voor additieve selectie.
        let additive = NSEvent.modifierFlags.contains(.command)
        let hit = BannerLayoutMetrics.hitTest(at: canvasPoint, doc: doc, canvas: canvasSize)

        if let ref = hit {
            pressedRef = ref
            // Klik in de tekst die al wordt bewerkt → laat de NSTextView het doen.
            if case let .text(id) = ref, isEditingText, selection == [.text(id)] {
                dragMode = nil
                return
            }
            if additive {
                // cmd/shift+klik toggelt lidmaatschap; geen move.
                backgroundSelected = false
                if selection.contains(ref) {
                    selection.remove(ref)
                } else {
                    selection.insert(ref)
                }
                isEditingText = false
                dragMode = .noop
                return
            }
            backgroundSelected = false
            // Klik op een lid van een bestaande multi-selectie → groep-move (selectie behouden).
            if selection.contains(ref), selection.count > 1 {
                pressWasSelected = true
                dragMode = .groupMove
                dragStartLayers = doc.layers
                groupStartCenter = BannerGroupTransform.combinedRect(selection, doc: doc, canvas: canvasSize)
                    .map { CGPoint(x: $0.midX, y: $0.midY) }
                return
            }
            pressWasSelected = (selection == [ref])
            if !pressWasSelected {
                finalizeEmptyTexts(keeping: ref)
                selection = [ref]
                isEditingText = false
                if case .text = ref { textToolbarVisible = true }
            }
            dragMode = .moveLayer
            dragStartLayers = doc.layers
            switch ref {
            case let .text(id):
                if let layer = doc.layers.texts.first(where: { $0.id == id }) {
                    dragGrabOffset = grabOffset(centerX: layer.x, centerY: layer.y, press: canvasPoint)
                }
            case .logo:
                if let logo = doc.layers.logo {
                    dragGrabOffset = grabOffset(centerX: logo.x, centerY: logo.y, press: canvasPoint)
                }
            }
            return
        }

        // Lege plek.
        backgroundSelected = false
        // Tools die op een tik een element toevoegen behouden hun gedrag.
        if activeTool == .logo || activeTool == .background {
            dragMode = .pendingTap
            return
        }
        // Anders: marquee (additief met cmd/shift).
        marqueeBase = additive ? selection : []
        dragMode = .marquee
        updateMarquee(to: canvasPoint)
    }

    /// Offset tussen het laag-midden en het aanraakpunt (in canvas-pixels).
    private func grabOffset(centerX: Double, centerY: Double, press: CGPoint) -> CGPoint {
        CGPoint(
            x: centerX * Double(canvasSize.width) - press.x,
            y: centerY * Double(canvasSize.height) - press.y
        )
    }

    private func applyDrag(to canvasPoint: CGPoint, layout: BannerCanvasChromeMetrics.Layout) {
        guard let mode = dragMode else { return }
        switch mode {
        case .moveLayer:
            moveSelection(to: canvasPoint, layout: layout)
        case .groupMove:
            moveGroup(to: canvasPoint, layout: layout)
        case .reframeBackground:
            reframeBackground(dragDelta: canvasPoint)
        case .marquee:
            updateMarquee(to: canvasPoint)
        case .pendingTap, .noop:
            break
        }
    }

    private func finishDrag(at canvasPoint: CGPoint) {
        let clickCount = NSApp.currentEvent?.clickCount ?? 1

        switch dragMode {
        case .moveLayer:
            if !didMoveDuringDrag, let ref = selection.singleElement, case .text = ref {
                if clickCount >= 2 {
                    isEditingText = true
                    textToolbarVisible = true
                } else if pressWasSelected {
                    textToolbarVisible.toggle()
                }
            }
            endDrag()
            return
        case .groupMove:
            // Tik (geen beweging) op een lid → terug naar single.
            if !didMoveDuringDrag, let ref = pressedRef {
                selection = [ref]
                if case .text = ref { textToolbarVisible = true }
            }
            endDrag()
            return
        case .marquee:
            cleanupUnselectedEmptyTexts()
            endDrag()
            return
        case .noop:
            endDrag()
            return
        case .reframeBackground:
            endDrag()
            return
        case .pendingTap, .none:
            break
        }

        guard dragMode == .pendingTap, !didMoveDuringDrag else {
            endDrag()
            return
        }
        switch activeTool {
        case .logo:
            addLogo(at: canvasPoint)
        case .background:
            if dismissesBottomPanelOnTap {
                onDismissBottomPanel?()
            } else if doc.layers.fill != .image || doc.fillImageData == nil {
                addBackgroundImage()
            } else {
                backgroundSelected = true
                selection = []
            }
        default:
            // Lege canvas-tik → deselecteren; lege/placeholder tekst opruimen.
            finalizeEmptyTexts(keeping: nil)
            selection = []
            backgroundSelected = false
            isEditingText = false
            textToolbarVisible = false
        }
        endDrag()
    }

    /// Verwijdert lege/placeholder tekstlagen die momenteel geselecteerd zijn (bij
    /// het wisselen van selectie), behalve `keeping`.
    private func finalizeEmptyTexts(keeping: BannerElementRef?) {
        let keepID = keeping?.textID
        let toRemove = selection.textIDs.filter { id in
            id != keepID
                && (doc.layers.texts.first(where: { $0.id == id }).map { BannerTextPresets.isEmptyOrPlaceholder($0.string) } ?? false)
        }
        guard !toRemove.isEmpty else { return }
        let before = doc.layers
        var layers = doc.layers
        layers.texts.removeAll { toRemove.contains($0.id) }
        doc.layers = layers
        BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: layers, actionName: "Delete text")
    }

    /// Na een marquee: ruim placeholder-tekstlagen op die NIET geselecteerd zijn
    /// (bv. een net toegevoegde lege tekst waar de gebruiker omheen sleepte).
    private func cleanupUnselectedEmptyTexts() {
        let toRemove = doc.layers.texts
            .filter { !selection.contains(.text($0.id)) && BannerTextPresets.isEmptyOrPlaceholder($0.string) }
            .map(\.id)
        guard !toRemove.isEmpty else { return }
        let before = doc.layers
        var layers = doc.layers
        layers.texts.removeAll { toRemove.contains($0.id) }
        doc.layers = layers
        BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: layers, actionName: "Delete text")
    }

    // MARK: Mutations

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
        selection = [.logo]
        backgroundSelected = false
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
        selection = [.logo]
        backgroundSelected = false
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
        let stored = BackgroundImageKit.shared.add(picked.data) ?? picked.data
        let before = BannerDocUndo.snapshot(of: doc)
        doc.applyFillImage(stored)
        backgroundFilename = picked.filename
        let after = BannerDocUndo.snapshot(of: doc)
        BannerDocUndo.registerDocument(undoManager, doc: doc, from: before, to: after, actionName: actionName)
        backgroundSelected = true
        selection = []
    }

    private func moveSelection(to canvasPoint: CGPoint, layout: BannerCanvasChromeMetrics.Layout) {
        // Grab-offset: verschuif t.o.v. wáár je de laag vastpakte i.p.v. het midden
        // onder de cursor te plakken (anders springt de tekst bij het oppakken).
        let grabbed = CGPoint(x: canvasPoint.x + dragGrabOffset.x, y: canvasPoint.y + dragGrabOffset.y)
        var nx = Double(min(1, max(0, grabbed.x / canvasSize.width)))
        var ny = Double(min(1, max(0, grabbed.y / canvasSize.height)))

        var layers = doc.layers
        let (xTargets, yTargets) = snapTargets(in: layers)
        let thrX = Double(Self.snapScreenPt) / Double(layout.canvasScale) / Double(canvasSize.width)
        let thrY = Double(Self.snapScreenPt) / Double(layout.canvasScale) / Double(canvasSize.height)

        var guides = SnapGuides()
        if let target = nearestSnap(nx, targets: xTargets, threshold: thrX) {
            nx = target
            guides.xNorm = target
        }
        if let target = nearestSnap(ny, targets: yTargets, threshold: thrY) {
            ny = target
            guides.yNorm = target
        }

        // Shift vergrendelt de beweging op de dominante as.
        if NSEvent.modifierFlags.contains(.shift),
           let start = dragStartCanvasPoint,
           let startPos = startNormalizedPosition() {
            if abs(canvasPoint.x - start.x) >= abs(canvasPoint.y - start.y) {
                ny = startPos.y
                guides.yNorm = nil
            } else {
                nx = startPos.x
                guides.xNorm = nil
            }
        }

        if activeSnap != guides { activeSnap = guides }

        switch selection.singleElement {
        case let .some(.text(id)):
            guard let i = layers.texts.firstIndex(where: { $0.id == id }) else { return }
            layers.texts[i].x = nx
            layers.texts[i].y = ny
        case .some(.logo):
            guard layers.logo != nil else { return }
            layers.logo?.x = nx
            layers.logo?.y = ny
        case .none:
            return
        }
        doc.layers = layers
    }

    /// Verplaatst alle geselecteerde elementen met dezelfde delta vanaf hun
    /// startposities; het groep-midden snapt naar het canvasmidden.
    private func moveGroup(to canvasPoint: CGPoint, layout: BannerCanvasChromeMetrics.Layout) {
        guard let startLayers = dragStartLayers, let start = dragStartCanvasPoint else { return }
        var dx = Double(canvasPoint.x - start.x)
        var dy = Double(canvasPoint.y - start.y)

        // Shift vergrendelt op de dominante as.
        if NSEvent.modifierFlags.contains(.shift) {
            if abs(dx) >= abs(dy) { dy = 0 } else { dx = 0 }
        }

        // Snap het groep-midden naar het canvasmidden.
        var guides = SnapGuides()
        let thrX = Double(Self.snapScreenPt) / Double(layout.canvasScale)
        let thrY = Double(Self.snapScreenPt) / Double(layout.canvasScale)
        if let center = groupStartCenter {
            let cx = Double(center.x) + dx
            let cy = Double(center.y) + dy
            let targetX = Double(canvasSize.width) / 2
            let targetY = Double(canvasSize.height) / 2
            if abs(cx - targetX) <= thrX {
                dx += targetX - cx
                guides.xNorm = 0.5
            }
            if abs(cy - targetY) <= thrY {
                dy += targetY - cy
                guides.yNorm = 0.5
            }
        }
        if activeSnap != guides { activeSnap = guides }

        let dxFrac = dx / Double(canvasSize.width)
        let dyFrac = dy / Double(canvasSize.height)

        var layers = startLayers
        for ref in selection {
            switch ref {
            case let .text(id):
                guard let i = layers.texts.firstIndex(where: { $0.id == id }) else { continue }
                layers.texts[i].x = min(1, max(0, layers.texts[i].x + dxFrac))
                layers.texts[i].y = min(1, max(0, layers.texts[i].y + dyFrac))
            case .logo:
                guard var logo = layers.logo else { continue }
                logo.x = min(1, max(0, logo.x + dxFrac))
                logo.y = min(1, max(0, logo.y + dyFrac))
                layers.logo = logo
            }
        }
        doc.layers = layers
    }

    /// Genormaliseerde startpositie van de gesleepte laag (uit `dragStartLayers`),
    /// nodig om de vergrendelde as op zijn beginwaarde te houden bij Shift.
    private func startNormalizedPosition() -> (x: Double, y: Double)? {
        guard let layers = dragStartLayers else { return nil }
        switch selection.singleElement {
        case let .some(.text(id)):
            guard let text = layers.texts.first(where: { $0.id == id }) else { return nil }
            return (text.x, text.y)
        case .some(.logo):
            guard let logo = layers.logo else { return nil }
            return (logo.x, logo.y)
        case .none:
            return nil
        }
    }

    /// Snap-doelen per as: altijd het canvasmidden (0.5) plus de centers van
    /// de overige lagen, zodat tekst uitlijnt zoals in Snapchat.
    private func snapTargets(in layers: BannerLayers) -> (x: [Double], y: [Double]) {
        var xs: [Double] = [0.5]
        var ys: [Double] = [0.5]
        let selectedTextID = selection.singleElement?.textID
        for text in layers.texts where text.id != selectedTextID {
            xs.append(text.x)
            ys.append(text.y)
        }
        if selection.singleElement != .logo, let logo = layers.logo {
            xs.append(logo.x)
            ys.append(logo.y)
        }
        return (xs, ys)
    }

    /// Zoekt het dichtstbijzijnde snap-doel binnen de drempel.
    private func nearestSnap(_ value: Double, targets: [Double], threshold: Double) -> Double? {
        var best: Double?
        var bestDistance = threshold
        for target in targets {
            let distance = abs(value - target)
            if distance <= bestDistance {
                bestDistance = distance
                best = target
            }
        }
        return best
    }

    private func updateMarquee(to canvasPoint: CGPoint) {
        guard let start = dragStartCanvasPoint else { return }
        let rect = CGRect(
            x: min(start.x, canvasPoint.x),
            y: min(start.y, canvasPoint.y),
            width: abs(canvasPoint.x - start.x),
            height: abs(canvasPoint.y - start.y)
        )
        marquee = rect
        let hits = marqueeHits(rect)
        let newSelection = marqueeBase.union(hits)
        if selection != newSelection { selection = newSelection }
    }

    /// Elementen waarvan de canvas-rect het marquee-kader snijdt.
    private func marqueeHits(_ rect: CGRect) -> Set<BannerElementRef> {
        var hits: Set<BannerElementRef> = []
        for text in doc.layers.texts {
            if BannerLayoutMetrics.textRect(layer: text, canvas: canvasSize).intersects(rect) {
                hits.insert(.text(text.id))
            }
        }
        if let logo = doc.layers.logo,
           let data = doc.logoImageData,
           let cg = BannerDocRenderer.cgImage(from: data),
           BannerLayoutMetrics.logoRect(layer: logo, logoImage: cg, canvas: canvasSize).intersects(rect) {
            hits.insert(.logo)
        }
        return hits
    }

    private func reframeBackground(dragDelta canvasPoint: CGPoint) {
        guard let start = dragStartDocument, let origin = dragStartCanvasPoint else { return }
        let dx = (canvasPoint.x - origin.x) / canvasSize.width
        let dy = (canvasPoint.y - origin.y) / canvasSize.height
        doc.fillImageFocalX = min(1, max(0, start.fillImageFocalX - dx * 0.6))
        doc.fillImageFocalY = min(1, max(0, start.fillImageFocalY - dy * 0.6))
        doc.touch()
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
        pressWasSelected = false
        pressedRef = nil
        dragGrabOffset = .zero
        groupStartCenter = nil
        activeSnap = SnapGuides()
        marquee = nil
        marqueeBase = []
        if mode == .moveLayer || mode == .groupMove, let before = beforeLayers, before != doc.layers {
            BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: doc.layers, actionName: "Move")
        }
        if mode == .reframeBackground, let before = beforeDocument {
            let after = BannerDocUndo.snapshot(of: doc)
            if before != after {
                BannerDocUndo.registerDocument(undoManager, doc: doc, from: before, to: after, actionName: "Background")
            }
        }
    }

}
