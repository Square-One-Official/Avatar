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
            // Heel het venster is droptarget (Fitts); glow op de rand
            // zolang er iets boven hangt.
            .onDrop(of: [.fileURL, .image], isTargeted: $model.isDropTargeted) { providers in
                handleDrop(providers)
            }
            .overlay {
                if model.isDropTargeted {
                    RoundedRectangle(cornerRadius: DSRadius.xl)
                        .strokeBorder(
                            DSColor.Action.primary,
                            style: StrokeStyle(lineWidth: DSBorderWidth.medium, dash: [8, 6])
                        )
                        .padding(DSSpacing.gap2)
                        .allowsHitTesting(false)
                }
            }
            // Tijdelijke paywall-opstap (E08.3) tot E06 echte gating levert.
            .overlay(alignment: .topTrailing) {
                EntitlementStatusStrip(model: entitlement)
                    .padding(DSSpacing.gap4)
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
            portrait(original)
                .opacity(DSOpacity.subtle)
                .overlay(alignment: .bottom) {
                    // Minimale staat; E05.3 levert de echte isolating-
                    // animatie met fade-out en 'Cutting out hair…'-copy.
                    Text("Isolating…")
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.subtle)
                        .padding(.bottom, DSSpacing.gap6)
                }
        case .result(let cutout):
            portrait(cutout)
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
