// Shell-topbar (PoC left-nav herziening). Sterk uitgekleed: de credits-teller,
// de gear (Settings), de board- en de rechter-sidebar-toggle zijn weg — die
// leven nu in de left-nav. De sidebar-inklap-toggle zit in ShellSidebarChrome
// (ShellView) náást de traffic-lights, altijd op dezelfde vensterpositie.
// Wat hier overblijft:
//   • rechts de editor-chrome (view-toggle + Share), ALLEEN tijdens bewerken;
//   • een ✕ om de in-window Settings te sluiten.
//
// Compacte Granola-stijl rij: gelabelde segmented control (Edit · Preview)
// + gelabelde Share-pil (icoon links).

import AvatarUI
import SwiftUI

struct ShellTopBar: View {
    let isSettingsActive: Bool
    let onToggleSettings: () -> Void
    /// Editor-chrome toont ALLEEN tijdens het bewerken van een portret.
    var isEditing: Bool = false
    var canExport: Bool = false
    var onExport: () -> Void = {}
    /// E34.5: social-preview als tweede segment naast Edit.
    var canPreview: Bool = false
    var isPreviewActive: Bool = false
    var onPreviewActiveChange: (Bool) -> Void = { _ in }

    private static let controlHeight: CGFloat = 28

    var body: some View {
        toolCluster
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.18), value: isSettingsActive)
    }

    // Rechts: editor-chrome tijdens bewerken; ✕ in Settings-modus.
    private var toolCluster: some View {
        HStack(spacing: 0) {
            Spacer(minLength: DSSpacing.gap2)
            ZStack(alignment: .trailing) {
                HStack(spacing: DSSpacing.gap1_5) {
                    if isEditing && canPreview {
                        EditorViewModeToggle(
                            isPreview: isPreviewActive,
                            height: Self.controlHeight,
                            onChange: onPreviewActiveChange
                        )
                    }
                    if isEditing && canExport {
                        SharePillButton(height: Self.controlHeight, action: onExport)
                    }
                }
                .opacity(isSettingsActive ? 0 : 1)
                .allowsHitTesting(!isSettingsActive)

                DSCompactTopBarButton(
                    icon: "xmark",
                    label: "Close",
                    height: Self.controlHeight,
                    action: onToggleSettings
                )
                .opacity(isSettingsActive ? 1 : 0)
                .allowsHitTesting(isSettingsActive)
            }
            .padding(.trailing, ShellMetrics.topBarInset)
        }
        .frame(height: ShellMetrics.topBarRowHeight, alignment: .top)
    }
}

// MARK: - Editor view mode (Edit · Preview)

/// Gelabelde segmented control — icoon + tekst per segment (pencil · eye).
private struct EditorViewModeToggle: View {
    @Namespace private var selectionNamespace
    let isPreview: Bool
    let height: CGFloat
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment(icon: "pencil", label: "Edit", selected: !isPreview) {
                DSMotion.animate(DSMotion.springSmall) { onChange(false) }
            }
            segment(icon: "eye", label: "Preview", selected: isPreview) {
                DSMotion.animate(DSMotion.springSmall) { onChange(true) }
            }
        }
        .padding(DSSpacing.gap0_5)
        .background(DSColor.Background.neutral, in: Capsule())
        .dsMotion(DSMotion.springSmall, value: isPreview)
    }

    private func segment(icon: String, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap1) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .dsTextStyle(.labelSmall)
            }
            .foregroundStyle(selected ? DSColor.Foreground.primary : DSColor.Foreground.muted)
            .padding(.horizontal, DSSpacing.gap2_5)
            .frame(height: height)
            .background {
                if selected {
                    Capsule()
                        .fill(DSColor.Background.neutralStronger)
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Share pill (icon + label, high-contrast)

/// Gelabelde Share-knop — Granola-stijl: icoon links, tekst rechts, inverted
/// surface (wit op dark / donker op light) als primaire actie in de topbar.
private struct SharePillButton: View {
    let height: CGFloat
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap1_5) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                Text("Share")
                    .dsTextStyle(.labelSmall)
            }
            .foregroundStyle(DSColor.Background.app)
            .padding(.horizontal, DSSpacing.gap3)
            .frame(height: height)
            .background(shareSurface, in: Capsule())
            .scaleEffect(pressed ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pressEvents(onPress: { pressed = true }, onRelease: { pressed = false })
        .animation(DSMotion.micro, value: hovering)
        .animation(DSMotion.micro, value: pressed)
        .accessibilityLabel("Share")
    }

    private var shareSurface: Color {
        if pressed { return DSColor.Foreground.subtle }
        if hovering { return DSColor.Foreground.subtle.opacity(0.92) }
        return DSColor.Foreground.primary
    }
}

// MARK: - Compact icon button (Settings close)

private struct DSCompactTopBarButton: View {
    let icon: String
    let label: String
    let height: CGFloat
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DSColor.Foreground.primary)
                .frame(width: height, height: height)
                .background(
                    DSColor.neutralSurface(pressed: pressed, hovering: hovering,
                                           base: DSColor.Background.neutral),
                    in: Capsule()
                )
                .scaleEffect(pressed ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pressEvents(onPress: { pressed = true }, onRelease: { pressed = false })
        .animation(DSMotion.micro, value: hovering)
        .animation(DSMotion.micro, value: pressed)
        .accessibilityLabel(label)
    }
}

private extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded { _ in onRelease() }
        )
    }
}
