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

// E03.19: trailing accessoire-slot. Niet-selecteerbare knoppen (undo/redo,
// hold-to-compare) horen volgens frame App / Edit (4008:7340) ín de
// toolbar-strip op dezelfde 56-pitch (cirkels op x344/x400 = +56), niet als
// losse overlay ernaast. De `accessory`-builder hangt rechts achter de tools
// op precies die pitch (48-cirkel + gap2=8 = 56); vul 'm met DSToolButtons.
public struct DSBottomToolbar<ID: Hashable, Accessory: View>: View {
    private let items: [DSToolbarItem<ID>]
    @Binding private var selection: ID?
    private let accessory: Accessory

    public init(
        items: [DSToolbarItem<ID>],
        selection: Binding<ID?>,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.items = items
        self._selection = selection
        self.accessory = accessory()
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
            // Accessoires delen de strip op dezelfde gap2-pitch als de tools,
            // dus undo/redo lijnen op 56 uit zonder eigen container.
            accessory
        }
        .padding(DSSpacing.gap2)
    }
}

// Bestaande call sites (alleen tools, geen accessoires) blijven werken via een
// EmptyView-accessory; geen verplichte trailing closure.
extension DSBottomToolbar where Accessory == EmptyView {
    public init(items: [DSToolbarItem<ID>], selection: Binding<ID?>) {
        self.init(items: items, selection: selection, accessory: { EmptyView() })
    }
}
