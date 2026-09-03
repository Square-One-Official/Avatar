// Gedeelde paneel-/popover-oppervlak (E24.12). Eén DS-stijl voor ZOWEL de
// canvas-toolbar-dropdowns (caret-loos, custom float) ALS de bottom-panelen
// (DSEditPanel), zodat top en bottom identiek ogen: subtiel glas (in-window-
// blur + donkere card-tint), een dunne rand (divider) en de DS-radius +
// schaduw. Gebruik `dsDropdownMenu` / overlay — niet `.popover(arrowEdge:)`
// — anders krijg je systeempijl + dubbele buitenrand.

import SwiftUI

/// Schaduw van `dsPanelSurface`/`dsMenuSurface`. Eén plek, zodat de
/// child-window-marge (`DSFloatingMode.menu`) 'm volledig kan omvatten —
/// een te krappe marge knipt de blur hard af tot een rechthoek.
public enum DSPanelShadow {
    public static let radius: CGFloat = 12
    public static let yOffset: CGFloat = 12
    public static let opacity: Double = 0.25
}

public enum DSMenuLayout {
    public static let cornerRadius = DSRadius.xl4
    public static let contentInset = DSSpacing.gap5 + DSSpacing.gap2
    public static let listInset = DSSpacing.gap2
    /// Hover-rij binnen `listInset`: concentrisch met de kaart (`outer − inset`).
    public static let rowRadius = DSRadius.concentric(inset: listInset, outer: cornerRadius)
}

public extension View {
    /// Past het gedeelde paneel-oppervlak toe (rand + radius + schaduw).
    /// `cornerRadius` schaalt mee met de kaartgrootte (groot paneel = xl4,
    /// compacte dropdown = xl).
    /// `solid`: true = massieve card-achtergrond (edit-panelen onderaan);
    /// false (default) = in-window blur + card-tint (toolbar-dropdowns).
    /// Clip/schaduw zitten op de fill, niet op de inhoud — dropdowns mogen
    /// over de kaart-rand vallen.
    func dsPanelSurface(cornerRadius: CGFloat = DSRadius.xl4, solid: Bool = false) -> some View {
        modifier(DSPanelSurface(cornerRadius: cornerRadius, solid: solid))
    }

    /// Canonieke container voor zwevende editor-menu's en edit-panelen.
    /// Zelfde massieve Card als Effects/Enhance (24pt radius), zodat Frame
    /// en Background niet als glas-dropdown afwijken.
    func dsMenuSurface() -> some View {
        dsPanelSurface(cornerRadius: DSMenuLayout.cornerRadius, solid: true)
    }
}

private struct DSPanelSurface: ViewModifier {
    let cornerRadius: CGFloat
    let solid: Bool
    @Environment(\.dsVectorExport) private var vectorExport

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // Clip en schaduw alléén op de fill — niet op `content`.
        // `.clipShape` + `.shadow` op de hele kaart maken een compositing-
        // laag die child-overlays afkapt; Enhance-dropdowns (breder dan hun
        // tegel) vielen daardoor over de paneelrand in plaats van eroverheen.
        content
            .background {
                Group {
                    if solid || vectorExport {
                        DSColor.Background.card
                    } else {
                        ZStack {
                            WithinWindowBlur(material: .hudWindow)
                            DSColor.Background.card.opacity(0.82)
                        }
                    }
                }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
                }
                .dsVectorSafeShadow(
                    color: .black.opacity(DSPanelShadow.opacity),
                    radius: DSPanelShadow.radius,
                    x: 0,
                    y: DSPanelShadow.yOffset
                )
            }
    }
}
