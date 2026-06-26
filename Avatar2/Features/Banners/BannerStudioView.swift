// Banner Studio (E37.2). De editor-romp: een venster-niveau-overlay (zoals de
// social-preview) die op één `BannerDoc` werkt. Een wijde canvas-kaart toont de
// live render; een onderste capsule-toolbar (Background · Effects · Text · Logo ·
// Size) opent per tool een paneel — in de geest van de portret-editor
// (`DSEditPanelContainer`), maar simpeler.

import AppKit
import AvatarUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
    let onClose: () -> Void

    @Environment(\.undoManager) private var undoManager

    @State private var activeTool: BannerTool?
    @State private var name: String
    @State private var preview: NSImage?
    @State private var canvasSelection: BannerCanvasSelection?
    @State private var isEditingText = false
    @State private var logoFilename = "logo.png"
    @State private var backgroundFilename = "background.png"
    @State private var shownHints: Set<BannerTool> = []
    @State private var thumbnailBakeTask: Task<Void, Never>?

    let isPro: Bool

    init(doc: BannerDoc, isPro: Bool, onClose: @escaping () -> Void) {
        self.doc = doc
        self.isPro = isPro
        self.onClose = onClose
        _name = State(initialValue: doc.name)
    }

    var body: some View {
        ZStack {
            DSColor.Background.app.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                DSEditPanelContainer(
                    tools: BannerTool.allCases.map { DSToolbarItem(id: $0, icon: $0.icon, label: $0.label) },
                    activeTool: $activeTool,
                    photo: { canvas },
                    panel: { tool in panel(tool) }
                )
            }
        }
        .task(id: doc.updatedAt) { await refreshPreview() }
        .onChange(of: doc.updatedAt) { _, _ in scheduleThumbnailBake() }
        .onChange(of: canvasSelection) { _, _ in Task { await refreshPreview() } }
        .onChange(of: isEditingText) { _, _ in Task { await refreshPreview() } }
        .onChange(of: activeTool) { _, tool in
            Task { await refreshPreview() }
            guard let tool else { return }
            autoSelectForTool(tool)
        }
        .onDisappear { thumbnailBakeTask?.cancel() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: DSSpacing.gap3) {
            DSToolButton(Image(systemName: "xmark"), label: "Close", surface: .ghost) { onClose() }

            undoRedoCluster

            Spacer(minLength: 0)

            TextField("Banner name", text: $name)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .dsTextStyle(.labelLarge)
                .foregroundStyle(DSColor.Foreground.primary)
                .frame(maxWidth: 280)
                .onSubmit { commitName() }

            Spacer(minLength: 0)

            DSNeutralButton("Export") { export() }
            DSPrimaryButton("Done") { done() }
        }
        .padding(.horizontal, DSSpacing.gap6)
        .padding(.vertical, DSSpacing.gap4)
    }

    private var undoRedoCluster: some View {
        HStack(spacing: DSSpacing.gap1) {
            DSToolButton(Image(systemName: "arrow.uturn.backward"), label: "Undo", surface: .ghost) {
                undoManager?.undo()
            }
            .disabled(!(undoManager?.canUndo ?? false))
            DSToolButton(Image(systemName: "arrow.uturn.forward"), label: "Redo", surface: .ghost) {
                undoManager?.redo()
            }
            .disabled(!(undoManager?.canRedo ?? false))
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        ZStack {
            DSColor.Background.app
            RoundedRectangle(cornerRadius: DSRadius.xl4, style: .continuous)
                .fill(DSColor.Background.card)
                .aspectRatio(doc.canvasSize.width / max(1, doc.canvasSize.height), contentMode: .fit)
                .overlay {
                    if let preview {
                        Image(nsImage: preview)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .overlay {
                    BannerCanvasOverlay(
                        doc: doc,
                        selection: $canvasSelection,
                        isEditingText: $isEditingText,
                        logoFilename: $logoFilename,
                        backgroundFilename: $backgroundFilename,
                        activeTool: activeTool,
                        canvasSize: doc.canvasSize,
                        undoManager: undoManager
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.xl4, style: .continuous)
                        .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
                )
                .frame(maxWidth: 1100)
                .shadow(color: .black.opacity(0.25), radius: 40, y: 24)
                .padding(.horizontal, DSSpacing.gap8)
        }
    }

    // MARK: Panels

    @ViewBuilder private func panel(_ tool: BannerTool) -> some View {
        let showHint = !shownHints.contains(tool)
        Group {
            switch tool {
            case .background:
                BannerBackgroundPanel(doc: doc, subtitle: showHint ? tool.summary : nil)
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
        case .text:
            if canvasSelection == nil, let first = doc.layers.texts.first {
                canvasSelection = .text(first.id)
            }
            isEditingText = doc.layers.texts.isEmpty
        case .logo:
            if doc.layers.logo != nil { canvasSelection = .logo }
        case .background:
            if doc.layers.fill == .image, doc.fillImageData != nil {
                canvasSelection = .backgroundFill
            }
        default:
            break
        }
    }

    // MARK: Acties

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { name = doc.name; return }
        doc.name = trimmed
        doc.touch()
    }

    /// Sluit de studio; wijzigingen zijn al opgeslagen (SwiftData). Bak thumbnail.
    private func done() {
        commitName()
        bakeThumbnail()
        onClose()
    }

    private func export() {
        commitName()
        guard let cg = composedImage(watermark: !isPro),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (doc.name.isEmpty ? "banner" : doc.name) + ".png"
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }

    private func refreshPreview() async {
        guard let cg = composedImage(watermark: false, excludingTextIDs: editingTextIDs) else { return }
        preview = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// De tekst-id die live op het canvas wordt bewerkt (en dus uit de gebakken
    /// preview moet) — precies wanneer het `NSTextField` zichtbaar is in de chrome.
    private var editingTextIDs: Set<UUID> {
        guard activeTool == .text, case let .text(id) = canvasSelection else { return [] }
        return [id]
    }

    private func scheduleThumbnailBake() {
        thumbnailBakeTask?.cancel()
        thumbnailBakeTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { bakeThumbnail() }
        }
    }

    private func bakeThumbnail() {
        if let cg = composedImage(watermark: false),
           let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            doc.previewImageData = png
        }
    }

    private func composedImage(watermark: Bool, excludingTextIDs: Set<UUID> = []) -> CGImage? {
        guard let base = BannerDocRenderer.render(doc, excludingTextIDs: excludingTextIDs) else { return nil }
        let shaded = BannerShaderRenderer.bake(base, shaders: doc.layers.shaders, size: doc.canvasSize) ?? base
        guard watermark else { return shaded }
        return BannerDocRenderer.stampWatermark(on: shaded) ?? shaded
    }
}
