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

    /// Plaatshouder-tekst tot het echte paneel landt (welke story het invult).
    var placeholder: String {
        switch self {
        case .background: return "Solid color, mesh gradient, upload or generate an image. (E37.3)"
        case .shaders:    return "Procedural effects — noise, dither, mesh gradient, lens distortion, warp. (E37.7 · E38)"
        case .text:       return "Add and style text — font, size, weight, color, alignment. (E37.4)"
        case .logo:       return "Place a logo and manage your brand colors. (E37.5)"
        case .size:       return "Platform sizes — LinkedIn, X, wide. (E37.6)"
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

    init(doc: BannerDoc, onClose: @escaping () -> Void) {
        self.doc = doc
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
        DSEditPanel(title: tool.label) {
            VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                Text(tool.placeholder)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        if let cg = BannerDocRenderer.render(doc),
           let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            doc.previewImageData = png
        }
        doc.touch()
        onClose()
    }

    private func refreshPreview() async {
        // Klein canvas (≤1500×500) — render op de main-actor is goedkoop genoeg;
        // de echte live-shaderrender komt off-main in E38.2.
        guard let cg = BannerDocRenderer.render(doc) else { return }
        preview = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
