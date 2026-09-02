import SwiftUI

/// Step 2 — privacy posture. Two large radio cards for `localOnly` vs
/// `cloudAllowed`. Selecting a card commits the choice into
/// `PrivacyPreferences` immediately so the host's flow logic (engine
/// step appears for local-only) reads the live value when computing
/// `total` for the progress indicator. "Continue" advances; "Back"
/// is owned by the host.
struct OnboardingStepPrivacy: View {
    @Environment(PrivacyPreferences.self) private var prefs

    /// Called when the user clicks Continue with a selection. Host
    /// either dismisses (cloudAllowed) or advances to the engine step
    /// (localOnly). The choice is already in `prefs.mode` by the time
    /// this fires — Continue is just a confirmation gesture.
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Loc.onboardingPrivacyTitle)
                    .font(.title2.weight(.semibold))
                Text(Loc.onboardingPrivacyBody)
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
                    isSelected: prefs.mode == .localOnly,
                    title: Loc.onboardingPrivacyLocalTitle,
                    badge: Loc.onboardingPrivacyLocalRecommended,
                    detail: Loc.onboardingPrivacyLocalBody,
                    icon: "lock.shield",
                    position: (1, 2)
                ) {
                    prefs.mode = .localOnly
                }
                ChoiceCard(
                    isSelected: prefs.mode == .cloudAllowed,
                    title: Loc.onboardingPrivacyCloudTitle,
                    badge: nil,
                    detail: Loc.onboardingPrivacyCloudBody,
                    icon: "cloud",
                    position: (2, 2)
                ) {
                    prefs.mode = .cloudAllowed
                }
            }
            .padding(.horizontal, 28)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Loc.onboardingPrivacyTitle)
            .focusable()
            .onMoveCommand { direction in
                switch direction {
                case .up: prefs.mode = .localOnly
                case .down: prefs.mode = .cloudAllowed
                default: break
                }
            }

            Button(action: onContinue) {
                Text(Loc.onboardingContinue)
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.appBrandSolid)
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
