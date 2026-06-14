// Hover-affordances voor plain buttons in menu's/popovers en op de canvas-
// toolbar (E24). DSStateOpacityButtonStyle is intern; deze publieke modifiers
// geven dezelfde DS-hovertaal aan call-sites buiten AvatarUI:
//   - `dsHoverHighlight`: subtiele neutral-stronger achtergrond op hover
//     (zelfde token als de ghostNeutral-icon-button) — voor tekst-rijen/knoppen.
//   - `dsHoverScale`: lichte schaal op hover — voor swatches (vorm-knoppen).

import SwiftUI

public extension View {
    func dsHoverHighlight(cornerRadius: CGFloat = DSRadius.md) -> some View {
        modifier(DSHoverHighlight(cornerRadius: cornerRadius))
    }

    func dsHoverScale(_ scale: CGFloat = 1.10) -> some View {
        modifier(DSHoverScale(scale: scale))
    }
}

private struct DSHoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                hovering ? DSColor.Background.neutralStronger : Color.clear,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

private struct DSHoverScale: ViewModifier {
    let scale: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
    }
}
