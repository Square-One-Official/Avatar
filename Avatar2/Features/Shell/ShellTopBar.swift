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
    /// E22.1: bibliotheek/sidebar-toggle, verhuisd uit de bottom-toolbar.
    var canToggleSidebar: Bool = false
    var isSidebarActive: Bool = false
    var onToggleSidebar: () -> Void = {}

    var body: some View {
        // E24.6: counter + Upgrade op een EIGEN rij ónder de traffic-lights,
        // ~12px (gap-3) van de linkerrand. Rij 1 = app-chrome rechts
        // (Export → Settings → Library uiterst rechts, E24.5).
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            HStack(spacing: 0) {
                Spacer()
                HStack(spacing: DSSpacing.gap2) {
                    if canExport {
                        // Frame 27 share-icoon → export/share (E08.2).
                        DSToolButton(Image(systemName: "square.and.arrow.up"), label: "Share", tooltipEdge: .bottom) {
                            onExport()
                        }
                    }
                    DSToolButton(
                        Image(systemName: "gearshape.fill"),
                        label: "Settings",
                        isActive: isSettingsActive,
                        tooltipEdge: .bottom
                    ) {
                        onToggleSettings()
                    }
                    if canToggleSidebar {
                        // E24.5: bibliotheek/sidebar-toggle UITERST RECHTS.
                        DSToolButton(
                            Image(systemName: "sidebar.right"),
                            label: "Library",
                            isActive: isSidebarActive,
                            tooltipEdge: .bottom
                        ) {
                            onToggleSidebar()
                        }
                    }
                }
                .padding(.top, DSSpacing.gap3)
                .padding(.trailing, ShellMetrics.topBarInset)
            }
            // De top-strook (h52) reserveert de hoogte van de traffic-lights.
            .frame(height: 52, alignment: .top)

            // E24.13: quota-badge alléén in de editor — NIET in Settings.
            if model.hasCompletedFirstCutout && !isSettingsActive {
                HStack(spacing: DSSpacing.gap2) {
                    Text(quotaLabel)
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.primary)
                    DSChip("Upgrade", type: .brand) {
                        model.requestUpgrade()
                    }
                }
                // E24.13: ~12px (gap-3) van de WINDOW-linkerrand.
                .padding(.leading, ShellMetrics.topBarInset)
            }
        }
        // E24.13-diagnose+fix: .overlay(alignment:.top) centreert een content-
        // sized view → de counter (rij 2) zat 12px van een GECENTREERDE kolom,
        // niet van de vensterrand. Forceer volle breedte + leading zodat de
        // leading-inset vanaf de echte vensterrand telt.
        .frame(maxWidth: .infinity, alignment: .leading)
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
