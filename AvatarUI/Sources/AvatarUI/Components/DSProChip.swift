// Gating-patroon (bouwplan 3.4, design-review "rode draad 3"): Figma heeft
// géén los gating-component — de visuele taal is de brand-Badge ("Upgrade"
// in de topbar en op de Pro-kaart van de Upgrade Modal, 4019:953). DSProChip
// hergebruikt die badge 1-op-1; DSGated is het ene patroon waarmee ALLE
// features vergrendelen (les uit v1: niet versnipperen).
//
// E03.7: per-feature-indicatoren. De Pro-chip op vergrendelde features en
// een cloud/AI-glyph (online vereist én online uit) zijn zelf tikbaar: een
// popover met korte uitleg + route (upgrade resp. Settings > AI & Models).
// Geen modals of blokkades — de indicatoren informeren; het DSGated-gedrag
// (élke tik op vergrendelde inhoud → onUpgradeRequested) blijft het enige
// gate-mechanisme. De requiresCloud-vlag per actie komt uit CreditMeter
// (E14.3); de aanroeper geeft hem door.

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

/// Tikbare per-feature-indicator: toont een popover met één regel uitleg
/// en een route. `.pro` = brand-chip → upgrade; `.cloudOff` = cloud-glyph
/// (neutral cirkel, zoals Icon-Only Button Small) → Settings > AI & Models.
public struct DSFeatureIndicator: View {
    public enum Kind: Sendable {
        case pro
        case cloudOff
    }

    private let kind: Kind
    private let chipLabel: String
    private let onRoute: () -> Void
    @State private var isShowingExplanation = false

    public init(_ kind: Kind, chipLabel: String = "Pro", onRoute: @escaping () -> Void) {
        self.kind = kind
        self.chipLabel = chipLabel
        self.onRoute = onRoute
    }

    public var body: some View {
        Button {
            isShowingExplanation = true
        } label: {
            switch kind {
            case .pro:
                DSProChip(chipLabel)
            case .cloudOff:
                Image(systemName: "cloud.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .padding(DSSpacing.gap1)
                    .background(DSColor.Background.neutral, in: Circle())
            }
        }
        .buttonStyle(DSStateOpacityButtonStyle())
        .dsFocusEffectDisabled()
        .accessibilityLabel(Text(kind == .pro ? chipLabel : "Online AI models off"))
        .popover(isPresented: $isShowingExplanation, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                Text(explanation)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    isShowingExplanation = false
                    onRoute()
                } label: {
                    Text(routeLabel)
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Action.primaryForeground)
                }
                .buttonStyle(DSStateOpacityButtonStyle())
                .dsFocusEffectDisabled()
            }
            .padding(DSSpacing.gap4)
            .frame(width: 240, alignment: .leading)
        }
    }

    private var explanation: String {
        switch kind {
        case .pro: "This feature is part of Aaavatar Pro."
        case .cloudOff: "This feature uses online AI models, which are turned off."
        }
    }

    private var routeLabel: String {
        switch kind {
        case .pro: "Upgrade"
        case .cloudOff: "Open AI & Models settings"
        }
    }
}

/// Hét gating-patroon: wikkel een feature-control in `DSGated`. Vergrendeld
/// krijgt de inhoud een Pro-indicator (top-trailing, inzet gap-1), wordt de
/// eigen interactie uitgeschakeld en gaat élke tik op de inhoud naar
/// `onUpgradeRequested` (hover/pressed via de Figma-opacitystates).
/// Ontgrendeld rendert de inhoud onaangeroerd. Vereist de feature online
/// (`requiresOnline`) terwijl online uit staat (`isOnlineEnabled == false`),
/// dan komt er een cloud-glyph naast — tik → uitleg + `onOpenAISettings`.
public struct DSGated<Content: View>: View {
    private let isLocked: Bool
    private let chipLabel: String
    private let requiresOnline: Bool
    private let isOnlineEnabled: Bool
    private let onUpgradeRequested: () -> Void
    private let onOpenAISettings: (() -> Void)?
    private let content: Content

    public init(
        isLocked: Bool,
        chipLabel: String = "Pro",
        requiresOnline: Bool = false,
        isOnlineEnabled: Bool = true,
        onUpgradeRequested: @escaping () -> Void,
        onOpenAISettings: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.isLocked = isLocked
        self.chipLabel = chipLabel
        self.requiresOnline = requiresOnline
        self.isOnlineEnabled = isOnlineEnabled
        self.onUpgradeRequested = onUpgradeRequested
        self.onOpenAISettings = onOpenAISettings
        self.content = content()
    }

    public var body: some View {
        if isLocked {
            Button(action: onUpgradeRequested) {
                content
                    .allowsHitTesting(false)
            }
            .buttonStyle(DSStateOpacityButtonStyle())
            .dsFocusEffectDisabled()
            .accessibilityHint(Text(chipLabel))
            .overlay(alignment: .topTrailing) { indicators }
        } else {
            content
                .overlay(alignment: .topTrailing) { indicators }
        }
    }

    /// Indicatoren los van de gate-knop, zodat ze zelf tikbaar zijn.
    @ViewBuilder private var indicators: some View {
        HStack(spacing: DSSpacing.gap1) {
            if requiresOnline && !isOnlineEnabled {
                DSFeatureIndicator(.cloudOff) { onOpenAISettings?() }
            }
            if isLocked {
                DSFeatureIndicator(.pro, chipLabel: chipLabel, onRoute: onUpgradeRequested)
            }
        }
        .padding(DSSpacing.gap1)
    }
}
