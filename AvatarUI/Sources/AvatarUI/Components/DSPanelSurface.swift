// Gedeeld paneel-/popover-oppervlak (E24.12). `dsPanelSurface` bevat de
// primitives voor zowel glas als solid; `dsMenuSurface` is de canonieke,
// massieve menu-/editpanelstijl zodat top- en bottom-menu's identiek ogen:
// donkere Card, dunne divider-rand, DS-radius en schaduw.

import SwiftUI

/// Eén expliciet layoutcontract voor alle custom menucontainers.
///
/// `contentInset` hoort bij panel/dropdown-inhoud; compacte lijstmenu's houden
/// dezelfde chrome maar gebruiken `listInset` zodat 32-pt menu-rijen niet door
/// overmatige witruimte worden verdrongen.
public enum DSMenuLayout {
    public static let cornerRadius = DSRadius.xl4
    public static let contentInset = DSSpacing.gap5 + DSSpacing.gap2
    public static let listInset = DSSpacing.gap2
}

public extension View {
    /// Low-level surface-primitive voor uitzonderingen buiten het custom
    /// menucontract. Primaire menu's gebruiken `dsMenuSurface()`.
    /// `solid`: true (default) = de canonieke massieve Card van Effects/Enhance;
    /// false = opt-in in-window blur voor geneste, materiaalachtige popovers.
    func dsPanelSurface(cornerRadius: CGFloat = DSRadius.xl4, solid: Bool = true) -> some View {
        modifier(DSPanelSurface(cornerRadius: cornerRadius, solid: solid))
    }

    /// Canonieke container voor zwevende editor-menu's en edit-panelen.
    ///
    /// Eén vaste, massieve Card-surface voorkomt dat Frame, Background en
    /// account/context-menu's visueel afwijken van Effects en Enhance.
    /// De radius is bewust niet configureerbaar: custom menu's delen altijd
    /// hetzelfde 24-pt containerprofiel.
    func dsMenuSurface() -> some View {
        dsPanelSurface(cornerRadius: DSMenuLayout.cornerRadius, solid: true)
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
