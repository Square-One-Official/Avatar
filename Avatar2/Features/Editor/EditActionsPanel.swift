// Edit-paneel actielijst (E06.3) — Figma App / Edit dropdownMenu
// (4014:10761). Het frame groepeert Retouch / Optimise / Position and
// alignment; de story vraagt **zakelijke acties boven beauty-acties**, dus
// de volgorde hier is Position → Optimise → Retouch (beauty onderaan).
// Elke actie is een pill-rij met links het label en — voor cloud/
// generatieve acties — een gating-chip (DSProChip); lokale gratis acties
// (uitlijnen) krijgen geen chip. Exacte credit-labels komen uit de
// CreditMeter (E14.3); tot die landt tonen cloud-acties de default
// "Pro"-chip als gating-indicator. Op één na zijn de acties stubs — het
// paneel krijgt nog een design-iteratie (story: vervangbaar bouwen).
//
// Geïmplementeerde actie: "Auto-crop & center" → AutoFramer (E06.5).

import AvatarKit
import AvatarUI
import SwiftUI

struct EditActionsPanel: View {
    /// Auto-crop & center draait op het geselecteerde portret (E06.5).
    let onAutomaticFraming: () -> Void
    /// E12.1: lokale Core Image-retouch + belichting (geen cloud/credits).
    var onRetouch: () -> Void = {}
    var onImproveLighting: () -> Void = {}
    /// E10.3: cloud-upscale ("Boost resolution", 1 credit) + busy-vlag.
    var onBoostResolution: () -> Void = {}
    var isBoosting: Bool = false
    /// E18.2: nog niet-gebouwde Pro-acties zijn klikbaar → contextuele gate
    /// (online/login/upgrade) i.p.v. een dode/gedimde knop.
    var onProFeature: () -> Void = {}

    private struct Action: Identifiable {
        let id = UUID()
        let title: String
        /// E14.3: credit-tier voor het kosten-label. nil = lokaal/gratis óf
        /// (bij isCloud) een nog-niet-vastgesteld tarief → generieke chip.
        let meter: CreditMeter.Action?
        let isCloud: Bool
        let handler: (() -> Void)?
    }

    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let actions: [Action]
    }

    private var sections: [Section] {
        [
            // Zakelijk eerst. Uitlijnen draait on-device → geen credits.
            Section(title: "Position and alignment", actions: [
                Action(title: "Auto-crop & center", meter: nil, isCloud: false, handler: onAutomaticFraming),
                Action(title: "Fix camera angle", meter: nil, isCloud: false, handler: nil),
            ]),
            Section(title: "Optimise", actions: [
                Action(title: "Colorise", meter: .colorize, isCloud: true, handler: onProFeature),
                // Boost resolution: 1 credit (besluit Thierry 2026-06-13;
                // upscale = lichte cloud-call). E10.3: Real-ESRGAN, gewired.
                Action(title: "Boost resolution", meter: .upscale, isCloud: true, handler: onBoostResolution),
            ]),
            // Beauty onderaan. One-click retouch + Improve lighting zijn
            // sinds E12.1 lokale Core Image-acties (geen credits/chip);
            // gerichte semantische edits (tanden/rimpels/make-up) blijven
            // generatief (4); Restore body = fill-body-route (2).
            Section(title: "Retouch", actions: [
                Action(title: "One click retouch", meter: nil, isCloud: false, handler: onRetouch),
                Action(title: "Improve lighting", meter: nil, isCloud: false, handler: onImproveLighting),
                Action(title: "Whiten teeth", meter: .generativeStandard, isCloud: true, handler: onProFeature),
                Action(title: "Apply make-up", meter: .generativeStandard, isCloud: true, handler: onProFeature),
                Action(title: "Reduce wrinkles", meter: .generativeStandard, isCloud: true, handler: onProFeature),
                Action(title: "Restore body", meter: .fillBody, isCloud: true, handler: onProFeature),
            ]),
        ]
    }

    private let columns = [
        GridItem(.flexible(), spacing: DSSpacing.gap2),
        GridItem(.flexible(), spacing: DSSpacing.gap2),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            if isBoosting {
                HStack(spacing: DSSpacing.gap2) {
                    ProgressView().controlSize(.small)
                    Text("Boosting resolution…")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                }
            }
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                    Text(section.title)
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: DSSpacing.gap2) {
                        ForEach(section.actions) { action in
                            row(action)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(isBoosting)
    }

    private func row(_ action: Action) -> some View {
        Button {
            action.handler?()
        } label: {
            HStack(spacing: DSSpacing.gap2) {
                Text(action.title)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                    .lineLimit(1)
                Spacer(minLength: DSSpacing.gap2)
                if let meter = action.meter {
                    // E14.3: kosten in credits vóór uitvoering.
                    DSProChip(CreditMeter.chipLabel(for: meter))
                } else if action.isCloud {
                    // Cloud-actie met nog niet-vastgesteld tarief.
                    DSProChip()
                }
            }
            .padding(.horizontal, DSSpacing.gap4)
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.Background.neutral)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl))
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.xl))
        }
        .buttonStyle(.plain)
        // Stubs (handler == nil) zijn nog niet actief; visueel gedimd.
        .opacity(action.handler == nil ? 0.55 : 1)
        .disabled(action.handler == nil)
    }
}
