// Figma "Stories" → App / Hair (4114:903) → floatingToolbar (4114:978).
// E31.1: de onderste toolbar is een zwevende **capsule** (Card-fill, r-full)
// met gelabelde icoon+label-pillen + een overflow `⋯`-icoonknop. Geverifieerd
// op de render (variabelen via get_variable_defs): container = background/Card
// (#1c1917), pil = background/neutral (wit@5%), label = UI/Labels/Base
// (SF Pro Semibold 14.2), gap-2 (8) tussen pillen én als padding, knophoogte 40,
// capsule r-full (96). Active = lime (E03.3-gedrag).
//
// Undo/redo/compare (E06.6-accessoires) staan in de Figma-capsule-frame NIET; ze
// blijven als losse cirkels (DSToolButton) **náást** de Card-capsule in dezelfde
// strip — Figma-TODO: definitieve plaatsing zodra er een referentie is.

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

public struct DSBottomToolbar<ID: Hashable, Accessory: View>: View {
    private let items: [DSToolbarItem<ID>]
    private let overflow: [DSToolbarItem<ID>]
    @Binding private var selection: ID?
    private let accessory: Accessory

    public init(
        items: [DSToolbarItem<ID>],
        selection: Binding<ID?>,
        overflow: [DSToolbarItem<ID>] = [],
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.items = items
        self.overflow = overflow
        self._selection = selection
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: DSSpacing.gap2) {
            // De Figma-capsule: Card-fill r-full rondom de pillen + overflow.
            HStack(spacing: DSSpacing.gap2) {
                ForEach(items) { item in
                    DSCapsuleToolButton(
                        item.icon,
                        label: item.label,
                        isActive: selection == item.id,
                        action: { selection = selection == item.id ? nil : item.id }
                    )
                }
                if !overflow.isEmpty {
                    DSToolbarOverflowButton(items: overflow, selection: $selection)
                }
            }
            .padding(DSSpacing.gap2)
            .background(DSColor.Background.card, in: Capsule())

            // Accessoires (undo/redo/compare) blijven buiten de Card-capsule.
            accessory
        }
    }
}

// Bestaande call sites (alleen tools, geen accessoires) blijven werken via een
// EmptyView-accessory; geen verplichte trailing closure.
extension DSBottomToolbar where Accessory == EmptyView {
    public init(
        items: [DSToolbarItem<ID>],
        selection: Binding<ID?>,
        overflow: [DSToolbarItem<ID>] = []
    ) {
        self.init(items: items, selection: selection, overflow: overflow, accessory: { EmptyView() })
    }
}

/// E31.1: gelabelde capsule-pil (icoon + label) uit `floatingToolbar` (4114:978).
/// Pil = background/neutral op de Card-capsule, label = UI/Labels/Base, active =
/// lime icoon+label + lime ring (E03.3). Hoogte 40, r-full.
struct DSCapsuleToolButton: View {
    private let icon: Image
    private let label: String
    private let isActive: Bool
    private let action: () -> Void

    init(_ icon: Image, label: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap2) {
                icon.font(.system(size: 18, weight: .medium))
                Text(label).dsTextStyle(.labelBase)
            }
            .foregroundStyle(isActive ? DSColor.Action.primary : DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap3)
            .frame(height: 40)
            .background { Capsule().fill(DSColor.Background.neutral) }
            .overlay {
                Capsule()
                    .strokeBorder(DSColor.Action.primary, lineWidth: DSBorderWidth.medium)
                    .opacity(isActive ? DSOpacity.strong : DSOpacity.hidden)
            }
            .animation(.easeOut(duration: 0.15), value: isActive)
        }
        .buttonStyle(DSStateOpacityButtonStyle())
        .accessibilityLabel(Text(label))
    }
}

/// E31.1: overflow `⋯`-icoonknop (Icon-Only Button 4114:983, 40×40) die de
/// secundaire tools in een menu toont. Vertikale dots conform de Figma-render.
struct DSToolbarOverflowButton<ID: Hashable>: View {
    let items: [DSToolbarItem<ID>]
    @Binding var selection: ID?

    var body: some View {
        Menu {
            ForEach(items) { item in
                Button { selection = item.id } label: {
                    Label { Text(item.label) } icon: { item.icon }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .medium))
                .rotationEffect(.degrees(90))
                .foregroundStyle(DSColor.Foreground.primary)
                .frame(width: 40, height: 40)
                .background { Circle().fill(DSColor.Background.neutral) }
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("More tools"))
    }
}
