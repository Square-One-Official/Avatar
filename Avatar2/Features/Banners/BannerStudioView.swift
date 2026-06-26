// Banner Studio (E37.2). De editor-romp: een venster-niveau-overlay (zoals de
// social-preview) die op één `BannerDoc` werkt. Een wijde canvas-kaart toont de
// live render; een onderste capsule-toolbar (Background · Shaders · Text · Logo ·
// Size) opent per tool een paneel — in de geest van de portret-editor
// (`DSEditPanelContainer`), maar simpeler. De panelen zelf zijn in 37.2 nog
// plaatshouders; 37.3–37.7 vullen ze.
//
// NB: `DSCanvasCard` is 1:1-vergrendeld (vierkant export-canvas); een banner is
// WIJD, dus de canvas-kaart is hier een DS-token-kaart (Background.card, xl4) op
// de doc-aspect i.p.v. `DSCanvasCard` — bewuste DS-afwijking, in de geest van het
// systeem.

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
        case .shaders:    return "Shaders"
        case .text:       return "Text"
        case .logo:       return "Logo"
        case .size:       return "Size"
        }
    }

    var icon: Image {
        switch self {
        case .background: return Image(systemName: "photo.fill")
        case .shaders:    return Image(systemName: "sparkles")
        case .text:       return Image(systemName: "textformat")
        case .logo:       return Image(systemName: "rosette")
        case .size:       return Image(systemName: "aspectratio")
        }
    }

    /// Korte omschrijving van de tool (gebruikersgericht).
    var summary: String {
        switch self {
        case .background: return "Solid color, mesh gradient, upload or generate an image."
        case .shaders:    return "Procedural effects — noise, dither, mesh gradients, lens distortion and warp — applied live on your banner."
        case .text:       return "Add and style text — font, size, weight, color, alignment."
        case .logo:       return "Place a logo and manage your brand colors."
        case .size:       return "Platform sizes — LinkedIn, X, wide."
        }
    }
}

struct BannerStudioView: View {
    let doc: BannerDoc
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeTool: BannerTool?
    @State private var name: String
    @State private var preview: NSImage?

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
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: DSSpacing.gap3) {
            DSToolButton(Image(systemName: "xmark"), label: "Close", surface: .ghost) { onClose() }

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
            DSPrimaryButton("Save") { save() }
        }
        .padding(.horizontal, DSSpacing.gap6)
        .padding(.vertical, DSSpacing.gap4)
    }

    // MARK: Canvas (wijde DS-kaart — zie kop-noot over DSCanvasCard)

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

    // MARK: Panels (plaatshouders — 37.3–37.7 vullen ze)

    @ViewBuilder private func panel(_ tool: BannerTool) -> some View {
        switch tool {
        case .background:
            BannerBackgroundPanel(doc: doc)
        case .text:
            BannerTextPanel(doc: doc)
        case .logo:
            BannerLogoPanel(doc: doc)
        case .size:
            BannerSizePanel(doc: doc)
        case .shaders:
            BannerShaderPanel(doc: doc)
        }
    }

    // MARK: Acties

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { name = doc.name; return }
        doc.name = trimmed
        doc.touch()
    }

    /// Rendert de doc → preview-cache + sluit. (Banner2-mirror voor gallery/
    /// social-preview-compat: zie 37.6 — gallery toont nu BannerDoc.)
    private func save() {
        commitName()
        if let cg = composedImage(watermark: false),
           let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            doc.previewImageData = png
        }
        doc.touch()
        onClose()
    }

    /// Rendert de doc op canvas-maat → PNG → NSSavePanel; free-tier watermerk.
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
        // Klein canvas (≤1500×500) — render op de main-actor is goedkoop genoeg.
        guard let cg = composedImage(watermark: false) else { return }
        preview = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Het volledige banner-beeld: CPU-compositie (fill+tekst+logo) via
    /// `BannerDocRenderer`, dan de GPU-shader-stack erin gerasterd (E38.2), en
    /// optioneel het free-tier watermerk scherp bovenop. Eén pad voor
    /// preview/save/export → wat-je-ziet = wat-je-bewaart/exporteert.
    private func composedImage(watermark: Bool) -> CGImage? {
        guard let base = BannerDocRenderer.render(doc) else { return nil }
        let shaded = BannerShaderRenderer.bake(base, shaders: doc.layers.shaders, size: doc.canvasSize) ?? base
        guard watermark else { return shaded }
        return BannerDocRenderer.stampWatermark(on: shaded) ?? shaded
    }
}
