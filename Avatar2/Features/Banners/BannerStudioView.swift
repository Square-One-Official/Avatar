// Banner Studio (E37.2). Full-bleed canvas (ShellView ZStack) — zelfde patroon
// als EditorView: sidebar + topbar/toolbar als overlay.

import AppKit
import AvatarUI
import SwiftData
import SwiftUI

/// De tools in de Studio-capsule. Simpeler dan de portret-editor; toegespitst op
/// wat een mooie banner nodig heeft (UX-onderzoek E37).
enum BannerTool: Hashable, CaseIterable, Identifiable {
    case background, shaders, text, logo, size
    var id: Self { self }

    var label: String {
        switch self {
        case .background: return "Background"
        case .shaders:    return "Effects"
        case .text:       return "Text"
        case .logo:       return "Logo"
        case .size:       return "Size"
        }
    }

    var icon: Image {
        switch self {
        case .background: return Image(systemName: "photo.fill")
        case .shaders:    return Image(systemName: "sparkles")
        case .text:       return Image(systemName: "character.textbox")
        case .logo:       return Image(systemName: "photo")
        case .size:       return Image(systemName: "aspectratio")
        }
    }

    var summary: String {
        switch self {
        case .background: return "Colour or gradient here — tap the canvas to add a photo background."
        case .shaders:    return "Procedural effects applied to the whole banner."
        case .text:       return "Tap the canvas to add text — drag to move, use the toolbar to style."
        case .logo:       return "Tap the canvas to place a logo — drag to move, corners to scale."
        case .size:       return "Platform sizes — LinkedIn, X, wide."
        }
    }
}

struct BannerStudioView: View {
    let doc: BannerDoc
    var entitlement: EntitlementModel?

    @Environment(\.undoManager) private var undoManager

    @State private var activeTool: BannerTool?
    @State private var preview: NSImage?
    @State private var selection: Set<BannerElementRef> = []
    @State private var backgroundSelected = false
    @State private var isEditingText = false
    @State private var textToolbarVisible = false
    @State private var isManipulatingText = false
    @State private var logoFilename = "logo.png"
    @State private var backgroundFilename = "background.png"
    @State private var shownHints: Set<BannerTool> = []
    @State private var thumbnailBakeTask: Task<Void, Never>?
    /// Doelresolutie (pixels) voor de on-screen preview = getoonde banner-maat ×
    /// schermschaal. Houdt de gebakken tekst scherp op elk venster-/displayformaat.
    @State private var canvasPixelSize: CGSize = .zero
    /// Viewport-grootte voor camera-fit bij openen en venster-resize.
    @State private var canvasViewportSize: CGSize = .zero
    /// Viewport-camera (E27): zoom/pan over de banner-kaart, sessie-only.
    @State private var camera = CanvasCamera()

    init(doc: BannerDoc, entitlement: EntitlementModel? = nil) {
        self.doc = doc
        self.entitlement = entitlement
    }

    var body: some View {
        DSEditPanelContainer(
            tools: BannerTool.allCases.map { DSToolbarItem(id: $0, icon: $0.icon, label: $0.label) },
            activeTool: toolSelection,
            photo: { canvas },
            panel: { tool in panel(tool) }
        )
        .task(id: previewRefreshKey) { await refreshPreview() }
        .onChange(of: doc.updatedAt) { _, _ in scheduleThumbnailBake() }
        .onChange(of: selection) { _, _ in Task { await refreshPreview() } }
        .onChange(of: backgroundSelected) { _, _ in Task { await refreshPreview() } }
        .onChange(of: isEditingText) { _, _ in Task { await refreshPreview() } }
        .onChange(of: isManipulatingText) { _, _ in Task { await refreshPreview() } }
        .onChange(of: canvasPixelSize) { _, _ in Task { await refreshPreview() } }
        .onChange(of: activeTool) { _, tool in
            Task { await refreshPreview() }
            guard let tool else { return }
            autoSelectForTool(tool)
        }
        .onChange(of: doc.persistentModelID) { _, _ in
            applyBannerOpenFit()
        }
        .onDisappear {
            thumbnailBakeTask?.cancel()
            Task { await bakeThumbnail() }
            camera.reset()
        }
        .background { selectionKeyboardShortcuts }
        .focusedSceneValue(\.canvasZoom, CanvasZoomActions(
            zoomIn: { zoomCamera(by: 1.25) },
            zoomOut: { zoomCamera(by: 0.8) },
            zoomToFit: { withAnimation(.spring(duration: 0.3)) { applyBannerOpenFit() } },
            actualSize: { withAnimation(.spring(duration: 0.3)) { applyBannerActualSize() } }
        ))
    }

    private func zoomCamera(by factor: CGFloat) {
        withAnimation(.spring(duration: 0.25)) { camera.zoomCentered(by: factor) }
    }

    private func applyBannerOpenFit(viewport: CGSize? = nil) {
        let vp = viewport ?? canvasViewportSize
        guard vp.width > 0, vp.height > 0 else { return }
        let layout = BannerCanvasChromeMetrics.fitLayout(
            canvasSize: doc.canvasSize,
            viewport: vp,
            horizontalPadding: 0,
            camera: camera
        )
        var c = camera
        c.fitToContent(contentSize: layout.drawn, in: vp, padding: 0.94)
        camera = c
    }

    /// ⌘1 — Actual Size (100%): 1 scherm-punt per banner-pixel. De kaart wordt op
    /// `layout.drawn` getekend en met `camera.scale` geschaald, dus scale =
    /// canvasSize/drawn brengt 'm op zijn echte exportmaat. Bij een grote banner
    /// loopt 'ie buiten het venster (pannen) — dat hóórt bij 100%.
    private func applyBannerActualSize(viewport: CGSize? = nil) {
        let vp = viewport ?? canvasViewportSize
        guard vp.width > 0, vp.height > 0 else { return }
        let layout = BannerCanvasChromeMetrics.fitLayout(
            canvasSize: doc.canvasSize,
            viewport: vp,
            horizontalPadding: 0,
            camera: camera
        )
        guard layout.drawn.width > 0 else { return }
        var c = camera
        c.scale = c.clampScale(doc.canvasSize.width / layout.drawn.width)
        c.offset = .zero
        camera = c
    }

    /// Onzichtbare toetsenbord-sneltoetsen voor de canvas-selectie. Werken alleen
    /// als geen tekstveld/NSTextView de toets opslokt (dus niet tijdens typen).
    private var selectionKeyboardShortcuts: some View {
        ZStack {
            Button("") { selectAllElements() }
                .keyboardShortcut("a", modifiers: .command)
            Button("") { deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
            Button("") { clearSelection() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .frame(width: 0, height: 0)
    }

    private func selectAllElements() {
        guard !isEditingText else { return }
        var sel = Set(doc.layers.texts.map { BannerElementRef.text($0.id) })
        if doc.layers.logo != nil { sel.insert(.logo) }
        selection = sel
        backgroundSelected = false
    }

    /// Verwijdert alle geselecteerde tekstlagen (+ logo indien geselecteerd) in één
    /// undo. Niet tijdens tekst-bewerking (de NSTextView verwerkt ⌫ dan zelf).
    private func deleteSelection() {
        guard !isEditingText, !selection.isEmpty else { return }
        let before = BannerDocUndo.snapshot(of: doc)
        var layers = doc.layers
        let ids = Set(selection.textIDs)
        layers.texts.removeAll { ids.contains($0.id) }
        if selection.contains(.logo) {
            layers.logo = nil
            doc.logoImageData = nil
        }
        doc.layers = layers
        let after = BannerDocUndo.snapshot(of: doc)
        BannerDocUndo.registerDocument(undoManager, doc: doc, from: before, to: after, actionName: "Delete")
        selection = []
        backgroundSelected = false
        isEditingText = false
        textToolbarVisible = false
    }

    private func clearSelection() {
        finalizeEmptyText()
        selection = []
        backgroundSelected = false
        isEditingText = false
        textToolbarVisible = false
    }

    /// Proxy zodat de Text-knop momentaan is (#6): selecteren ervan voegt direct
    /// een tekst toe zónder een sticky tool/paneel te activeren. Wisselen naar een
    /// paneel-tool laat de huidige tekstselectie los (#2).
    private var toolSelection: Binding<BannerTool?> {
        Binding(
            get: { activeTool },
            set: { newValue in
                if newValue == .text {
                    addTextLayer()
                    return
                }
                deselectText()
                activeTool = newValue
            }
        )
    }

    private var previewRefreshKey: String {
        let fillTag: String
        switch doc.layers.fill {
        case .image: fillTag = "image"
        case .solid: fillTag = "solid"
        case .meshGradient: fillTag = "gradient"
        }
        return "\(doc.updatedAt.timeIntervalSinceReferenceDate)-\(fillTag)-\(doc.fillImageData?.count ?? 0)-\(doc.fillImageFocalX)-\(doc.fillImageFocalY)-\(doc.fillImageZoom)"
    }

    // MARK: Canvas

    /// Bottom-panelen (Background/Effects/Size) sluiten bij canvas-tik; Logo niet
    /// (geen paneel — canvas-tik opent Finder).
    private var closesPanelOnCanvasTap: Bool {
        switch activeTool {
        case .background, .shaders, .size: true
        case .text, .logo, .none: false
        }
    }

    private var canvas: some View {
        GeometryReader { proxy in
            let viewport = proxy.size
            let layout = BannerCanvasChromeMetrics.fitLayout(
                canvasSize: doc.canvasSize,
                viewport: viewport,
                horizontalPadding: 0,
                camera: camera
            )
            let cardFrame = CGRect(origin: layout.origin, size: layout.drawn)

            ZStack {
                DSColor.Background.canvasIsolated
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isEditingText else { return }
                        // E18.17-pariteit: open bottom-paneel sluit vóór deselect —
                        // anders opent Background op canvas-tik meteen Finder.
                        if closesPanelOnCanvasTap {
                            toolSelection.wrappedValue = nil
                            return
                        }
                        clearSelection()
                    }

                bannerCardPreview(layout: layout)
                    .scaleEffect(
                        camera.scale,
                        anchor: layout.cameraScaleAnchor(cardFrame: cardFrame)
                    )
                    .offset(camera.offset)

                BannerCanvasOverlay(
                    doc: doc,
                    selection: $selection,
                    backgroundSelected: $backgroundSelected,
                    isEditingText: $isEditingText,
                    textToolbarVisible: $textToolbarVisible,
                    isManipulatingText: $isManipulatingText,
                    logoFilename: $logoFilename,
                    backgroundFilename: $backgroundFilename,
                    activeTool: activeTool,
                    canvasSize: doc.canvasSize,
                    camera: $camera,
                    undoManager: undoManager,
                    dismissesBottomPanelOnTap: closesPanelOnCanvasTap,
                    onDismissBottomPanel: { toolSelection.wrappedValue = nil }
                )
            }
            .background {
                CanvasInteractionCatcher(
                    camera: $camera,
                    // Alleen zijpaneel-scroll blokkeert canvas-zoom — niet de
                    // floating tekst-toolbar bij selectie (zoom moet blijven werken).
                    chromeHovered: activeTool != nil
                )
            }
            .clipped()
            // E18.17: open bottom-paneel sluit bij tik op canvas/foto — net als
            // EditorView en dropdown-menu's (voorkomt o.a. Finder via Background-tool).
            .overlay {
                if closesPanelOnCanvasTap {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toolSelection.wrappedValue = nil
                        }
                }
            }
            .onAppear {
                canvasViewportSize = viewport
                applyBannerOpenFit(viewport: viewport)
            }
            .onChange(of: proxy.size) { _, size in
                canvasViewportSize = size
                applyBannerOpenFit(viewport: size)
            }
        }
        .ignoresSafeArea()
    }

    /// De banner-kaart op fit-layout-posities; krijgt camera-transform in `canvas`.
    private func bannerCardPreview(layout: BannerCanvasChromeMetrics.Layout) -> some View {
        RoundedRectangle(cornerRadius: DSRadius.xl4, style: .continuous)
            .fill(DSColor.Background.card)
            .frame(width: layout.drawn.width, height: layout.drawn.height)
            .overlay {
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { updateCanvasPixelSize(proxy.size) }
                        .onChange(of: proxy.size) { _, size in updateCanvasPixelSize(size) }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xl4, style: .continuous)
                    .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
            )
            .shadow(color: .black.opacity(0.25), radius: 40, y: 24)
            .position(
                x: layout.origin.x + layout.drawn.width / 2,
                y: layout.origin.y + layout.drawn.height / 2
            )
    }

    // MARK: Panels

    @ViewBuilder private func panel(_ tool: BannerTool) -> some View {
        let showHint = !shownHints.contains(tool)
        Group {
            switch tool {
            case .background:
                BannerBackgroundPanel(
                    doc: doc,
                    entitlement: entitlement,
                    subtitle: showHint ? tool.summary : nil
                )
            case .text:
                EmptyView()
            case .logo:
                EmptyView()
            case .size:
                BannerSizePanel(doc: doc, subtitle: showHint ? tool.summary : nil)
            case .shaders:
                BannerShaderPanel(doc: doc, subtitle: showHint ? tool.summary : nil)
            }
        }
        .onAppear {
            if showHint { shownHints.insert(tool) }
        }
    }

    private func autoSelectForTool(_ tool: BannerTool) {
        switch tool {
        case .logo:
            if doc.layers.logo != nil {
                selection = [.logo]
                backgroundSelected = false
            }
        case .background:
            if doc.layers.fill == .image, doc.fillImageData != nil {
                backgroundSelected = true
                selection = []
            }
        default:
            break
        }
    }

    /// Voegt een lege tekstlaag in het canvas-midden toe (Freeform #1): geselecteerd
    /// met handvatten, maar nog NIET in edit-modus en zonder floating toolbar. De
    /// gebruiker begint te typen of dubbelklikt om te bewerken.
    private func addTextLayer() {
        finalizeEmptyText()
        let canvas = doc.canvasSize
        let stackIndex = BannerLayoutMetrics.nextTextStackIndex(in: doc.layers.texts, canvas: canvas)
        let (nx, ny) = BannerLayoutMetrics.staggeredTextPosition(stackIndex: stackIndex, canvas: canvas)
        let layer = BannerLayoutMetrics.withInitialFrame(
            BannerTextLayer(string: "", fontSize: 50, colorHex: "#FFFFFF", alignRaw: 1, x: nx, y: ny),
            canvas: canvas
        )
        let before = doc.layers
        var layers = doc.layers
        layers.texts.append(layer)
        doc.layers = layers
        BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: layers, actionName: "Add text")
        selection = [.text(layer.id)]
        backgroundSelected = false
        isEditingText = false
        textToolbarVisible = false
    }

    /// Laat een tekstselectie los (bij wisselen naar een paneel-tool of klik buiten):
    /// ruimt een lege/placeholder laag op en reset de tekst-UI-state.
    private func deselectText() {
        finalizeEmptyText()
        selection = selection.filter { $0.textID == nil }
        isEditingText = false
        textToolbarVisible = false
    }

    /// Ruimt nog-lege/placeholder tekstlagen op (alle geselecteerde) wanneer de
    /// Text-tool verlaten wordt zonder dat er iets is getypt.
    private func finalizeEmptyText() {
        let emptyIDs = selection.textIDs.filter { id in
            doc.layers.texts.first(where: { $0.id == id }).map {
                BannerTextPresets.isEmptyOrPlaceholder($0.string)
            } ?? false
        }
        guard !emptyIDs.isEmpty else { return }
        let before = doc.layers
        var layers = doc.layers
        layers.texts.removeAll { emptyIDs.contains($0.id) }
        doc.layers = layers
        BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: layers, actionName: "Delete text")
        selection = selection.filter { ref in
            guard let id = ref.textID else { return true }
            return !emptyIDs.contains(id)
        }
        isEditingText = false
    }

    // MARK: Acties

    private func refreshPreview() async {
        guard let cg = await BannerDocRenderer.composedImageAsync(
            doc,
            size: previewRenderSize,
            excludingTextIDs: editingTextIDs
        ) else { return }
        preview = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Doelmaat voor de on-screen render: getoonde pixels (× backingScale), met
    /// behoud van de canvas-aspect. Valt terug op de canvas-maat vóór de meting.
    private var previewRenderSize: CGSize? {
        guard canvasPixelSize.width > 1 else { return nil }
        let aspect = doc.canvasSize.height / max(1, doc.canvasSize.width)
        return CGSize(width: canvasPixelSize.width, height: (canvasPixelSize.width * aspect).rounded())
    }

    /// Zet de doelresolutie op basis van de gemeten banner-grootte × schermschaal.
    /// Negeert micro-wijzigingen om onnodige re-renders te vermijden.
    private func updateCanvasPixelSize(_ pointSize: CGSize) {
        guard pointSize.width > 1 else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let px = (pointSize.width * scale).rounded()
        if abs(px - canvasPixelSize.width) > 2 {
            canvasPixelSize = CGSize(width: px, height: (px * doc.canvasSize.height / max(1, doc.canvasSize.width)).rounded())
        }
    }

    /// De tekst-id die live op het canvas wordt bewerkt (en dus uit de gebakken
    /// preview moet) — precies wanneer het `NSTextField` zichtbaar is in de chrome.
    private var editingTextIDs: Set<UUID> {
        guard isEditingText || isManipulatingText,
              let id = selection.singleElement?.textID else { return [] }
        return [id]
    }

    private func scheduleThumbnailBake() {
        thumbnailBakeTask?.cancel()
        thumbnailBakeTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await bakeThumbnail()
        }
    }

    /// Bakt de gecachte preview-PNG. Render + PNG-encode draaien off-main
    /// (`composedImageAsync` + detached encode); alleen het schrijven naar het
    /// `@Model` gebeurt op de main-actor.
    private func bakeThumbnail() async {
        guard let cg = await BannerDocRenderer.composedImageAsync(doc) else { return }
        if Task.isCancelled { return }
        let box = SendableCGImage(cgImage: cg)
        let pngTask = Task.detached(priority: .utility) {
            NSBitmapImageRep(cgImage: box.cgImage).representation(using: .png, properties: [:])
        }
        guard let png = await pngTask.value, !Task.isCancelled else { return }
        // Na de awaits kan het document gesloten/verwijderd zijn (de onDisappear-
        // bake draait async ná teardown): niet naar een losgekoppeld @Model
        // schrijven. En een gesuperseerde (gecancelde) bake mag een verse preview
        // niet overschrijven (de debounce cancelt de vorige `thumbnailBakeTask`).
        guard doc.modelContext != nil else { return }
        doc.previewImageData = png
    }
}
