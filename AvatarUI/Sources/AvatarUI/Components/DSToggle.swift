// Figma "Components" → Toggle (61:944), zoals gebruikt in Onboarding /
// Permissions (online-modellen) en Settings. Track 48×24 (r-full): uit =
// background/neutral → neutral-stronger (hover) → neutral-strongest
// (pressed); aan = background/action in alle staten. Thumb 22 (gap-px
// inzet): foreground/default/thumb (uit) resp. on-action (aan). Hover
// schuift de thumb 2pt naar binnen (inzet 3); in de pressed-frames staat
// de thumb al aan de doelzijde — pressed toont dus de bestemming. Figma
// kent geen disabled-variant: disabled volgt de Figma-opacityschaal.

import SwiftUI

public struct DSToggle: View {
    @Binding private var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    public init(isOn: Binding<Bool>) {
        self._isOn = isOn
    }

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            EmptyView()
        }
        .buttonStyle(DSToggleTrackStyle(isOn: isOn))
        .opacity(isEnabled ? DSOpacity.strong : DSOpacity.disabled)
        .accessibilityRepresentation {
            Toggle(isOn: $isOn) { EmptyView() }
        }
    }
}

/// Tekent track + thumb; het Button-label blijft leeg. Als ButtonStyle
/// zodat de pressed-staat (thumb aan de doelzijde) uit `isPressed` komt.
private struct DSToggleTrackStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        Track(isOn: isOn, isPressed: configuration.isPressed)
    }

    private struct Track: View {
        let isOn: Bool
        let isPressed: Bool
        @State private var isHovering = false

        private static let trackSize = CGSize(width: 48, height: 24)
        private static let thumbDiameter: CGFloat = 22
        private static let hoverInset: CGFloat = 3

        var body: some View {
            let thumbAtTrailing = isPressed ? !isOn : isOn
            let inset = isHovering && !isPressed ? Self.hoverInset : DSSpacing.gapPx
            ZStack(alignment: thumbAtTrailing ? .trailing : .leading) {
                Capsule().fill(trackColor)
                Circle()
                    .fill(isOn ? DSColor.Action.onAction : DSColor.Foreground.thumb)
                    .frame(width: Self.thumbDiameter, height: Self.thumbDiameter)
                    .padding(thumbAtTrailing ? .trailing : .leading, inset)
            }
            .frame(width: Self.trackSize.width, height: Self.trackSize.height)
            .onHover { isHovering = $0 }
            .animation(DSMotion.micro, value: isHovering)
            .animation(.spring(duration: 0.2), value: isPressed)
            .animation(.spring(duration: 0.2), value: isOn)
        }

        private var trackColor: Color {
            if isOn { return DSColor.Background.action }
            if isPressed { return DSColor.Background.neutralStrongest }
            if isHovering { return DSColor.Background.neutralStronger }
            return DSColor.Background.neutral
        }
    }
}
