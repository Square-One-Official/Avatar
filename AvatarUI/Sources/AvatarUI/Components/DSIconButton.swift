// Figma "Components" → Icon-Only Button (circulair).
// Default: 40×40 (padding gap-2.5, icon 20) · Small: 24×24 (padding gap-1,
// icon 16). Stijlen 1-op-1 uit Figma:
// - fillBrand: bg background/action, icon on-action; states via opacity
//   (hover Medium .75, pressed Subtle .5, disabled Disabled .25).
// - ghostNeutral: opacity blijft Strong; default icon muted zonder bg,
//   hover bg neutral-stronger + icon primary, pressed/active bg
//   neutral-strongest + icon primary.

import SwiftUI

public struct DSIconButton: View {
    public enum Style: Sendable {
        case fillBrand
        case ghostNeutral
    }

    public enum Size: Sendable {
        case `default`
        case small

        var padding: CGFloat { self == .default ? DSSpacing.gap2_5 : DSSpacing.gap1 }
        var iconSize: CGFloat { self == .default ? 20 : 16 }
    }

    private let icon: Image
    private let label: String
    private let style: Style
    private let size: Size
    private let isActive: Bool
    private let action: () -> Void

    /// UXS-7: `label` is verplicht (geen default) — een icoon-knop zonder
    /// AX-naam bestaat niet voor VoiceOver. Het label voedt zowel
    /// `accessibilityLabel` als de `.help`-tooltip.
    public init(
        _ icon: Image,
        label: String,
        style: Style = .ghostNeutral,
        size: Size = .default,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.style = style
        self.size = size
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: size.iconSize, height: size.iconSize)
        }
        .buttonStyle(SurfaceStyle(style: style, size: size, isActive: isActive))
        .dsFocusEffectDisabled()
        .accessibilityLabel(label)
        .help(label)
    }

    private struct SurfaceStyle: ButtonStyle {
        let style: Style
        let size: Size
        let isActive: Bool

        func makeBody(configuration: Configuration) -> some View {
            Surface(style: style, size: size, isActive: isActive, configuration: configuration)
        }
    }

    private struct Surface: View {
        let style: Style
        let size: Size
        let isActive: Bool
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(foregroundColor)
                .padding(size.padding)
                .background(backgroundColor, in: Circle())
                .opacity(currentOpacity)
                .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
                .onHover { isHovering = $0 }
                .dsMotion(DSMotion.micro, value: isHovering)
                .dsMotion(DSMotion.micro, value: configuration.isPressed)
        }

        private var isHighlighted: Bool {
            isActive || isHovering || configuration.isPressed
        }

        private var foregroundColor: Color {
            switch style {
            case .fillBrand:
                return DSColor.Action.onAction
            case .ghostNeutral:
                return isHighlighted ? DSColor.Foreground.primary : DSColor.Foreground.muted
            }
        }

        private var backgroundColor: Color {
            switch style {
            case .fillBrand:
                return DSColor.Background.action
            case .ghostNeutral:
                return DSColor.neutralSurface(
                    pressed: isActive || configuration.isPressed, hovering: isHovering
                )
            }
        }

        private var currentOpacity: Double {
            if !isEnabled { return DSOpacity.disabled }
            switch style {
            case .fillBrand:
                if configuration.isPressed { return DSOpacity.subtle }
                if isHovering { return DSOpacity.medium }
                return DSOpacity.strong
            case .ghostNeutral:
                return DSOpacity.strong
            }
        }
    }
}
