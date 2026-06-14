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
    /// E08.2: export/share. Verborgen tot er een portret op het canvas staat.
    var canExport: Bool = false
    var onExport: () -> Void = {}

    var body: some View {
        // E18.14: counter op een EIGEN rij ónder de OS-traffic-lights, zodat
        // hij écht ~12pt (gap-3) van de linkerrand zit i.p.v. ~72pt ernaast.
        // Rij 1 = de top-strook met rechts Share/Settings (de lights bezetten
        // links); rij 2 = quota + Upgrade, gap-3 van de rand.
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            HStack(spacing: 0) {
                Spacer()
                HStack(spacing: DSSpacing.gap2) {
                    if canExport {
                        // Frame 27 share-icoon → export/share (E08.2).
                        DSToolButton(Image(systemName: "square.and.arrow.up"), label: "Share") {
                            onExport()
                        }
                    }
                    DSToolButton(
                        Image(systemName: "gearshape.fill"),
                        label: "Settings",
                        isActive: isSettingsActive
                    ) {
                        onToggleSettings()
                    }
                }
                // E18.6: trailing = gedeelde topbar-inset (gap-3), gelijk aan
                // de redo-knop rechtsonder — niet tegen de vensterrand geplakt.
                .padding(.top, DSSpacing.gap3)
                .padding(.trailing, ShellMetrics.topBarInset)
            }
            // De top-strook (h52) reserveert de hoogte van de traffic-lights,
            // zodat de counter eronder valt i.p.v. ernaast.
            .frame(height: 52, alignment: .top)

            if model.hasCompletedFirstCutout {
                HStack(spacing: DSSpacing.gap2) {
                    Text(quotaLabel)
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.primary)
                    DSChip("Upgrade", type: .brand) {
                        model.requestUpgrade()
                    }
                }
                // E18.14: gap-3 van de linkerrand (gelijk aan de gear-trailing).
                .padding(.leading, ShellMetrics.topBarInset)
            }
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
