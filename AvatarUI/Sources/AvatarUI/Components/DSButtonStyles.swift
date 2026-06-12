// Interactiestaten zoals in Figma "Components": alle knoppen/chips dimmen
// via de opacity-schaal — Default=Strong(1), Hover=Medium(.75),
// Pressed=Subtle(.5), Disabled=Disabled(.25).

import SwiftUI

/// ButtonStyle die de Figma-opacitystates op het label toepast.
struct DSStateOpacityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StateOpacityBody(configuration: configuration)
    }

    private struct StateOpacityBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .opacity(currentOpacity)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.1), value: isHovering)
        }

        private var currentOpacity: Double {
            if !isEnabled { return DSOpacity.disabled }
            if configuration.isPressed { return DSOpacity.subtle }
            if isHovering { return DSOpacity.medium }
            return DSOpacity.strong
        }
    }
}
