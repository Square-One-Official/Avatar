import SwiftUI
import AppKit

/// Bewegings-tokens (duur + curve) voor de hele app — één bron van waarheid,
/// net als DSColor/DSLayout/DSTypography. Honoreert "Verminder beweging".
public enum DSMotion {
    /// Sterkere ease-out dan SwiftUI's ingebouwde (die mist 'punch').
    /// cubic-bezier(0.23, 1, 0.32, 1).
    public static func easeOut(_ duration: Double) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    // Semantische duur-tokens (vervangen de losse 0.1–0.45 literals).
    public static let micro    = easeOut(0.10) // hover/press-dim, tooltip, drag-handle
    public static let fast     = easeOut(0.15) // validatie, active-ring, grid-fade
    public static let base     = easeOut(0.20) // kleine toasts, toggles, banners
    public static let emphasis = easeOut(0.25) // stap-/sectiewissels (onboarding)

    // Springs — expliciete bounce (Jakub: bounce 0 = professioneel, geen overshoot).
    public static let springSmall     = Animation.spring(duration: 0.30, bounce: 0) // kleine moves, status-toast
    public static let springTransform = Animation.spring(duration: 0.40, bounce: 0) // canvas-transform, align-set, sidebar

    /// macOS "Verminder beweging"-vlag voor imperatieve withAnimation-sites.
    public static var reduceMotionEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Reduced-motion-bewuste withAnimation. Gebruik op élke withAnimation-site.
    public static func animate(_ animation: Animation, _ body: () -> Void) {
        withAnimation(reduceMotionEnabled ? nil : animation, body)
    }
}

public extension View {
    /// Reduced-motion-bewuste vervanger voor `.animation(_:value:)`.
    /// Geeft nil door (beweging uit) als de gebruiker "Verminder beweging" aan heeft.
    func dsMotion<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(DSMotionModifier(animation: animation, value: value))
    }
}

private struct DSMotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
