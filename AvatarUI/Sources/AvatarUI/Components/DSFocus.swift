// Focus-chrome voor custom DS-controls.
//
// macOS tekent standaard een lichtblauwe rechthoek rond elke focused view —
// óók na een muisklik. Figma heeft die ring niet; DS-chrome (selected pill,
// input-rand, hover) is de visuele staat. Keyboard-navigatie blijft werken
// via `.focusable()` / `@FocusState`; alleen het systeemeffect gaat uit.

import SwiftUI

public extension View {
    /// Verbergt de macOS-systeem-focusring. Muisklik mag die ring nooit
    /// tonen; pas dit toe op elke custom control die focus kan krijgen.
    func dsFocusEffectDisabled() -> some View {
        focusEffectDisabled()
    }

    /// Keyboard-focusabel zonder systeemring. Gebruik i.p.v. `.focusable()`
    /// op custom controls die ←/→ of andere key commands nodig hebben.
    func dsKeyboardFocusable(_ isFocusable: Bool = true) -> some View {
        focusable(isFocusable)
            .focusEffectDisabled()
    }
}
