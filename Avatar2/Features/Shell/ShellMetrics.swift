// Gedeelde shell-maten (E05.8). Eén bron voor de marge t.o.v. de
// vensterrand — sidebar-kaart (E03.15), topbar-cluster en toekomstige
// randelementen rekenen met hetzelfde token i.p.v. losse getallen.

import Foundation
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

    /// Editor-breadcrumb leading wanneer de left-nav ingeklapt is: direct ná de
    /// sidebar-toggle, op dezelfde rij als traffic-lights + toggle.
    static var editorBreadcrumbLeadingCollapsed: CGFloat {
        topBarLeadingAfterWindowControls + sidebarToggleWidth + DSSpacing.gap2
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

    /// Top-inset van breadcrumb + Share/Edit/Preview — centreert de 28pt-controls
    /// op de traffic-light-middellijn (zelfde hoogte als vensterknoppen + toggle).
    static var shellTopBarControlTopInset: CGFloat {
        windowControlsCenterFromTop - topBarRowHeight / 2
    }

    /// Totale overlay-hoogte van de editor-top-chrome (breadcrumb + controls).
    static var editorTopChromeBandHeight: CGFloat {
        shellTopBarControlTopInset + topBarRowHeight
    }

    /// Totale hoogte van de editor-top-chrome (gelijk aan traffic-light-rij).
    static var topBarBandHeight: CGFloat { windowControlsRowHeight }

    // MARK: - Paginakop (Home / Portraits)

    /// Top-inset van de paginatitel ("Home", "All portraits", mapnaam). Home
    /// had gap6 ín de scroll, de gallery gap8 in een vaste header — de titel
    /// versprong bij tabwissel. Beide schermen bouwen nu dezelfde vaste kop.
    static let pageTitleTopInset: CGFloat = DSSpacing.gap8

    /// Ruimte tussen de paginakop en de content eronder.
    static let pageTitleBottomInset: CGFloat = DSSpacing.gap6

    // MARK: - Portret-grid (UXS-9 / UX8)

    /// Kolommen in het portret-rooster. Home en de Portraits-gallery hadden
    /// eigen waarden (4 vs 3 kolommen, gap5 vs gap4), waardoor dezelfde kaart
    /// per scherm een andere maat kreeg.
    static let portraitGridColumnCount = 4
    static let portraitGridSpacing: CGFloat = DSSpacing.gap5

    /// Hoeveel portretten "Recent" toont vóór de rest naar Earlier zakt.
    static let recentSectionLimit = 6

    /// Hoe recent een portret moet zijn voor de Recent-sectie.
    static let recentSectionWindow: TimeInterval = 7 * 24 * 60 * 60

    // MARK: - Settings-takeover (UXS-26 / UX27)

    /// Top-inset van een Settings-pagina: onder de takeover-header door. Stond
    /// als kale `76` op vijf pagina's — vijf plekken die stilletjes uit elkaar
    /// konden lopen zodra de header verandert.
    static let settingsPageTopInset: CGFloat = 76

    // MARK: - Zwevende upload-pill (UXS-10 / UX9)

    /// Hoogte van de "Upload portrait ⌘U"-pil op Home.
    static let uploadPillHeight: CGFloat = 44

    /// Afstand van de pil tot de onderrand van het venster.
    static let uploadPillBottomInset: CGFloat = DSSpacing.gap5

    /// Bodem-inset die de scroll-content vrijhoudt van de zwevende pil, zodat de
    /// laatste kaartrij er volledig bovenuit te scrollen is. Afgeleid i.p.v. een
    /// magic number, plus `gap4` lucht zodat het label van de onderste rij niet
    /// tegen de pil-rand (incl. schaduw) plakt.
    static var uploadPillScrollInset: CGFloat {
        uploadPillHeight + uploadPillBottomInset + DSSpacing.gap4
    }
}
