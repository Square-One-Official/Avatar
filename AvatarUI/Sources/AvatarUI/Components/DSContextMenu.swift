// Zwevend DS-rechtermuis-menu (E24.22) — vervangt native `.contextMenu` op macOS.
// `DSMenuRow` + `DSContextMenuPanel` + overlay/scrim; submenu via `DSMenuFlyout`.

import SwiftUI

// MARK: - Menu row

public struct DSMenuRow: View {
    private let title: String
    private let icon: String
    private let destructive: Bool
    private let showsChevron: Bool
    private let shortcut: String?
    private let disabled: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        icon: String,
        destructive: Bool = false,
        showsChevron: Bool = false,
        shortcut: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.destructive = destructive
        self.showsChevron = showsChevron
        self.shortcut = shortcut
        self.disabled = disabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap2) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Text(title).dsTextStyle(.labelBase)
                Spacer(minLength: DSSpacing.gap4)
                if let shortcut {
                    Text(shortcut)
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                } else if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DSColor.Foreground.muted)
                }
            }
            .foregroundStyle(destructive ? DSColor.Foreground.destructive : DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .dsHoverHighlight(cornerRadius: DSRadius.md)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
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
        .padding(DSSpacing.gap1)
        .frame(minWidth: minWidth, alignment: .leading)
        .dsPanelSurface(cornerRadius: DSRadius.lg)
    }
}

// MARK: - Overlay + scrim

public struct DSContextMenuOverlay<Menu: View>: View {
    private let anchor: CGRect
    private let onDismiss: () -> Void
    private let menu: Menu

    public init(
        anchor: CGRect,
        onDismiss: @escaping () -> Void,
        @ViewBuilder menu: () -> Menu
    ) {
        self.anchor = anchor
        self.onDismiss = onDismiss
        self.menu = menu()
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
                menu
                    .fixedSize()
                    .offset(x: clampedX(in: geo.size), y: clampedY(in: geo.size))
            }
        }
    }

    private func clampedX(in size: CGSize, menuWidth: CGFloat = 220) -> CGFloat {
        let pad = DSSpacing.gap2
        return min(max(anchor.minX, pad), max(pad, size.width - menuWidth - pad))
    }

    private func clampedY(in size: CGSize, menuHeight: CGFloat = 260) -> CGFloat {
        let pad = DSSpacing.gap2
        // Point-anchor (rechtermuis): open net onder de klik. Rect-anchor: onder het element.
        let baseY = anchor.height > 0 ? anchor.maxY : anchor.minY
        return min(max(baseY + pad, pad), max(pad, size.height - menuHeight - pad))
    }
}

// MARK: - Rechtermuis-trigger (frame in named coordinate space)

public extension View {
    /// Roept `onTrigger` aan met de view-bounds in `coordinateSpace` bij rechtsklik.
    func contextMenuTrigger(
        in coordinateSpace: CoordinateSpace,
        onTrigger: @escaping (CGRect) -> Void
    ) -> some View {
        modifier(ContextMenuTriggerModifier(coordinateSpace: coordinateSpace, onTrigger: onTrigger))
    }
}

private struct ContextMenuTriggerModifier: ViewModifier {
    let coordinateSpace: CoordinateSpace
    let onTrigger: (CGRect) -> Void
    @State private var bounds: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.frame(in: coordinateSpace), initial: true) { _, new in
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
