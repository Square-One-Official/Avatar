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

import AvatarUI
import SwiftUI

struct EditActionsPanel: View {
    /// Auto-crop & center draait op het geselecteerde portret (E06.5).
    let onAutomaticFraming: () -> Void

    private struct Action: Identifiable {
        let id = UUID()
        let title: String
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
            // Zakelijk eerst.
            Section(title: "Position and alignment", actions: [
                Action(title: "Auto-crop & center", isCloud: false, handler: onAutomaticFraming),
                Action(title: "Fix camera angle", isCloud: false, handler: nil),
            ]),
            Section(title: "Optimise", actions: [
                Action(title: "Colorise", isCloud: true, handler: nil),
                Action(title: "Boost resolution", isCloud: true, handler: nil),
            ]),
            // Beauty onderaan.
            Section(title: "Retouch", actions: [
                Action(title: "One click retouch", isCloud: true, handler: nil),
                Action(title: "Whiten teeth", isCloud: true, handler: nil),
                Action(title: "Apply make-up", isCloud: true, handler: nil),
                Action(title: "Reduce wrinkles", isCloud: true, handler: nil),
                Action(title: "Improve lighting", isCloud: true, handler: nil),
                Action(title: "Restore body", isCloud: true, handler: nil),
            ]),
        ]
    }

    private let columns = [
        GridItem(.flexible(), spacing: DSSpacing.gap2),
        GridItem(.flexible(), spacing: DSSpacing.gap2),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
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
                if action.isCloud {
                    // Gating-indicator; CreditMeter (E14.3) vult straks het
                    // echte credit-label in.
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
