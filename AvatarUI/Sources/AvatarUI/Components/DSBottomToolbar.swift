// Figma "Stories" → App / Edit e.v. (dark) → Toolbar (4016:3746).
// Container: hstack gap-2, padding gap-2, geen fill (radius 68 is in Figma
// puur cosmetisch). Tool: DSToolButton (E03.11) — 48-cirkel met glass-
// surface, icoon 18pt medium in foreground/primary, actief = lime ring
// b-medium + lime icoon. Undo/redo naast de toolbar zijn losse knoppen
// (E06), geen selecteerbare tools.

import SwiftUI

public struct DSToolbarItem<ID: Hashable>: Identifiable {
    public let id: ID
    public let icon: Image
    public let label: String

    public init(id: ID, icon: Image, label: String) {
        self.id = id
        self.icon = icon
        self.label = label
    }
}

public struct DSBottomToolbar<ID: Hashable>: View {
    private let items: [DSToolbarItem<ID>]
    @Binding private var selection: ID?

    public init(items: [DSToolbarItem<ID>], selection: Binding<ID?>) {
        self.items = items
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: DSSpacing.gap2) {
            ForEach(items) { item in
                // Glass-surface via DSToolButton (E03.11).
                DSToolButton(
                    item.icon,
                    label: item.label,
                    isActive: selection == item.id,
                    action: { selection = selection == item.id ? nil : item.id }
                )
            }
        }
        .padding(DSSpacing.gap2)
    }
}
