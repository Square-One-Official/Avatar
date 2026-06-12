// Figma "Stories" → App / Edit e.v. (dark) → Toolbar (4016:3746).
// Container: hstack gap-2, padding gap-2, geen fill (radius 68 is in Figma
// puur cosmetisch). Tool: 48×48 cirkel, bg background/neutral, icoon 18pt
// medium in foreground/primary. Actieve tool: ring border-width/b-medium
// in foreground/action/primary (lime) + icoon in lime. Undo/redo naast de
// toolbar zijn losse DSIconButtons (E06), geen selecteerbare tools.

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
                ToolButton(
                    item: item,
                    isActive: selection == item.id,
                    action: { selection = selection == item.id ? nil : item.id }
                )
            }
        }
        .padding(DSSpacing.gap2)
    }

    private struct ToolButton: View {
        let item: DSToolbarItem<ID>
        let isActive: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                item.icon
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isActive ? DSColor.Action.primary : DSColor.Foreground.primary)
                    .frame(width: 48, height: 48)
                    .background(DSColor.Background.neutral, in: Circle())
                    .overlay {
                        if isActive {
                            Circle().strokeBorder(
                                DSColor.Action.primary,
                                lineWidth: DSBorderWidth.medium
                            )
                        }
                    }
            }
            .buttonStyle(DSStateOpacityButtonStyle())
            .accessibilityLabel(item.label)
        }
    }
}
