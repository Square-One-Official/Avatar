// Gedeelde paneel-/popover-oppervlak (E24.12). Eén DS-stijl voor ZOWEL de
// canvas-toolbar-dropdowns (caret-loos, custom float) ALS de bottom-panelen
// (DSEditPanel), zodat top en bottom identiek ogen: subtiel glas (in-window-
// blur + donkere card-tint), een dunne rand (divider) en de DS-radius +
// schaduw. Gebruik `dsDropdownMenu` / overlay — niet `.popover(arrowEdge:)`
// — anders krijg je systeempijl + dubbele buitenrand.

import SwiftUI

public extension View {
    /// Past het gedeelde paneel-oppervlak toe (rand + radius + schaduw).
    /// `cornerRadius` schaalt mee met de kaartgrootte (groot paneel = xl4,
    /// compacte dropdown = xl).
    /// `solid`: true = massieve card-achtergrond (edit-panelen onderaan);
    /// false (default) = in-window blur + card-tint (toolbar-dropdowns).
    func dsPanelSurface(cornerRadius: CGFloat = DSRadius.xl4, solid: Bool = false) -> some View {
        modifier(DSPanelSurface(cornerRadius: cornerRadius, solid: solid))
    }
}

private struct DSPanelSurface: ViewModifier {
    let cornerRadius: CGFloat
    let solid: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if solid {
                    DSColor.Background.card
                } else {
                    ZStack {
                        WithinWindowBlur(material: .hudWindow)
                        DSColor.Background.card.opacity(0.82)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
            }
            .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 12)
    }
}
