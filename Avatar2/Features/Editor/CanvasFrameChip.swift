// FigJam-stijl naam-chip linksboven het frame (E33). Vervangt de gecentreerde
// PortraitHeader in de enkel-editor: toont de portretnaam als pill die
//   - bij een single-click het frame selecteert (top-toolbar + ring terug), en
//   - bij een dubbelklik de rename-modal opent (FigJam-conventie).
// De active-stijl (neutraal-grijze rand) volgt de frame-selectie; de naam is áltijd
// zichtbaar (ook gedeselecteerd), net als de "Section 1"-labels in FigJam.
// Naam/fallback-logica 1-op-1 uit de oude PortraitHeader.

import AvatarUI
import SwiftUI

struct CanvasFrameChip: View {
    var name: String?
    var isActive: Bool
    var onSelect: () -> Void
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
                // Active = neutraal-grijze rand (macOS-stijl, cohesie met de OUTER
                // frame-ring — géén lime); rust = subtiele neutral-rand.
                Capsule(style: .continuous)
                    .strokeBorder(
                        isActive ? EditorView.frameSelectionGrey : DSColor.Background.neutralStronger,
                        lineWidth: isActive ? 1.5 : 1
                    )
            )
            .contentShape(Capsule(style: .continuous))
            // Dubbelklik vóór single zodat hij voorrang krijgt (FigJam: klik =
            // selecteren, dubbelklik = hernoemen).
            .onTapGesture(count: 2) { onRename() }
            .onTapGesture { onSelect() }
            // Alleen een opacity-/kleur-crossfade van de rand (geen beweging) —
            // reduced-motion-bewust via dsMotion.
            .dsMotion(DSMotion.fast, value: isActive)
            .help("Click to select · double-click to rename")
    }
}
