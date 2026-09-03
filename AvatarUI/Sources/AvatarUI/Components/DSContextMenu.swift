// Zwevend DS-rechtermuis-menu (E24.22) — vervangt native `.contextMenu` op macOS.
// `DSMenuRow` + `DSContextMenuPanel` + overlay/scrim; submenu via `DSMenuSubmenu`
// (E57.1: eigen child window naast de rij, hover-intent + keyboard via
// `DSMenuTree`/`DSMenuLevel` in DSMenuNavigation.swift).
// Ankers zijn SwiftUI `.global`. Het menu zelf leeft in een child window
// (`DSFloatingWindowAnchor`), zodat het — net als een native NSMenu — over de
// vensterrand heen mag en altijd bovenop in-window content staat; de scrim
// blijft in-window en vangt de klik-buiten binnen het hostvenster.

import SwiftUI

// MARK: - Menu row

public struct DSMenuRow<Accessory: View>: View {
    private let title: String
    /// SF-symboolnaam óf een kant-en-klaar `Image` (bijv. een Phosphor-icoon uit
    /// een toolbar-item dat als menu-rij hergebruikt wordt).
    private let icon: Image
    private let destructive: Bool
    private let showsChevron: Bool
    private let shortcut: String?
    private let disabled: Bool
    private let accessory: Accessory
    private let action: () -> Void
    @State private var id = UUID()

    public init(
        _ title: String,
        icon: String,
        destructive: Bool = false,
        showsChevron: Bool = false,
        shortcut: String? = nil,
        disabled: Bool = false,
        @ViewBuilder accessory: () -> Accessory,
        action: @escaping () -> Void
    ) {
        self.init(
            title,
            icon: Image(systemName: icon),
            destructive: destructive,
            showsChevron: showsChevron,
            shortcut: shortcut,
            disabled: disabled,
            accessory: accessory,
            action: action
        )
    }

    /// UXS-4: variant voor call sites die het icoon al als `Image` hebben —
    /// de capsule-overflow hergebruikt zijn toolbar-iconen als menu-rijen.
    public init(
        _ title: String,
        icon: Image,
        destructive: Bool = false,
        showsChevron: Bool = false,
        shortcut: String? = nil,
        disabled: Bool = false,
        @ViewBuilder accessory: () -> Accessory,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.destructive = destructive
        self.showsChevron = showsChevron
        self.shortcut = shortcut
        self.disabled = disabled
        self.accessory = accessory()
        self.action = action
    }

    public var body: some View {
        DSMenuRowContent(
            id: id,
            title: title,
            icon: icon,
            destructive: destructive,
            showsChevron: showsChevron,
            shortcut: shortcut,
            disabled: disabled,
            isSubmenu: false,
            accessory: accessory,
            action: action
        )
    }
}

/// De rij zelf (gedeeld door `DSMenuRow` en `DSMenuSubmenu`). Binnen een
/// `DSMenuLevel` volgt de markering het niveau (hover én keyboard delen één
/// `focusedID`; een open submenu-rij blijft gemarkeerd); daarbuiten — in-window
/// dropdowns — is het de eigen hover, zoals voorheen.
struct DSMenuRowContent<Accessory: View>: View {
    let id: UUID
    let title: String
    let icon: Image
    let destructive: Bool
    let showsChevron: Bool
    let shortcut: String?
    let disabled: Bool
    let isSubmenu: Bool
    let accessory: Accessory
    let action: () -> Void

    @Environment(DSMenuLevel.self) private var level: DSMenuLevel?
    @State private var localHover = false
    @State private var actionBox = ActionBox()

    /// Het niveau bewaart één activatie-closure per rij (Return/Space); die
    /// wordt elke body-pass ververst zodat 'ie nooit een verouderde state
    /// vasthoudt (de rij-closures vangen de menu-struct van dat moment).
    @MainActor
    private final class ActionBox {
        var action: () -> Void = {}
        func update(_ action: @escaping () -> Void) { self.action = action }
    }

    private var highlighted: Bool {
        guard !disabled else { return false }
        if let level {
            return level.focusedID == id || (isSubmenu && level.openSubmenuID == id)
        }
        return localHover
    }

    var body: some View {
        let _ = actionBox.update(action)
        Button(action: action) {
            HStack(spacing: DSSpacing.gap2) {
                icon
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Text(title)
                    .dsTextStyle(.labelBase)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: (shortcut != nil || showsChevron) ? DSSpacing.gap4 : 0)
                if let shortcut {
                    Text(shortcut)
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .lineLimit(1)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DSColor.Foreground.muted)
                }
                accessory
                    .layoutPriority(1)
            }
            .foregroundStyle(destructive ? DSColor.Foreground.destructive : DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                DSColor.neutralSurface(pressed: false, hovering: highlighted),
                in: RoundedRectangle(cornerRadius: DSMenuLayout.rowRadius, style: .continuous)
            )
            .dsMotion(DSMotion.micro, value: highlighted)
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { hovering in
            localHover = hovering
            if hovering { level?.hoverEntered(id) } else { level?.hoverExited(id) }
        }
        .background {
            if let level {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.frame(in: .global), initial: true) { _, frame in
                            level.updateFrame(id, frame)
                        }
                }
            }
        }
        .onAppear {
            level?.register(id, isSubmenu: isSubmenu, isDisabled: disabled) { [actionBox] in
                actionBox.action()
            }
        }
        .onChange(of: disabled) { _, new in level?.setDisabled(id, new) }
        .onDisappear { level?.unregister(id) }
    }
}

extension DSMenuRow where Accessory == EmptyView {
    public init(
        _ title: String,
        icon: String,
        destructive: Bool = false,
        showsChevron: Bool = false,
        shortcut: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            title,
            icon: icon,
            destructive: destructive,
            showsChevron: showsChevron,
            shortcut: shortcut,
            disabled: disabled,
            accessory: { EmptyView() },
            action: action
        )
    }

    public init(
        _ title: String,
        icon: Image,
        destructive: Bool = false,
        showsChevron: Bool = false,
        shortcut: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            title,
            icon: icon,
            destructive: destructive,
            showsChevron: showsChevron,
            shortcut: shortcut,
            disabled: disabled,
            accessory: { EmptyView() },
            action: action
        )
    }
}

// MARK: - Panel

public struct DSContextMenuPanel<Content: View>: View {
    private let minWidth: CGFloat
    private let content: Content

    @Environment(DSMenuTree.self) private var tree: DSMenuTree?
    @Environment(DSMenuLevel.self) private var parentLevel: DSMenuLevel?

    public init(minWidth: CGFloat = 190, @ViewBuilder content: () -> Content) {
        self.minWidth = minWidth
        self.content = content()
    }

    public var body: some View {
        if let tree {
            // Rechtermuis-menu (`DSContextMenuOverlay`): dit paneel is een
            // niveau in de boom — het hoofdpaneel of een open submenu.
            DSMenuLevelHost(tree: tree, parent: parentLevel) { list }
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            content
        }
        .padding(DSMenuLayout.listInset)
        .frame(minWidth: minWidth, alignment: .leading)
        .dsMenuSurface()
        .accessibilityElement(children: .contain)
    }
}

private struct DSMenuLevelHost<Content: View>: View {
    let tree: DSMenuTree
    let content: Content
    @State private var level: DSMenuLevel

    init(tree: DSMenuTree, parent: DSMenuLevel?, @ViewBuilder content: () -> Content) {
        self.tree = tree
        self.content = content()
        _level = State(initialValue: DSMenuLevel(parent: parent))
    }

    var body: some View {
        content
            .environment(level)
            .onAppear {
                tree.attach(level)
                // Keyboard-open (→/Return op de trigger): eerste rij markeren
                // zodra de rijen hun frames gemeld hebben (volgende tick).
                if let parent = level.parent, parent.pendingChildFocus {
                    parent.pendingChildFocus = false
                    DispatchQueue.main.async { [level] in level.focusFirst() }
                }
            }
            .onDisappear { tree.detach(level) }
    }
}

// MARK: - Overlay-plaatsing (testbaar)

/// Ankers komen binnen in SwiftUI `.global`. De overlay rekent ze om naar
/// haar eigen lokale space, zodat een menu op ShellView-niveau naast de
/// klik landt — ook als de trigger in de sidebar of gallery zit.
enum DSContextMenuPlacement {
    static func localAnchor(_ anchor: CGRect, overlayGlobalOrigin: CGPoint) -> CGRect {
        CGRect(
            x: anchor.minX - overlayGlobalOrigin.x,
            y: anchor.minY - overlayGlobalOrigin.y,
            width: anchor.width,
            height: anchor.height
        )
    }

    static func offset(
        anchor: CGRect,
        menuSize: CGSize,
        in container: CGSize,
        padding: CGFloat = DSSpacing.gap2
    ) -> CGPoint {
        CGPoint(
            x: clamped(
                preferred: anchor.minX,
                padding: padding,
                container: container.width,
                menu: menuSize.width
            ),
            y: clamped(
                preferred: preferredY(anchor: anchor, padding: padding),
                padding: padding,
                container: container.height,
                menu: menuSize.height
            )
        )
    }

    /// Point-anchor (rechtermuis): op de klik. Rect-anchor: onder het element.
    static func preferredY(anchor: CGRect, padding: CGFloat) -> CGFloat {
        (anchor.height > 0 ? anchor.maxY : anchor.minY) + padding
    }

    /// Gewenste linkerbovenhoek van het menu (zelfde space als `anchor`);
    /// het klemmen gebeurt daarna op het scherm (DSFloatingLayout).
    static func preferredTopLeft(anchor: CGRect, padding: CGFloat = DSSpacing.gap2) -> CGPoint {
        CGPoint(x: anchor.minX, y: preferredY(anchor: anchor, padding: padding))
    }

    private static func clamped(
        preferred: CGFloat,
        padding: CGFloat,
        container: CGFloat,
        menu: CGFloat
    ) -> CGFloat {
        min(max(preferred, padding), max(padding, container - menu - padding))
    }
}

// MARK: - Overlay + scrim

/// Scrim in-window (klik-buiten binnen het hostvenster) + het menu in een
/// child window op het anker. Het menu wordt op z'n échte maat gemeten en
/// geklemd binnen `bounds` (default: het scherm, zoals een native NSMenu;
/// `.window` voor grote popover-achtige panelen). `menuWidth`/`menuHeight`
/// blijven in de signature voor bestaande call sites maar sturen de
/// plaatsing niet meer.
public struct DSContextMenuOverlay<Menu: View>: View {
    private let anchor: CGRect
    private let bounds: DSFloatingBounds
    private let kind: DSFloatingKind
    private let onDismiss: () -> Void
    private let menu: Menu

    /// E57.1: één boom per open menu — pijltjes/Return lopen via een lokale
    /// toetsen-monitor (de panels worden nooit key) naar het diepste open
    /// niveau; submenu's melden zich als kind-niveau.
    @State private var tree = DSMenuTree()
    @State private var keyMonitor = DSMenuKeyMonitor()

    /// `kind: .panel` voor een popover-achtig paneel dat een app-/venster-
    /// wissel overleeft en waarin tekstvelden werken (zie `DSFloatingMode`).
    public init(
        anchor: CGRect,
        bounds: DSFloatingBounds = .screen,
        kind: DSFloatingKind = .menu,
        onDismiss: @escaping () -> Void,
        menuWidth _: CGFloat = 220,
        menuHeight _: CGFloat = 260,
        @ViewBuilder menu: () -> Menu
    ) {
        self.anchor = anchor
        self.bounds = bounds
        self.kind = kind
        self.onDismiss = onDismiss
        self.menu = menu()
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            DSFloatingWindowAnchor(
                placement: .anchoredTopLeft(
                    DSContextMenuPlacement.preferredTopLeft(anchor: anchor),
                    bounds: bounds
                ),
                mode: DSFloatingMode(kind: kind, onDismiss: onDismiss),
                identity: anchor
            ) {
                menu.environment(tree)
            }
        }
        .onAppear { keyMonitor.install(tree: tree) }
        .onDisappear { keyMonitor.remove() }
    }
}

// MARK: - Rechtermuis-trigger (klik in SwiftUI `.global`)

public extension View {
    /// Roept `onTrigger` aan met de klikpositie in `.global` bij rechtsklik.
    /// `coordinateSpace` blijft in de signature zodat bestaande call sites
    /// compileren; ankers zijn altijd window-globaal zodat `DSContextMenuOverlay`
    /// ze overal kan plaatsen (shell-host én lokaal paneel).
    func contextMenuTrigger(
        in _: CoordinateSpace,
        onTrigger: @escaping (CGRect) -> Void
    ) -> some View {
        modifier(ContextMenuTriggerModifier(onTrigger: onTrigger))
    }
}

private struct ContextMenuTriggerModifier: ViewModifier {
    let onTrigger: (CGRect) -> Void
    @State private var bounds: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.frame(in: .global), initial: true) { _, new in
                            bounds = new
                        }
                }
            }
            .onRightClick { localPoint in
                let anchor = CGPoint(x: bounds.minX + localPoint.x, y: bounds.minY + localPoint.y)
                onTrigger(CGRect(origin: anchor, size: .zero))
            }
    }
}
