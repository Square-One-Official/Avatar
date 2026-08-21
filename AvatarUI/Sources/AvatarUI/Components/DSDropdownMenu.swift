// Caret-loze dropdown-menu's (E24.12) — zwevende DS-kaart onder een anker.
// Gebruik dit i.p.v. `.popover(arrowEdge:)` wanneer de inhoud al `dsPanelSurface`
// of `DSContextMenuPanel` heeft; systeem-popovers voegen een pijltje + extra
// buitenrand toe rond ons paneel-oppervlak.

import SwiftUI

public enum DSDropdownPlacement: Sendable {
    case below
    case above
}

public extension View {
    /// Toont `menu` als caret-loze, zwevende kaart direct onder deze view.
    /// Sluit bij een tik buiten het anker+menu (via `dismissOverlay` op een
    /// voorouder) of wanneer `isPresented` false wordt gezet.
    func dsDropdownMenu<Menu: View>(
        isPresented: Binding<Bool>,
        anchorHeight: CGFloat = 32,
        gap: CGFloat = DSSpacing.gap2,
        placement: DSDropdownPlacement = .below,
        @ViewBuilder menu: @escaping () -> Menu
    ) -> some View {
        modifier(DSDropdownMenuModifier(
            isPresented: isPresented,
            anchorHeight: anchorHeight,
            gap: gap,
            placement: placement,
            menu: menu
        ))
    }

    /// Transparante vanglaag: tik ergens buiten een open dropdown sluit `isPresented`.
    /// Zet op een container (paneel, scroll-rij) die groter is dan het anker.
    func dsDropdownDismissOverlay(isPresented: Binding<Bool>) -> some View {
        modifier(DSDropdownDismissOverlay(isPresented: isPresented))
    }
}

private struct DSDropdownMenuModifier<Menu: View>: ViewModifier {
    @Binding var isPresented: Bool
    let anchorHeight: CGFloat
    let gap: CGFloat
    let placement: DSDropdownPlacement
    @ViewBuilder let menu: () -> Menu
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresented {
                    menu()
                        .fixedSize()
                        .offset(y: placement == .below ? anchorHeight + gap : 0)
                        .alignmentGuide(.top) { d in
                            placement == .above ? d[.bottom] + gap : d[.top]
                        }
                        .zIndex(10)
                        .transition(.dsScaleFade(
                            anchor: placement == .below ? .top : .bottom,
                            reduceMotion: reduceMotion
                        ))
                }
            }
            .zIndex(isPresented ? 10 : 0)
            .dsMotion(DSMotion.fast, value: isPresented)
    }
}

private struct DSDropdownDismissOverlay: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.background {
            if isPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isPresented = false }
            }
        }
    }
}

/// Knop + `DSContextMenuPanel` (8pt-radius). Vervangt native SwiftUI `Menu`,
/// dat de systeem-menuradius tekent i.p.v. onze DS-kaart.
public struct DSDropdownButton<Label: View, Menu: View>: View {
    @Binding private var isPresented: Bool
    private let anchorHeight: CGFloat
    private let minWidth: CGFloat
    private let placement: DSDropdownPlacement
    private let label: Label
    private let menu: Menu

    public init(
        isPresented: Binding<Bool>,
        anchorHeight: CGFloat = 32,
        minWidth: CGFloat = 160,
        placement: DSDropdownPlacement = .below,
        @ViewBuilder label: () -> Label,
        @ViewBuilder menu: () -> Menu
    ) {
        self._isPresented = isPresented
        self.anchorHeight = anchorHeight
        self.minWidth = minWidth
        self.placement = placement
        self.label = label()
        self.menu = menu()
    }

    public var body: some View {
        Button { isPresented.toggle() } label: {
            label
        }
        .buttonStyle(.plain)
        .dsDropdownMenu(
            isPresented: $isPresented,
            anchorHeight: anchorHeight,
            placement: placement
        ) {
            DSContextMenuPanel(minWidth: minWidth) { menu }
        }
    }
}
