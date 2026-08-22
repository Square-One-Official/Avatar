import SwiftUI
import AppKit

// MARK: - Reduce Motion

/// Applies an animation only when Reduce Motion is off.
private struct MotionAwareAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    func motionAwareAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionAwareAnimation(animation: animation, value: value))
    }
}

/// Runs `body` with `withAnimation` unless Reduce Motion is enabled.
@MainActor
enum Motion {
    static func run(
        _ reduceMotion: Bool,
        _ animation: Animation,
        _ body: () -> Void
    ) {
        if reduceMotion {
            body()
        } else {
            withAnimation(animation, body)
        }
    }
}

// MARK: - Reduce Transparency

/// Fills with a system material, or a solid `appSurface` when Reduce Transparency is on.
struct AppMaterialFill: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var material: Material = .thickMaterial

    var body: some View {
        if reduceTransparency {
            Color.appSurface
        } else {
            Rectangle().fill(material)
        }
    }
}

// MARK: - Pressable (respects Reduce Motion)

struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration, pressedScale: pressedScale)
    }

    private struct PressableLabel: View {
        let configuration: Configuration
        let pressedScale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? pressedScale : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12),
                           value: configuration.isPressed)
        }
    }
}
