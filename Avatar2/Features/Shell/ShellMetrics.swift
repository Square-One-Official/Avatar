// Gedeelde shell-maten (E05.8). Eén bron voor de marge t.o.v. de
// vensterrand — sidebar-kaart (E03.15), topbar-cluster en toekomstige
// randelementen rekenen met hetzelfde token i.p.v. losse getallen.

import AvatarUI
import CoreGraphics

enum ShellMetrics {
    /// Marge t.o.v. de vensterrand — macOS floating-panel stijl (Freeform/Notes:
    /// ~12 pt rond sidebar + content). Was gap-1; concentric radius → zie
    /// `panelCornerRadius`.
    static let windowEdgeInset: CGFloat = DSSpacing.gap3

    /// Geen extra tussenruimte tussen sidebar-kaart en content-kolom.
    static let sidebarContentSpacing: CGFloat = 0

    /// Hoekradius van floating panelen. Bij gap-3 inset is concentric(window−inset)
    /// nul; vaste radius houdt de kaart visueel in lijn met macOS-systemapps.
    static let panelCornerRadius: CGFloat = DSRadius.xl2

    /// E18.6: gedeelde topbar-inset, gelijk aan de redo-knop rechtsonder
    /// (gap-3). Gear-trailing gebruikt deze; de counter zit dezelfde afstand
    /// ná de OS-window-controls, zodat alles "gap-3 van de dichtstbijzijnde
    /// chrome" zit.
    static let topBarInset: CGFloat = DSSpacing.gap3

    /// Links-marge van de quota-teller. De OS-traffic-lights eindigen rond
    /// x67; we zetten de teller op ~88 zodat er duidelijke ademruimte ná de
    /// groene knop staat (feedback Thierry: 72 plakte tegen de knop → cramped).
    static let topBarLeadingAfterWindowControls: CGFloat = 88

    /// Sidebar-toggle breedte (ShellSidebarChrome) — sync met SidebarToggleButton.
    static let sidebarToggleWidth: CGFloat = 28

    /// Editor-breadcrumb leading wanneer de left-nav ingeklapt is: ná traffic-
    /// lights + sidebar-toggle + ademruimte (niet onder vensterknoppen).
    static var editorBreadcrumbLeadingCollapsed: CGFloat {
        topBarLeadingAfterWindowControls + sidebarToggleWidth + DSSpacing.gap3
    }

    /// Hoogte van de band waarin de quota-teller verticaal centreert zodat
    /// hij op het hart van de traffic-lights valt. Empirisch bepaald: de
    /// traffic-light-middellijn zit op ~15,75 pt vanaf de venstertop, dus de
    /// band is 32 pt (midden ≈ 16 pt). 28 pt zette de teller ~2 pt te hoog
    /// (top-uitgelijnd i.p.v. gecentreerd → "touching the top", feedback Thierry).
    static let windowControlsRowHeight: CGFloat = 32

    /// UXS-29(v2)/UX34: middellijn van de traffic-lights vanaf de venstertop
    /// mét de lege unified toolbar (ShellSidebarChrome.stabilise) — AppKit
    /// centreert de knoppen in de hogere titelbalk, dus ín de zwevende
    /// sidebar-kaart (top-inset gap3). De sidebar-toggle lijnt op dezelfde
    /// middellijn uit. Empirisch geverifieerd op de unified-toolbar-titelbalk.
    static let windowControlsCenterFromTop: CGFloat = 26

    /// Top-inset van de content-kolom en de top-chrome-band. Dit was vóór de
    /// unified toolbar (UXS-29(v2)) de impliciete titelbalk-safe-area (~28pt);
    /// de shell-root negeert de (nu hogere) safe-area en geeft content + band
    /// deze ontwerpwaarde expliciet terug zodat hun layout identiek blijft aan
    /// vóór de toolbar — alleen de traffic-lights + sidebar-chrome liggen lager.
    static let contentTopSafeArea: CGFloat = 28

    /// Editor-topbar (breadcrumb + view-toggle + Share): control-hoogte.
    static let topBarRowHeight: CGFloat = 28

    /// Verticale offset van breadcrumb/Share t.o.v. de top-chrome-band — centreert
    /// de 28pt-controls op de traffic-light-middellijn (32pt band).
    static let topBarTopInset: CGFloat = (windowControlsRowHeight - topBarRowHeight) / 2

    /// Totale hoogte van de editor-top-chrome (gelijk aan traffic-light-rij).
    static var topBarBandHeight: CGFloat { windowControlsRowHeight }
}
