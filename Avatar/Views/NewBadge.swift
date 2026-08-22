import SwiftUI

/// Compact "NEW" pill rendered next to recently-launched feature
/// affordances. Driven by Payload announcements: as long as an
/// unseen announcement targets a given `componentId`, the badge shows.
///
/// Visual style matches `ProBadge` — same metrics, typography, and
/// tracking — but tints with `appBrand` so it reads as informational
/// rather than premium-gated.
struct NewBadge: View {
    var body: some View {
        Text("NEW")
            .font(.caption2.weight(.bold))
            .tracking(0.3)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.appBrand))
            .accessibilityHidden(true)
    }
}

private struct NewBadgeOverlayModifier: ViewModifier {
    let componentId: String
    @Environment(AnnouncementService.self) private var service
    @Environment(PrivacyPreferences.self) private var privacyPrefs

    private var visible: Bool {
        if !privacyPrefs.cloudAllowed,
           BadgeComponent.cloudOnlyFeatures.contains(componentId) {
            return false
        }
        return service.isBadgeActive(for: componentId)
    }

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if visible {
                NewBadge()
                    // Tug the pill out of the host's bounds so it
                    // floats over the corner like a notification dot.
                    .offset(x: 8, y: -6)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .motionAwareAnimation(.easeOut(duration: 0.18), value: visible)
    }
}

extension View {
    /// Overlays a "NEW" pill at the top-trailing corner of the receiver
    /// while the announcement targeting `componentId` is active. Add this
    /// modifier to whichever view should advertise the feature — buttons,
    /// nav rows, sidebar items.
    ///
    /// `componentId` must match an entry in Payload's badge-component
    /// registry; otherwise nothing renders even if you publish a
    /// targeting announcement. Keep IDs in `BadgeComponent` so callers
    /// pick from a typed list rather than free-form strings.
    func newBadge(_ componentId: String) -> some View {
        modifier(NewBadgeOverlayModifier(componentId: componentId))
    }
}

#Preview {
    NewBadge()
        .padding()
}
