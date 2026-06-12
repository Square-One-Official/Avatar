// Figma "Components" → Button, Type=Ghost, Color=Neutral (13:305). Zelfde
// maten als DSPrimaryButton; states volgen het ghostNeutral-gedrag van
// DSIconButton: default label muted zonder bg, hover bg neutral-stronger +
// label primary, pressed bg neutral-strongest + label primary, disabled via
// de opacityschaal.

import SwiftUI

public struct DSGhostButton: View {
    private let title: String
    private let icon: Image?
    private let size: DSPrimaryButton.Size
    private let fullWidth: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        icon: Image? = nil,
        size: DSPrimaryButton.Size = .default,
        fullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.size = size
        self.fullWidth = fullWidth
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: size.contentGap) {
                if let icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.iconSize, height: size.iconSize)
                }
                Text(title)
                    .dsTextStyle(size.textStyle)
                    .lineLimit(1)
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
        }
        .buttonStyle(GhostSurfaceStyle(size: size))
    }

    private struct GhostSurfaceStyle: ButtonStyle {
        let size: DSPrimaryButton.Size

        func makeBody(configuration: Configuration) -> some View {
            Surface(configuration: configuration)
        }

        private struct Surface: View {
            let configuration: ButtonStyle.Configuration
            @Environment(\.isEnabled) private var isEnabled
            @State private var isHovering = false

            var body: some View {
                configuration.label
                    .foregroundStyle(
                        isHovering || configuration.isPressed
                            ? DSColor.Foreground.primary
                            : DSColor.Foreground.muted
                    )
                    .background(backgroundColor, in: Capsule())
                    .opacity(isEnabled ? DSOpacity.strong : DSOpacity.disabled)
                    .onHover { isHovering = $0 }
                    .animation(.easeOut(duration: 0.1), value: isHovering)
            }

            private var backgroundColor: Color {
                if configuration.isPressed { return DSColor.Background.neutralStrongest }
                if isHovering { return DSColor.Background.neutralStronger }
                return .clear
            }
        }
    }
}
