// Main shell-wortel (E05). 5.1 = first-use-empty-state, 5.2 = import
// (drag-drop over het hele venster + bestandskiezer → PipelineRouter,
// review-fix: geen omlijnd dropvierkant maar een vensterrand-glow).
// Isolating-animatie (5.3), sidebar (5.4) en header (5.5) haken hier in.

import AvatarUI
import SwiftUI
import UniformTypeIdentifiers

struct ShellView: View {
    let entitlement: EntitlementModel
    @State private var model: ShellModel

    init(entitlement: EntitlementModel) {
        self.entitlement = entitlement
        _model = State(initialValue: ShellModel(entitlement: entitlement))
    }

    var body: some View {
        canvas
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DSColor.Background.app)
            .preferredColorScheme(.dark)
            // Heel het venster is droptarget (Fitts); de Figma-dropzone
            // (App / Dropzone, 4017:1622) verschijnt zolang er iets boven
            // hangt: 465×456, r-4xl, dashed lime b-medium, "Drop it" H3.
            .onDrop(of: [.fileURL, .image], isTargeted: $model.isDropTargeted) { providers in
                handleDrop(providers)
            }
            .overlay {
                if model.isDropTargeted {
                    DropzoneOverlay()
                        .allowsHitTesting(false)
                }
            }
            // Topbar (E04.5): quota + Upgrade links, gear rechts — 1-op-1
            // de "top"-strook uit de App-frames.
            .overlay(alignment: .top) {
                ShellTopBar(model: entitlement)
            }
            // Name/Role-header (E05.5) zodra er een portret op canvas
            // staat — gecentreerd boven het canvas (Figma Frame 2, y=32).
            .overlay(alignment: .top) {
                if case .result = model.canvas {
                    PortraitHeader(model: model)
                        .padding(.top, DSSpacing.gap8)
                }
            }
    }

    @ViewBuilder
    private var canvas: some View {
        switch model.canvas {
        case .empty:
            FirstUseEmptyState {
                model.presentOpenPanel()
            }
        case .processing(let original):
            IsolatingCanvas(original: original, cutout: nil)
                .overlay(alignment: .bottomTrailing) {
                    IsolatingStatusPill(label: "Removing background...")
                        .padding(DSSpacing.gap4)
                }
        case .revealing(let original, let cutout):
            IsolatingCanvas(original: original, cutout: cutout)
                .overlay(alignment: .bottomTrailing) {
                    IsolatingStatusPill(label: "Cutting out hair...")
                        .padding(DSSpacing.gap4)
                }
        case .result(let cutout):
            // Editor-framework (E06.1): toolbar + panel-systeem rond het
            // resultaat; foto-verkleining regelt de DS-container centraal.
            EditorView(portrait: cutout)
        case .failed(let message):
            VStack(spacing: DSSpacing.gap4) {
                Text(message)
                    .dsTextStyle(.bodyMedium)
                    .foregroundStyle(DSColor.Foreground.subtle)
                    .multilineTextAlignment(.center)
                DSNeutralButton("Choose another file…") {
                    model.presentOpenPanel()
                }
            }
            .padding(DSSpacing.gap8)
        }
    }

    /// Figma App / Dropzone (4017:1622): Frame 11 465×456 gecentreerd,
    /// r-4xl, dashed b-medium in lime, vulling lime ~5% (gesampled — het
    /// frame exposeert er geen variabele voor), "Drop it" in H3 primary.
    private struct DropzoneOverlay: View {
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: DSRadius.xl4)
                    .fill(DSColor.Action.primary.opacity(0.05))
                RoundedRectangle(cornerRadius: DSRadius.xl4)
                    .strokeBorder(
                        DSColor.Action.primary,
                        style: StrokeStyle(lineWidth: DSBorderWidth.medium, dash: [2, 4])
                    )
                Text("Drop it")
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
            }
            .frame(width: 465, height: 456)
        }
    }

    private func portrait(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .padding(DSSpacing.gap8)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                Task { @MainActor in
                    await model.importImage(from: url)
                }
            }
            return true
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    await model.importImage(data: data)
                }
            }
            return true
        }
        return false
    }
}
