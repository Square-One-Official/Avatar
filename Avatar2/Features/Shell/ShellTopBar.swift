// Shell-topbar (PoC left-nav herziening). Sterk uitgekleed: de credits-teller,
// de gear (Settings), de board- en de rechter-sidebar-toggle zijn weg — die
// leven nu in de left-nav. Wat overblijft:
//   • een SUBTIELE reveal-knop náást de traffic-lights wanneer de nav is
//     ingeklapt (Granola-stijl; bij open nav zit de inklap-toggle ín de nav);
//   • rechts de editor-chrome (Share), die ALLEEN tijdens het bewerken van een
//     portret zichtbaar is — niet op Home of in de Portraits-grid;
//   • een ✕ om de in-window Settings te sluiten.

import AvatarUI
import SwiftUI

struct ShellTopBar: View {
    let isSettingsActive: Bool
    let onToggleSettings: () -> Void
    /// Editor-chrome (Share) toont ALLEEN tijdens het bewerken van een portret.
    var isEditing: Bool = false
    var canExport: Bool = false
    var onExport: () -> Void = {}
    /// PoC (left-nav): subtiele reveal-knop náást de traffic-lights wanneer de
    /// nav is ingeklapt. Bij open nav zit de toggle ín de nav-header.
    var isLeftNavVisible: Bool = false
    var onToggleLeftNav: () -> Void = {}

    var body: some View {
        ZStack(alignment: .topLeading) {
            revealCluster
            toolCluster
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.18), value: isSettingsActive)
    }

    // Subtiele reveal náást de traffic-lights — alleen als de nav verborgen is.
    @ViewBuilder
    private var revealCluster: some View {
        if !isLeftNavVisible {
            Button { onToggleLeftNav() } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(DSColor.Foreground.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show sidebar")
            .padding(.leading, ShellMetrics.topBarLeadingAfterWindowControls)
            .frame(height: ShellMetrics.windowControlsRowHeight)
            .ignoresSafeArea(.container, edges: .top)
        }
    }

    // Rechts: editor-chrome (Share) tijdens bewerken; ✕ in Settings-modus.
    private var toolCluster: some View {
        HStack(spacing: 0) {
            Spacer(minLength: DSSpacing.gap2)
            ZStack(alignment: .trailing) {
                HStack(spacing: DSSpacing.gap2) {
                    if isEditing && canExport {
                        DSToolButton(Image(systemName: "square.and.arrow.up"), label: "Share", tooltipEdge: .bottom) {
                            onExport()
                        }
                    }
                }
                .opacity(isSettingsActive ? 0 : 1)
                .allowsHitTesting(!isSettingsActive)

                // Enige knop in Settings-modus: ✕ sluit (canonieke sluit-glyph).
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
}
