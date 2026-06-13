// Gedeelde shell-maten (E05.8). Eén bron voor de marge t.o.v. de
// vensterrand — sidebar-kaart (E03.15), topbar-cluster en toekomstige
// randelementen rekenen met hetzelfde token i.p.v. losse getallen.

import AvatarUI
import CoreGraphics

enum ShellMetrics {
    /// Marge t.o.v. de vensterrand (E03.15: kaartradius rekent er
    /// concentrisch mee; E05.8: ook de topbar-trailing).
    static let windowEdgeInset: CGFloat = DSSpacing.gap1

    /// X-positie waar topbar-content links begint: de OS-window-controls
    /// bij hiddenTitleBar (~68 pt, vaste systeemmaat) + gap-2. Geen
    /// DS-token — de traffic lights zijn van macOS, niet van ons grid.
    static let topBarLeadingAfterWindowControls: CGFloat = 68 + DSSpacing.gap2
}
