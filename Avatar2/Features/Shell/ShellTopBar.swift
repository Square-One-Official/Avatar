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
        // E24.20: counter + Upgrade staan nu op DEZELFDE regel als de
        // top-right app-chrome (Export/Settings/Library) — verticaal uitgelijnd
        // met die iconen én de Name/Role-kop (die ook op gap-3 vanaf de top
        // hangt). Counter links (ná de traffic-lights), iconen rechts.
        HStack(alignment: .center, spacing: 0) {
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
                // Voorbij de window-controls (traffic-lights) i.p.v. eronder.
                .padding(.leading, ShellMetrics.topBarLeadingAfterWindowControls)
            }

            Spacer(minLength: DSSpacing.gap2)

            HStack(spacing: DSSpacing.gap2) {
                if canExport {
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
            .padding(.trailing, ShellMetrics.topBarInset)
        }
        // De top-strook (h52) reserveert de hoogte van de traffic-lights; alles
        // op gap-3 vanaf de top zodat het met de Name/Role-kop uitlijnt.
        .padding(.top, DSSpacing.gap3)
        .frame(height: 52, alignment: .top)
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
