// Clothes-paneel (E10.2, Figma App / Clothes 4016:13760): "Change upper
// clothes" + vaste outfit-chips + een vrije prompt ("Describe a color or
// style") met lime send-knop.
//
// Generatie-route is een open architectuurbeslissing (DECISIONS-PENDING):
// E10.1 bouwde een kledingmasker voor een masked FLUX-Fill-route, maar de
// E09.1-bakeoff koos nano-banana instruction-edit (zónder mask) als beste
// voor kledingwissel. Tot dat besluit valt is de generate-actie een stub;
// het paneel + de input zijn volledig (vervangbaar bouwen). Kosten:
// generatief standaard = 4 credits (CreditMeter), getoond bij de actie in
// het Edit-paneel (E06.3) — hier volgt het frame (geen losse chip).

import AvatarUI
import SwiftUI

struct ClothesPanel: View {
    /// Stub tot de generatie-route vastligt; krijgt de gekozen prompt mee.
    var onApply: (String) -> Void = { _ in }

    @State private var prompt = ""

    private let presets = ["T-Shirt", "Polo", "Blazer", "Hoody", "Sweater"]

    var body: some View {
        DSEditPanel(title: "Change upper clothes") {
            VStack(alignment: .leading, spacing: DSSpacing.gap3) {
                // Outfit-presets.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.gap2) {
                        ForEach(presets, id: \.self) { preset in
                            DSChip(preset, type: .neutral) {
                                onApply(preset)
                            }
                        }
                    }
                }

                // Vrije prompt + send.
                HStack(spacing: DSSpacing.gap2) {
                    DSTextField(placeholder: "Describe a color or style", text: $prompt)
                    Button {
                        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onApply(trimmed)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DSColor.Action.onAction)
                            .frame(width: 40, height: 40)
                            .background(DSColor.Action.primary)
                            .clipShape(Circle())
                            .opacity(prompt.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
