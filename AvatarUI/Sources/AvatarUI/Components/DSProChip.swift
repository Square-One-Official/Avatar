// Gating-patroon (bouwplan 3.4, design-review "rode draad 3"): Figma heeft
// géén los gating-component — de visuele taal is de brand-Badge ("Upgrade"
// in de topbar en op de Pro-kaart van de Upgrade Modal, 4019:953). DSProChip
// hergebruikt die badge 1-op-1; DSGated is het ene patroon waarmee ALLE
// features vergrendelen (les uit v1: niet versnipperen).

import SwiftUI

/// Pro-markering: brand-badge (lime) met standaardlabel "Pro". Geef een
/// eigen label mee voor credit-kosten (bv. "2 credits").
public struct DSProChip: View {
    private let label: String

    public init(_ label: String = "Pro") {
        self.label = label
    }

    public var body: some View {
        DSBadge(label, type: .brand)
    }
}

/// Hét gating-patroon: wikkel een feature-control in `DSGated`. Vergrendeld
/// krijgt de inhoud een DSProChip (top-trailing, inzet gap-1), wordt de
/// eigen interactie uitgeschakeld en gaat élke tik naar
/// `onUpgradeRequested` (hover/pressed via de Figma-opacitystates).
/// Ontgrendeld rendert de inhoud onaangeroerd.
public struct DSGated<Content: View>: View {
    private let isLocked: Bool
    private let chipLabel: String
    private let onUpgradeRequested: () -> Void
    private let content: Content

    public init(
        isLocked: Bool,
        chipLabel: String = "Pro",
        onUpgradeRequested: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isLocked = isLocked
        self.chipLabel = chipLabel
        self.onUpgradeRequested = onUpgradeRequested
        self.content = content()
    }

    public var body: some View {
        if isLocked {
            Button(action: onUpgradeRequested) {
                content
                    .allowsHitTesting(false)
                    .overlay(alignment: .topTrailing) {
                        DSProChip(chipLabel)
                            .padding(DSSpacing.gap1)
                    }
            }
            .buttonStyle(DSStateOpacityButtonStyle())
            .accessibilityHint(Text(chipLabel))
        } else {
            content
        }
    }
}
