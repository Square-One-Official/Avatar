import SwiftUI
import AppKit

/// Bewegings-tokens (duur + curve) voor de hele app — één bron van waarheid,
/// net als DSColor/DSLayout/DSTypography. Honoreert "Verminder beweging".
public enum DSMotion {
    /// Controlepunten van de DS-ease-out — één bron voor SwiftUI (`easeOut`)
    /// én AppKit (`CAMediaTimingFunction`, zie DSFloatingWindow).
    public static let easeOutControlPoints: (Float, Float, Float, Float) = (0.23, 1, 0.32, 1)

    /// Sterkere ease-out dan SwiftUI's ingebouwde (die mist 'punch').
    /// cubic-bezier(0.23, 1, 0.32, 1).
    public static func easeOut(_ duration: Double) -> Animation {
        let c = easeOutControlPoints
        return .timingCurve(Double(c.0), Double(c.1), Double(c.2), Double(c.3), duration: duration)
    }

    /// Duur-tokens in seconden — voor AppKit-animaties die geen `Animation`
    /// kunnen aannemen (NSAnimationContext). De SwiftUI-tokens hieronder zijn
    /// hiervan afgeleid, zodat beide werelden dezelfde timing hebben.
    public enum Duration {
        public static let micro    = 0.10
        public static let fast     = 0.15
        public static let base     = 0.20
        public static let emphasis = 0.25
        public static let enter    = emphasis
        public static let exit     = base
    }

    // Semantische duur-tokens (vervangen de losse 0.1–0.45 literals).
    public static let micro    = easeOut(Duration.micro)    // hover/press-dim, tooltip, drag-handle
    public static let fast     = easeOut(Duration.fast)     // validatie, active-ring, grid-fade
    public static let base     = easeOut(Duration.base)     // kleine toasts, toggles, banners
    public static let emphasis = easeOut(Duration.emphasis) // stap-/sectiewissels (onboarding)

    // Springs — expliciete bounce (Jakub: bounce 0 = professioneel, geen overshoot).
    public static let springSmall     = Animation.spring(duration: 0.30, bounce: 0) // kleine moves, status-toast
    public static let springTransform = Animation.spring(duration: 0.40, bounce: 0) // canvas-transform, align-set, sidebar

    // Enter/exit-asymmetrie (Emil/animations.dev): een surface verschijnt met
    // `enter` en verdwijnt één tik sneller met `exit` — de dismiss voelt zo
    // snappier dan de entree, nooit andersom.
    public static let enter = emphasis // 0.25 ease-out — surface komt op
    public static let exit  = base     // 0.20 ease-out — surface gaat dicht (sneller)

    /// macOS "Verminder beweging"-vlag voor imperatieve withAnimation-sites.
    public static var reduceMotionEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Reduced-motion-bewuste withAnimation. Gebruik op élke withAnimation-site.
    public static func animate(_ animation: Animation, _ body: () -> Void) {
        withAnimation(reduceMotionEnabled ? nil : animation, body)
    }

    /// Voor animaties die alléén opacity veranderen (cross-fades, reveals).
    /// Die blijven óók onder "Verminder beweging" lopen: een fade verplaatst
    /// niets, dus veroorzaakt geen bewegingsklachten — hem tóch killen maakt
    /// reveals harder dan nodig. Bewust een eigen functie i.p.v. een kale
    /// `withAnimation`, zodat de uitzondering expliciet én greppable is
    /// (zie `scripts/check-motion.sh`).
    ///
    /// Gebruik dit NIET voor iets dat beweegt of schaalt — dan hoort `animate`.
    public static func animateCrossFade(_ animation: Animation, _ body: () -> Void) {
        withAnimation(animation, body)
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

public extension AnyTransition {
    /// Edge-slide met asymmetrische timing: entree `enter` (ease-out), dismiss
    /// `exit` (één tik sneller). De opacity wordt NIET los meegefade — dat
    /// desynct met de move onder een spring en is precies de "stagger+fade" die
    /// buggy oogde. Reduce-motion → kale opacity-fade, geen beweging.
    static func dsSlide(
        _ edge: Edge,
        reduceMotion: Bool = false,
        enter: Animation = DSMotion.enter,
        exit: Animation = DSMotion.exit
    ) -> AnyTransition {
        guard !reduceMotion else { return .opacity.animation(DSMotion.exit) }
        return .asymmetric(
            insertion: .move(edge: edge).animation(enter),
            removal:   .move(edge: edge).animation(exit)
        )
    }

    /// Anchor-bewuste scale+fade voor dropdowns/popovers: schaalt vanaf de
    /// trigger-rand (niet vanuit het midden). Scale en opacity delen één curve.
    static func dsScaleFade(
        anchor: UnitPoint,
        reduceMotion: Bool = false,
        enter: Animation = DSMotion.fast,
        exit: Animation = DSMotion.fast
    ) -> AnyTransition {
        let shape = AnyTransition.opacity.combined(with: .scale(scale: 0.96, anchor: anchor))
        guard !reduceMotion else { return .opacity.animation(DSMotion.fast) }
        return .asymmetric(
            insertion: shape.animation(enter),
            removal:   shape.animation(exit)
        )
    }
}
