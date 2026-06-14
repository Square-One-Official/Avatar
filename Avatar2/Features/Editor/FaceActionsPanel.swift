// Face-paneel (E21.1, herzien E24.15) — beauty-acties als gedeelde
// thumbnail-kaarten (DSThumbnailCard, dezelfde vorm als Effects). Twee
// secties (Retouch/Beauty), elk een horizontaal scrollbare rij kaarten:
// phosphor-icoon + label, Pro-badge bovenin (gegate cloud-acties), credit-kost
// onderin. Lokale One-click retouch (aan/uit) toont de selectie-ring; de
// generatieve Pro-acties (Whiten teeth/Apply make-up/Reduce wrinkles, 4
// credits) gaan via de contextuele gate. Restore body hoort hier NIET.

import AvatarKit
import AvatarUI
import PhosphorSwift
import SwiftUI

struct FaceActionsPanel: View {
    /// E12.1: lokale Core Image-retouch (geen cloud/credits) — aan/uit.
    var onRetouch: () -> Void = {}
    /// E18.2: nog niet-gebouwde Pro-acties → contextuele gate.
    var onProFeature: () -> Void = {}
    var isPro: Bool = false
    /// E18.12: titels van lokale enhances die momenteel "aan" staan.
    var activeToggles: Set<String> = []

    private struct Card: Identifiable {
        let id = UUID()
        let title: String
        let icon: Ph
        var credits: String? = nil
        var isCloud: Bool = false
        var isOn: Bool = false
        let handler: () -> Void
    }

    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let cards: [Card]
    }

    private var sections: [Section] {
        let beautyCredits = CreditMeter.chipLabel(for: .generativeStandard)
        return [
            Section(title: "Retouch", cards: [
                Card(title: "One click retouch", icon: .magicWand,
                     isOn: activeToggles.contains("One click retouch"), handler: onRetouch),
            ]),
            Section(title: "Beauty", cards: [
                Card(title: "Whiten teeth", icon: .tooth, credits: beautyCredits, isCloud: true, handler: onProFeature),
                Card(title: "Apply make-up", icon: .palette, credits: beautyCredits, isCloud: true, handler: onProFeature),
                Card(title: "Reduce wrinkles", icon: .smiley, credits: beautyCredits, isCloud: true, handler: onProFeature),
            ]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                    Text(section.title)
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DSSpacing.gap3) {
                            ForEach(section.cards) { card in
                                Button(action: card.handler) {
                                    DSThumbnailCard(
                                        label: card.title,
                                        isPro: card.isCloud && !isPro,
                                        credits: card.credits,
                                        isSelected: card.isOn
                                    ) {
                                        card.icon.regular
                                            .scaledToFit()
                                            .frame(width: 26, height: 26)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        // Ruimte voor de hover-scale + de top-leading Pro-badge.
                        .padding(.vertical, DSSpacing.gap1)
                        .padding(.horizontal, DSSpacing.gap1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
