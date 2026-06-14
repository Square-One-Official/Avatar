// Gedeelde paneel-/popover-oppervlak (E24.12). Eén DS-stijl voor ZOWEL de
// canvas-toolbar-dropdowns (caret-loos, custom float) ALS de bottom-panelen
// (DSEditPanel), zodat top en bottom identiek ogen: subtiel glas (in-window-
// blur + donkere card-tint), een dunne rand (divider) en de DS-radius +
// schaduw. Vervangt de inline-stijl die DSEditPanel had en die de systeem-
// `.popover` (mét pijltje) niet kon delen.

import SwiftUI

public extension View {
    /// Past het gedeelde paneel-oppervlak toe (glas + rand + radius + schaduw).
    /// `cornerRadius` schaalt mee met de kaartgrootte (groot paneel = xl4,
    /// compacte dropdown = xl).
    func dsPanelSurface(cornerRadius: CGFloat = DSRadius.xl4) -> some View {
        modifier(DSPanelSurface(cornerRadius: cornerRadius))
    }

    /// E24.12: subtiele verticale rand-fade op scrollbare paneelinhoud — de
    /// boven- en onderrand vervagen zacht zodat afgekapte inhoud niet hard
    /// afsnijdt maar "er is meer" communiceert. `fraction` = aandeel van de
    /// hoogte dat aan elke kant vervaagt.
    func dsEdgeFade(_ fraction: CGFloat = 0.06) -> some View {
        mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: fraction),
                    .init(color: .black, location: 1 - fraction),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }
}

private struct DSPanelSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    WithinWindowBlur(material: .hudWindow)
                    DSColor.Background.card.opacity(0.82)
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
