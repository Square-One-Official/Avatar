import SwiftUI

/// Step 3 — local cutout engine. Only shown when the user picked
/// `localOnly` in step 2. Two cards: Apple Vision (default, always
/// available) and Enhanced model (downloadable, ~90 MB). The download
/// itself is **deferred** to first use — a user who picks "downloaded
/// model" out of curiosity but doesn't import for a week shouldn't be
/// charged 90 MB on launch. Until the BiRefNet session lands, picking
/// the downloaded model is recorded but the cutout pipeline still
/// transparently uses Apple Vision; a banner in Settings makes that
/// fallback visible.
struct OnboardingStepEngine: View {
    @Environment(PrivacyPreferences.self) private var prefs

    /// Called when the user clicks Done. Host marks onboarding complete
    /// and dismisses.
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Loc.onboardingEngineTitle)
                    .font(.system(size: 22, weight: .semibold))
                Text(Loc.onboardingEngineBody)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 18)

            VStack(spacing: 10) {
                ChoiceCard(
                    isSelected: prefs.engine == .appleVision,
                    title: Loc.onboardingEngineAppleVisionTitle,
                    badge: Loc.onboardingEngineAppleVisionDefault,
                    detail: Loc.onboardingEngineAppleVisionBody,
                    icon: "applelogo"
                ) {
                    prefs.engine = .appleVision
                }
                ChoiceCard(
                    isSelected: prefs.engine == .downloadedModel,
                    title: Loc.onboardingEngineDownloadedTitle,
                    badge: nil,
                    detail: Loc.onboardingEngineDownloadedBody,
                    icon: "arrow.down.circle"
                ) {
                    prefs.engine = .downloadedModel
                }
            }
            .padding(.horizontal, 28)

            Button(action: onDone) {
                Text(Loc.onboardingDone)
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.appBrand)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 4)
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Shared card view

/// Radio-card primitive used by both the privacy and engine steps. Selection
/// state is owned by the parent (writes the underlying preference); the
/// card just displays the current state and exposes a tap target. Keeping
/// this view stateless avoids the source-of-truth split where a `@State`
/// selection inside the card could drift from the persisted preference.
struct ChoiceCard: View {
    let isSelected: Bool
    let title: String
    /// Optional pill (e.g. "Recommended for privacy" / "Default") rendered
    /// next to the title. Set nil to omit.
    let badge: String?
    let detail: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Color.appBrand : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color.secondary.opacity(0.15))
                                )
                        }
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(1)
                }

                Spacer(minLength: 0)

                // Radio indicator on the right keeps the eye on the choice
                // structure rather than buried inside the icon column.
                Circle()
                    .strokeBorder(isSelected ? Color.appBrand : Color.secondary.opacity(0.4),
                                   lineWidth: 1.5)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.appBrand : Color.clear)
                            .padding(4)
                    )
                    .frame(width: 18, height: 18)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? Color.appBrand : Color.secondary.opacity(0.18),
                                           lineWidth: isSelected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}
