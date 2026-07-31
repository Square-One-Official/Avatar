// Canvas drag-and-drop voor logo / achtergrond-image (Freeform-pariteit).

import AppKit
import AvatarUI
import SwiftUI
import UniformTypeIdentifiers

enum BannerCanvasDrop {
    /// Laadt de eerste afbeelding uit drop-providers; roept `apply` op main aan.
    @MainActor
    static func handle(
        providers: [NSItemProvider],
        apply: @escaping (PickedImage) -> Void
    ) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let url = item as? URL ?? (item as? Data).flatMap({ URL(dataRepresentation: $0, relativeTo: nil) }),
                      let raw = try? Data(contentsOf: url),
                      let picked = BannerNativePanels.pickedImage(from: raw, filename: url.lastPathComponent) else { return }
                Task { @MainActor in apply(picked) }
            }
            return true
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data, let picked = BannerNativePanels.pickedImage(from: data, filename: "dropped-image.png") else { return }
            Task { @MainActor in apply(picked) }
        }
        return true
    }
}

struct BannerCanvasDropModifier: ViewModifier {
    let isEnabled: Bool
    let onDrop: (PickedImage) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: DSRadius.xl4, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.image, .fileURL], isTargeted: $isTargeted) { providers in
                guard isEnabled else { return false }
                return BannerCanvasDrop.handle(providers: providers, apply: onDrop)
            }
    }
}

extension View {
    func bannerCanvasDrop(isEnabled: Bool, onDrop: @escaping (PickedImage) -> Void) -> some View {
        modifier(BannerCanvasDropModifier(isEnabled: isEnabled, onDrop: onDrop))
    }
}
