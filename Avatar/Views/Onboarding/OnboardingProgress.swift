import SwiftUI

/// Three-segment progress indicator for the onboarding sheet.
/// `current` is the step index (0-based). `total` is the visible step
/// count — when the user picks `cloudAllowed` the engine step disappears,
/// so total flips from 3 to 2 mid-flow. Animating between those two
/// states gives a clean shrink instead of a stale third pip lingering.
struct OnboardingProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(i <= current ? Color.appBrand : Color.secondary.opacity(0.25))
                    .frame(height: 3)
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeOut(duration: 0.22), value: current)
        .animation(.easeOut(duration: 0.22), value: total)
    }
}
