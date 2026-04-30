import SwiftUI

/// Capsule-shaped "Sign in with Google" button matching Google's dark
/// brand button variant: dark surface, white label, subtle 1px ring,
/// centered multicolor G + label. Used by the welcome sheet and the
/// paywall sign-in fallback so both surfaces share the same affordance.
struct GoogleSignInButton: View {
    let isLoading: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Logo / spinner share the same 18×18 frame so the
                // button height never jumps when the OAuth round-trip
                // begins.
                ZStack {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(labelColor)
                    } else {
                        GoogleGMark(size: 18)
                    }
                }
                .frame(width: 18, height: 18)

                Text(Loc.signInWithGoogle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(labelColor)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(surfaceColor)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.985))
        .disabled(isLoading)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.18), value: isLoading)
    }

    // MARK: Theming
    //
    // Two variants: dark canvas → black surface + white text + light
    // ring; light canvas → white surface + dark text + neutral ring.
    // Both follow Google's brand button guidelines while sitting
    // comfortably on Avatar's appCanvas. Hover tweaks the surface
    // tone slightly rather than swapping colors so it reads as a
    // calm response, not a state change.

    private var isDark: Bool { colorScheme == .dark }

    private var surfaceColor: Color {
        if isDark {
            return Color.white.opacity(hovering ? 0.06 : 0.04)
        } else {
            return Color.white.opacity(hovering ? 0.96 : 1.0)
        }
    }

    private var labelColor: Color {
        isDark ? Color.white : Color(red: 0.12, green: 0.12, blue: 0.14)
    }

    private var borderColor: Color {
        isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.14)
    }
}
