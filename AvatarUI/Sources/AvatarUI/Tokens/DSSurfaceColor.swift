import SwiftUI

public extension DSColor {
    /// Gedeelde "neutral surface"-achtergrond voor ghost/fill-knoppen, icoon-
    /// knoppen en toolbar-pillen. Eén bron voor de ladder die voorheen in
    /// ~6 ButtonStyles los stond.
    ///
    /// UXS-27: de ladder is RELATIEF aan de rustkleur. Bij een heldere base
    /// (ghost) blijft het klassieke gedrag: hover → `neutral-stronger`,
    /// pressed → `neutral-strongest`. Bij een gevúlde base (chips die op
    /// `neutral`/`neutral-stronger` rusten, zoals de canvas-topchips) schuift
    /// alles één trede op — anders is de hoverkleur identiek aan de rustkleur
    /// en bestaat de hover alleen in code (UX36): hover → `neutral-strongest`,
    /// pressed/active → `neutral-strongest-2`.
    static func neutralSurface(pressed: Bool, hovering: Bool, base: Color = .clear) -> Color {
        let filled = base != .clear
        if pressed { return filled ? Background.neutralStrongest2 : Background.neutralStrongest }
        if hovering { return filled ? Background.neutralStrongest : Background.neutralStronger }
        return base
    }
}
