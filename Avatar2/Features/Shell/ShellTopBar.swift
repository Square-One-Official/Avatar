// Shell-topbar (E04.5 + visuele pass punt 15, Figma: App-frames node "top"
// 4017:1921 + gear "Frame 27"). De quota-regel begint exact op x76 — vlak
// naast de window-controls (x16–68) — en zit verticaal gecentreerd op
// dezelfde regel (strook h52, middellijn y26): tekst y18/h16, chip y14/h24.
// De gear (48-cirkel) hangt op y12 met trailing 16. Zichtbaarheid
// quota/Upgrade volgt het E05.1-besluit (pas ná de eerste cutout).
// Punt 14: de gear toggelt de in-window Settings en toont de active-state.

import AvatarKit
import AvatarUI
import SwiftUI

struct ShellTopBar: View {
    let model: EntitlementModel
    let isSettingsActive: Bool
    let onToggleSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if model.hasCompletedFirstCutout {
                HStack(spacing: DSSpacing.gap2) {
                    Text(quotaLabel)
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.primary)
                    DSChip("Upgrade", type: .brand) {
                        model.requestUpgrade()
                    }
                }
                // Figma "top": kwota-regel gecentreerd in de 52-strook…
                .frame(height: 52)
                // …en exact op x76, direct na de window-controls.
                .padding(.leading, 76)
            }
            Spacer()
            DSToolButton(
                Image(systemName: "gearshape.fill"),
                label: "Settings",
                isActive: isSettingsActive
            ) {
                onToggleSettings()
            }
            // Figma "Frame 27": gear op y12, 16 uit de rechterrand.
            .padding(.top, DSSpacing.gap3)
            .padding(.trailing, DSSpacing.gap4)
        }
        .task { await model.refresh() }
    }

    private var quotaLabel: String {
        if model.isProActive {
            return "\(model.creditsRemaining) credits"
        }
        if let free = model.freeImportsRemaining {
            return "\(free)/\(FreeTier.maxPortraits) left"
        }
        return ""
    }
}
