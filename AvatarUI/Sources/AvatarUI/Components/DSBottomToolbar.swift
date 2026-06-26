// Figma "Stories" → App / Hair (4114:903) → floatingToolbar (4114:978).
// E31.1: de onderste toolbar is een zwevende **capsule** (Card-fill, r-full)
// met gelabelde icoon+label-pillen + een overflow `⋯`-icoonknop. Geverifieerd
// op de render (variabelen via get_variable_defs): container = background/Card
// (#1c1917), pil = background/neutral (wit@5%), label = UI/Labels/Base
// (SF Pro Semibold 14.2), gap-2 (8) tussen pillen én als padding, knophoogte 40,
// capsule r-full (96). Active = lime (E03.3-gedrag).
//
// Undo/redo/compare (E06.6-accessoires) staan in de Figma-capsule-frame NIET; ze
// blijven als losse cirkels (DSToolButton) **náást** de Card-capsule in dezelfde
// strip — Figma-TODO: definitieve plaatsing zodra er een referentie is.

import SwiftUI

/// E32: gedeelde maatvariant voor de capsule-toolbar + pillen. `.regular` is de
/// onderste toolbar (Figma floatingToolbar); `.compact` is de bovenste canvas-
/// toolbar (Frame/Background/grid) — exact dezelfde componenten, kleinere maten.
public enum DSToolbarSize: Sendable {
    case regular
    case compact
    /// Naast de FigJam-naam-chip (28pt) — losse pillen, geen outer capsule.
    case chip

    /// Pil-hoogte (knop).
    public var height: CGFloat {
        switch self {
        case .regular: 40
        case .compact: 32
        case .chip: 28
        }
    }
    /// Icoongrootte: SF Symbol `.font`-punt én Phosphor frame-zijde.
    public var iconPointSize: CGFloat {
        switch self {
        case .regular: 18
        case .compact: 15
        case .chip: 14
        }
    }
    /// Labelstijl in de pil.
    public var textStyle: DSTextStyle {
        switch self {
        case .regular: .labelBase
        case .compact, .chip: .labelSmall
        }
    }
    /// Horizontale padding binnen de pil.
    public var horizontalPadding: CGFloat {
        switch self {
        case .regular: DSSpacing.gap3
        case .compact: DSSpacing.gap2
        case .chip: DSSpacing.gap3
        }
    }
    /// Ruimte tussen icoon/label/chevron én tussen pillen onderling.
    public var itemSpacing: CGFloat {
        switch self {
        case .regular: DSSpacing.gap2
        case .compact, .chip: DSSpacing.gap1
        }
    }
    /// Inset van de capsule rondom de pillen.
    public var containerPadding: CGFloat {
        switch self {
        case .regular: DSSpacing.gap2
        case .compact: DSSpacing.gap1
        case .chip: 0
        }
    }
    /// Schaal op pressed (identiek voor beide maten).
    public var pressScale: CGFloat { 0.97 }
}

public extension View {
    /// E32: solide Card-fill capsule met maat-afhankelijke inset (geen rand).
    /// Vervangt de inline-achtergrond van zowel de onderste toolbar als de
    /// bovenste canvas-toolbar zodat beide identiek ogen.
    func dsToolbarCapsule(size: DSToolbarSize = .regular) -> some View {
        padding(size.containerPadding)
            .background(DSColor.Background.card, in: Capsule())
    }
}

/// E32: wikkelt een SF Symbol-`Image` in de juiste `.font`-grootte zodat de
/// SF-pijler door dezelfde generieke pil loopt als de Phosphor-iconen.
/// Underscore-prefix: niet rechtstreeks aanroepen — gebruik de convenience-init.
public struct _DSFontSizedIcon: View {
    let image: Image
    let pointSize: CGFloat
    public var body: some View {
        image.font(.system(size: pointSize, weight: .medium))
    }
}

public struct DSToolbarItem<ID: Hashable>: Identifiable {
    public let id: ID
    public let icon: Image
    public let label: String

    public init(id: ID, icon: Image, label: String) {
        self.id = id
        self.icon = icon
        self.label = label
    }
}

/// Een losse actie in de capsule-overflow (`⋯`) — geen eigen paneel/tool, maar
/// een directe handeling (bijv. "Restore to original"). Verschijnt in hetzelfde
/// `⋯`-menu als de overflow-tools.
public struct DSToolbarAction: Identifiable {
    public let id: String
    public let icon: Image
    public let label: String
    public let action: () -> Void

    public init(id: String, icon: Image, label: String, action: @escaping () -> Void) {
        self.id = id
        self.icon = icon
        self.label = label
        self.action = action
    }
}

public struct DSBottomToolbar<ID: Hashable, Accessory: View>: View {
    private let items: [DSToolbarItem<ID>]
    private let overflow: [DSToolbarItem<ID>]
    private let overflowActions: [DSToolbarAction]
    @Binding private var selection: ID?
    // E-fix: de feature-pillen zijn uit te schakelen (en te dimmen) terwijl er
    // niets is om op te werken — bv. tijdens een vervangende import waarin de
    // cutout nog rekent. De accessoire-strip (undo/redo/compare) blijft actief.
    private let toolsEnabled: Bool
    private let accessory: Accessory

    public init(
        items: [DSToolbarItem<ID>],
        selection: Binding<ID?>,
        overflow: [DSToolbarItem<ID>] = [],
        overflowActions: [DSToolbarAction] = [],
        toolsEnabled: Bool = true,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.items = items
        self.overflow = overflow
        self.overflowActions = overflowActions
        self._selection = selection
        self.toolsEnabled = toolsEnabled
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: DSSpacing.gap2) {
            // De Figma-capsule: Card-fill r-full rondom de pillen + overflow.
            HStack(spacing: DSSpacing.gap2) {
                ForEach(items) { item in
                    DSCapsuleToolButton(
                        item.icon,
                        label: item.label,
                        isActive: selection == item.id,
                        action: { selection = selection == item.id ? nil : item.id }
                    )
                }
                if !overflow.isEmpty || !overflowActions.isEmpty {
                    DSToolbarOverflowButton(items: overflow, actions: overflowActions, selection: $selection)
                }
            }
            .dsToolbarCapsule(size: .regular)
            // E-fix: alléén de feature-pillen dimmen/uitschakelen (de capsule);
            // de press-/hover-stijl van de pillen heeft geen eigen disabled-look,
            // dus de opacity maakt de inerte staat zichtbaar. easeOut zodat het
            // re-enablen bij `.result` zacht terugkomt i.p.v. te poppen.
            .disabled(!toolsEnabled)
            .opacity(toolsEnabled ? DSOpacity.strong : DSOpacity.disabled)
            .animation(DSMotion.base, value: toolsEnabled)

            // Accessoires (undo/redo/compare) blijven buiten de Card-capsule.
            accessory
        }
    }
}

// Bestaande call sites (alleen tools, geen accessoires) blijven werken via een
// EmptyView-accessory; geen verplichte trailing closure.
extension DSBottomToolbar where Accessory == EmptyView {
    public init(
        items: [DSToolbarItem<ID>],
        selection: Binding<ID?>,
        overflow: [DSToolbarItem<ID>] = [],
        overflowActions: [DSToolbarAction] = [],
        toolsEnabled: Bool = true
    ) {
        self.init(
            items: items, selection: selection,
            overflow: overflow, overflowActions: overflowActions,
            toolsEnabled: toolsEnabled,
            accessory: { EmptyView() }
        )
    }
}

/// Rust-oppervlak van een capsule-toolbar-knop. `.ghost` = transparant tot hover
/// (onderste/bovenste toolbar). `.secondary` = DS fill in rust (zelfde card-vulling
/// als de FigJam-naam-chip) — voor losse header-row pillen naast de chip.
public enum CapsuleToolSurface {
    case ghost
    case secondary
}

/// E31.1 + E32: gelabelde capsule-pil (icoon + optioneel label + optionele
/// chevron) uit `floatingToolbar` (4114:978). Gedeeld door de onderste toolbar
/// (`.regular`) én de bovenste canvas-toolbar (`.compact`) — generiek over de
/// icoon-view zodat zowel SF Symbols (via `.font`, convenience-init) als Phosphor
/// (via frame, generieke init) erin passen. De chevron is altijd een SF
/// `chevron.down` (structurele affordance, géén "menu-icoon").
/// Active = lime icoon+label + lime ring (E03.3). **Besluit Thierry (2026-06-22):**
/// de pil-fill is transparant in rust en verschijnt pas op hover (neutral-stronger)
/// of bij active/pressed (neutral-strongest). Wijkt bewust af van Figma.
public struct DSCapsuleToolButton<Icon: View>: View {
    private let icon: Icon
    private let label: String?
    private let showChevron: Bool
    private let isActive: Bool
    private let size: DSToolbarSize
    private let surface: CapsuleToolSurface
    private let action: () -> Void

    /// Generieke init: de caller levert een kant-en-klare icoon-view (Phosphor-pad).
    public init(
        label: String? = nil,
        showChevron: Bool = false,
        isActive: Bool = false,
        size: DSToolbarSize = .regular,
        surface: CapsuleToolSurface = .ghost,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.label = label
        self.showChevron = showChevron
        self.isActive = isActive
        self.size = size
        self.surface = surface
        self.action = action
        self.icon = icon()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: size.itemSpacing) {
                icon
                if let label {
                    Text(label)
                        .dsTextStyle(size.textStyle)
                        // Een toolbar-pil-label mag nooit wrappen; zonder dit perst
                        // een krappe parent-HStack langere labels naar twee regels.
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                if showChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .padding(.horizontal, size.horizontalPadding)
            .frame(height: size.height)
        }
        .buttonStyle(CapsuleSurfaceStyle(isActive: isActive, surface: surface, pressScale: size.pressScale))
        .accessibilityLabel(Text(label ?? ""))
    }
}

/// E31.1: SF Symbol-convenience — behoudt de `.font`-grootte en de bestaande
/// call-shape `DSCapsuleToolButton(item.icon, label: …)`.
public extension DSCapsuleToolButton where Icon == _DSFontSizedIcon {
    init(
        _ image: Image,
        label: String? = nil,
        showChevron: Bool = false,
        isActive: Bool = false,
        size: DSToolbarSize = .regular,
        surface: CapsuleToolSurface = .ghost,
        action: @escaping () -> Void
    ) {
        self.init(
            label: label, showChevron: showChevron, isActive: isActive,
            size: size, surface: surface, action: action
        ) {
            _DSFontSizedIcon(image: image, pointSize: size.iconPointSize)
        }
    }
}

/// Hover/press/active-surface voor de capsule-pil — zelfde opzet als `ToolSurface`
/// in `DSToolButton`: ghost in rust, fill op hover/active.
public struct CapsuleSurfaceStyle: ButtonStyle {
    let isActive: Bool
    var surface: CapsuleToolSurface = .ghost
    let pressScale: CGFloat

    public init(isActive: Bool, surface: CapsuleToolSurface = .ghost, pressScale: CGFloat = 0.97) {
        self.isActive = isActive
        self.surface = surface
        self.pressScale = pressScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        CapsuleSurface(isActive: isActive, surface: surface, pressScale: pressScale, configuration: configuration)
    }

    private struct CapsuleSurface: View {
        let isActive: Bool
        let surface: CapsuleToolSurface
        let pressScale: CGFloat
        let configuration: ButtonStyle.Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(isActive ? DSColor.Action.primaryForeground : DSColor.Foreground.primary)
                .background(backgroundColor, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(DSColor.Action.primaryForeground, lineWidth: DSBorderWidth.medium)
                        .opacity(isActive ? DSOpacity.strong : DSOpacity.hidden)
                }
                .scaleEffect(configuration.isPressed ? pressScale : 1.0)
                .onHover { isHovering = $0 }
                .animation(DSMotion.fast, value: isActive)
                .animation(DSMotion.micro, value: isHovering)
                .animation(DSMotion.micro, value: configuration.isPressed)
        }

        private var backgroundColor: Color {
            DSColor.neutralSurface(
                pressed: isActive || configuration.isPressed,
                hovering: isHovering,
                base: surface == .secondary ? DSColor.Background.card : .clear
            )
        }
    }
}

/// E31.1: overflow `⋯`-icoonknop (Icon-Only Button 4114:983, 40×40) die de
/// secundaire tools in een menu toont. Vertikale dots conform de Figma-render.
/// Besluit Thierry (2026-06-22): fill transparant in rust, verschijnt op hover
/// (neutral-stronger) / pressed (neutral-strongest), identiek aan de pillen.
///
/// E-fix (2026-06-24): `.onHover` op een `Menu` vuurt niet op macOS — de
/// menu-tracking slokt de hover-events op, dus de reveal verscheen nooit ("geen
/// hover-state"). We renderen het menu nu áls knop (`.menuStyle(.button)`) en
/// laten de surface via een echte `ButtonStyle` lopen — net als `DSIconButton`
/// en `DSCapsuleToolButton`. Hover én pressed komen daarmee uit de knop zelf
/// (betrouwbaar) i.p.v. uit de menu-wrapper.
struct DSToolbarOverflowButton<ID: Hashable>: View {
    let items: [DSToolbarItem<ID>]
    var actions: [DSToolbarAction] = []
    @Binding var selection: ID?

    // De `⋯` hangt in de onderste (`.regular`) capsule → deel exact die maat
    // (icoon-punt + knophoogte) zodat 'm naast de pillen consistent oogt.
    private let size: DSToolbarSize = .regular

    var body: some View {
        Menu {
            ForEach(items) { item in
                Button { selection = item.id } label: {
                    Label { Text(item.label) } icon: { item.icon }
                }
            }
            if !items.isEmpty && !actions.isEmpty { Divider() }
            ForEach(actions) { action in
                Button { action.action() } label: {
                    Label { Text(action.label) } icon: { action.icon }
                }
            }
        } label: {
            // Icoon = `iconPointSize`/medium (gelijk aan de pil-iconen); knop =
            // vierkant op pil-hoogte → icon-only cirkel. De surface (fill/hover/
            // pressed/scale) komt uit DSToolbarOverflowButtonStyle.
            Image(systemName: "ellipsis")
                .font(.system(size: size.iconPointSize, weight: .medium))
                .rotationEffect(.degrees(90))
                .frame(width: size.height, height: size.height)
        }
        .menuStyle(.button)
        .buttonStyle(DSToolbarOverflowButtonStyle(size: size))
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("More tools"))
    }
}

/// Ghost icon-button-surface voor de `⋯`-overflow: transparant in rust,
/// neutral-stronger op hover, neutral-strongest pressed — in een Circle, exact
/// de ghost-look van `DSIconButton`/de capsule-pillen. Gedreven door een
/// `ButtonStyle` zodat hij óók als `Menu`-knop (`.menuStyle(.button)`) werkt.
struct DSToolbarOverflowButtonStyle: ButtonStyle {
    let size: DSToolbarSize

    func makeBody(configuration: Configuration) -> some View {
        Surface(size: size, configuration: configuration)
    }

    private struct Surface: View {
        let size: DSToolbarSize
        let configuration: ButtonStyle.Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(DSColor.Foreground.primary)
                .background(
                    DSColor.neutralSurface(pressed: configuration.isPressed, hovering: isHovering),
                    in: Circle()
                )
                .scaleEffect(configuration.isPressed ? size.pressScale : 1.0)
                .contentShape(Circle())
                .onHover { isHovering = $0 }
                .animation(DSMotion.micro, value: isHovering)
                .animation(DSMotion.micro, value: configuration.isPressed)
        }
    }
}
