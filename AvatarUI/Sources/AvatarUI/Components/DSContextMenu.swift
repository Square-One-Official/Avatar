// Zwevend DS-rechtermuis-menu (E24.22) — vervangt native `.contextMenu` op macOS.
// `DSMenuRow` + `DSContextMenuPanel` + overlay/scrim; submenu via `DSMenuFlyout`.
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
                } else if showsChevron {
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
            .dsHoverHighlight(cornerRadius: DSMenuLayout.rowRadius)
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
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

    public init(minWidth: CGFloat = 190, @ViewBuilder content: () -> Content) {
        self.minWidth = minWidth
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            content
        }
        .padding(DSMenuLayout.listInset)
        .frame(minWidth: minWidth, alignment: .leading)
        .dsMenuSurface()
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
/// child window op het anker. Het menu wordt op z'n échte maat gemeten en op
/// het scherm geklemd; `menuWidth`/`menuHeight` blijven in de signature voor
/// bestaande call sites maar sturen de plaatsing niet meer.
public struct DSContextMenuOverlay<Menu: View>: View {
    private let anchor: CGRect
    private let onDismiss: () -> Void
    private let menu: Menu

    public init(
        anchor: CGRect,
        onDismiss: @escaping () -> Void,
        menuWidth _: CGFloat = 220,
        menuHeight _: CGFloat = 260,
        @ViewBuilder menu: () -> Menu
    ) {
        self.anchor = anchor
        self.onDismiss = onDismiss
        self.menu = menu()
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            DSFloatingWindowAnchor(
                placement: .anchoredTopLeft(DSContextMenuPlacement.preferredTopLeft(anchor: anchor)),
                mode: .menu(onDismiss: onDismiss),
                identity: anchor
            ) {
                menu
            }
        }
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
