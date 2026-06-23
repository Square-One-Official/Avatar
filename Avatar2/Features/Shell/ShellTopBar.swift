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
    /// E27.4: board-modus-toggle (alle portretten op één canvas).
    var canToggleBoard: Bool = false
    var isBoardActive: Bool = false
    var onToggleBoard: () -> Void = {}
    /// E22.1: bibliotheek/sidebar-toggle, verhuisd uit de bottom-toolbar.
    var canToggleSidebar: Bool = false
    var isSidebarActive: Bool = false
    var onToggleSidebar: () -> Void = {}

    /// Visuele-verificatie-haak: toon de quota-badge met een vaste preview-
    /// tekst zonder ingelogd account (--badge-preview). No-op in normale runs.
    private static let isBadgePreview =
        ProcessInfo.processInfo.arguments.contains("--badge-preview")

    var body: some View {
        // Feedback Thierry (Granola-referentie): de quota-teller hoort op
        // DEZELFDE regel als de traffic-lights (venstertop), niet eronder.
        // De 48 pt tool-knoppen passen niet op die regel zonder de window-
        // controls te raken, dus teller en tools liggen in twee lagen: de
        // teller gecentreerd op de window-controls-regel (28 pt), de tools in
        // hun eigen h52-strook eronder.
        ZStack(alignment: .topLeading) {
            toolCluster
            quotaCluster
        }
        .animation(.easeOut(duration: 0.18), value: isSettingsActive)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await model.refresh() }
    }

    // E24.13: quota-badge alléén ná de eerste cutout en NIET in Settings.
    // Kruisvervaag op opacity (i.p.v. wegnemen) zodat de linkerkant niet
    // wegklapt tijdens de Settings-toggle.
    @ViewBuilder
    private var quotaCluster: some View {
        if model.hasCompletedFirstCutout || Self.isBadgePreview {
            HStack(spacing: DSSpacing.gap2) {
                Text(quotaLabel)
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.primary)
                DSChip("Upgrade", type: .brand) {
                    model.requestUpgrade()
                }
            }
            // Voorbij de window-controls (links) én verticaal gecentreerd op de
            // traffic-light-regel (28 pt vanaf de venstertop) i.p.v. tegen de
            // 48 pt tool-knoppen — dát duwde 'm een regel te laag. ignoresSafeArea
            // borgt dat we ook bij een eventuele top-safe-area op die regel blijven.
            .padding(.leading, ShellMetrics.topBarLeadingAfterWindowControls)
            .frame(height: ShellMetrics.windowControlsRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ignoresSafeArea(.container, edges: .top)
            .opacity(isSettingsActive ? 0 : 1)
            .allowsHitTesting(!isSettingsActive)
        }
    }

    // Punt 14-vervolg: de editor-cluster en de Close-knop liggen in een
    // trailing-uitgelijnde ZStack en kruisvervagen op `isSettingsActive`.
    // Zo verspringt er niets bij het openen van Settings — een tandwiel opent,
    // een ✕ sluit (geen dubbelzinnige "actieve gear"). Eigen h52-strook
    // (gap-3 vanaf de top) zodat de 48 pt-knoppen vrij van de window-controls
    // blijven.
    private var toolCluster: some View {
        HStack(spacing: 0) {
            Spacer(minLength: DSSpacing.gap2)
            ZStack(alignment: .trailing) {
                HStack(spacing: DSSpacing.gap2) {
                    if canExport {
                        DSToolButton(Image(systemName: "square.and.arrow.up"), label: "Share", tooltipEdge: .bottom) {
                            onExport()
                        }
                    }
                    DSToolButton(
                        Image(systemName: "gearshape.fill"),
                        label: "Settings",
                        tooltipEdge: .bottom
                    ) {
                        onToggleSettings()
                    }
                    if canToggleBoard {
                        // E27.4: board-modus (alle portretten op één canvas).
                        DSToolButton(
                            Image(systemName: "square.grid.2x2"),
                            label: "Board",
                            isActive: isBoardActive,
                            tooltipEdge: .bottom
                        ) {
                            onToggleBoard()
                        }
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
                .opacity(isSettingsActive ? 0 : 1)
                .allowsHitTesting(!isSettingsActive)

                // Enige knop in Settings-modus: ✕ uiterst rechts (de hoek waar
                // de Library-knop stond). `xmark` = het canonieke sluit-glyph.
                DSToolButton(Image(systemName: "xmark"), label: "Close", tooltipEdge: .bottom) {
                    onToggleSettings()
                }
                .opacity(isSettingsActive ? 1 : 0)
                .allowsHitTesting(isSettingsActive)
            }
            .padding(.trailing, ShellMetrics.topBarInset)
        }
        .padding(.top, DSSpacing.gap3)
        .frame(height: 52, alignment: .top)
    }

    // Besluit Thierry (Granola-referentie): aftellende teller "X left of Y" —
    // resterend van het totaal, telt af naar 0. Semantiek volgt v1's
    // "X of 3 left".
    private var quotaLabel: String {
        if Self.isBadgePreview { return "147 left of 200" }
        if model.isProActive {
            // Resterende credits over de maand-grant. Top-ups stapelen bóven
            // de grant (verlopen nooit) → dan is er geen vaste noemer en valt
            // de teller terug op de kale balans i.p.v. een misleidende "523 left of 200".
            let quota = model.monthlyQuota
            if quota > 0, model.creditsRemaining <= quota {
                return "\(model.creditsRemaining) left of \(quota)"
            }
            return "\(model.creditsRemaining) credits"
        }
        if let free = model.freeImportsRemaining {
            // Resterend van de free-cap. Clamp tegen serverskew zodat het totaal klopt.
            let remaining = max(0, min(FreeTier.maxPortraits, free))
            return "\(remaining) left of \(FreeTier.maxPortraits)"
        }
        return ""
    }
}
