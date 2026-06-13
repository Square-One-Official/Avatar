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
                // …direct na de OS-window-controls (E05.8: afgeleide
                // constante i.p.v. magic 76).
                .padding(.leading, ShellMetrics.topBarLeadingAfterWindowControls)
            }
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
            // E05.8: trailing = het venster-marge-token (zelfde rand als
            // de sidebar-kaart) i.p.v. de losse 16 uit het frame — besluit
            // Thierry 13 jun. Top houdt het strook-ritme (Frame 27: y12).
            .padding(.top, DSSpacing.gap3)
            .padding(.trailing, ShellMetrics.windowEdgeInset)
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
