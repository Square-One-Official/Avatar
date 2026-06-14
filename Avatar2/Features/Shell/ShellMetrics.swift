// Gedeelde shell-maten (E05.8). Eén bron voor de marge t.o.v. de
// vensterrand — sidebar-kaart (E03.15), topbar-cluster en toekomstige
// randelementen rekenen met hetzelfde token i.p.v. losse getallen.

import AvatarUI
import CoreGraphics

enum ShellMetrics {
    /// Marge t.o.v. de vensterrand (E03.15: kaartradius rekent er
    /// concentrisch mee; sidebar-kaart).
    static let windowEdgeInset: CGFloat = DSSpacing.gap1

    /// E18.6: gedeelde topbar-inset, gelijk aan de redo-knop rechtsonder
    /// (gap-3). Gear-trailing gebruikt deze; de counter zit dezelfde afstand
    /// ná de OS-window-controls, zodat alles "gap-3 van de dichtstbijzijnde
    /// chrome" zit.
    static let topBarInset: CGFloat = DSSpacing.gap3

    /// X-positie waar topbar-content links begint: de OS-window-controls
    /// bij hiddenTitleBar (~60 pt) + de gedeelde topbar-inset. De traffic
    /// lights zijn van macOS, dus links kan niet helemaal tegen de rand.
    static let topBarLeadingAfterWindowControls: CGFloat = 60 + topBarInset
}
