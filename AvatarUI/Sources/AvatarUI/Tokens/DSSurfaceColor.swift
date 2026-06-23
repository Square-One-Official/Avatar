import SwiftUI

public extension DSColor {
    /// Gedeelde "neutral surface"-achtergrond voor ghost/fill-knoppen, icoon-
    /// knoppen en toolbar-pillen: pressed (of active) → `neutral-strongest`,
    /// hover → `neutral-stronger`, anders de rust-kleur (`base`, standaard helder).
    /// Eén bron voor de ladder die voorheen in ~6 ButtonStyles los stond.
    static func neutralSurface(pressed: Bool, hovering: Bool, base: Color = .clear) -> Color {
        if pressed { return Background.neutralStrongest }
        if hovering { return Background.neutralStronger }
        return base
    }
}
