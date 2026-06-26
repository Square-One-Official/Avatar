// FigJam-stijl naam-chip linksboven het frame (E33). Vervangt de gecentreerde
// PortraitHeader in de enkel-editor: toont de portretnaam als pill; dubbelklik
// opent de rename-modal (FigJam-conventie). Het frame is altijd actief — de chip
// deelt één rij met Frame/Background/grid naast de kaart.
// Naam/fallback-logica 1-op-1 uit de oude PortraitHeader.

import AvatarUI
import SwiftUI

struct CanvasFrameChip: View {
    var name: String?
    var onRename: () -> Void

    private var displayName: String {
        let n = name ?? ""
        return n.isEmpty ? "Name" : n
    }
    private var hasName: Bool { !(name ?? "").isEmpty }

    var body: some View {
        Text(displayName)
            .dsTextStyle(.bodyMedium)
            .foregroundStyle(hasName ? DSColor.Foreground.primary : DSColor.Foreground.muted)
            .lineLimit(1)
            .frame(height: 28)
            .padding(.horizontal, DSSpacing.gap3)
            .background(DSColor.Background.card, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(EditorView.frameSelectionGrey, lineWidth: 1.5)
            )
            .contentShape(Capsule(style: .continuous))
            .onTapGesture(count: 2) { onRename() }
            .help("Double-click to rename")
    }
}
