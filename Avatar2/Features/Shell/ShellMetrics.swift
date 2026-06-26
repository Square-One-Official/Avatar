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

    /// Links-marge van de quota-teller. De OS-traffic-lights eindigen rond
    /// x67; we zetten de teller op ~88 zodat er duidelijke ademruimte ná de
    /// groene knop staat (feedback Thierry: 72 plakte tegen de knop → cramped).
    static let topBarLeadingAfterWindowControls: CGFloat = 88

    /// Hoogte van de band waarin de quota-teller verticaal centreert zodat
    /// hij op het hart van de traffic-lights valt. Empirisch bepaald: de
    /// traffic-light-middellijn zit op ~15,75 pt vanaf de venstertop, dus de
    /// band is 32 pt (midden ≈ 16 pt). 28 pt zette de teller ~2 pt te hoog
    /// (top-uitgelijnd i.p.v. gecentreerd → "touching the top", feedback Thierry).
    static let windowControlsRowHeight: CGFloat = 32

    /// Editor-topbar (breadcrumb + view-toggle + Share): control-hoogte.
    static let topBarRowHeight: CGFloat = 28

    /// Lucht tussen vensterrand en editor-topbar — gelijk aan trailing inset.
    static let topBarTopInset: CGFloat = topBarInset

    /// Totale hoogte van de top-chrome-band (inset + controls).
    static var topBarBandHeight: CGFloat { topBarTopInset + topBarRowHeight }
}
