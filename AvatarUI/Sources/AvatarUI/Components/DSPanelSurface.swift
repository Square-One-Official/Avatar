// Gedeeld paneel-/popover-oppervlak (E24.12). `dsPanelSurface` bevat de
// primitives voor zowel glas als solid; `dsMenuSurface` is de canonieke,
// massieve menu-/editpanelstijl zodat top- en bottom-menu's identiek ogen:
// donkere Card, dunne divider-rand, DS-radius en schaduw.

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

    /// Canonieke container voor zwevende editor-menu's en edit-panelen.
    ///
    /// Eén vaste, massieve Card-surface voorkomt dat Frame, Background en
    /// account/context-menu's visueel afwijken van Effects en Enhance. Houd
    /// glas alleen voor expliciete, geneste popovers zoals de color picker.
    func dsMenuSurface(cornerRadius: CGFloat = DSRadius.xl4) -> some View {
        dsPanelSurface(cornerRadius: cornerRadius, solid: true)
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
