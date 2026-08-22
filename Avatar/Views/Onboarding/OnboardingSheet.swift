import SwiftUI

/// First-launch onboarding host. Owns the step state machine and the
/// `hasSeenOnboarding` AppStorage flag; renders the active step plus a
/// progress indicator and a Back button. Replaces the previous
/// `WelcomeSignInSheet` — its content has been refactored into
/// `OnboardingStepAuth`. Existing-user migration in `MainWindow.task`
/// seeds `hasSeenOnboarding = true` for anyone who already saw the old
/// sheet, so they never see this flow.
struct OnboardingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(PrivacyPreferences.self) private var prefs

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var step: Step = .auth

    enum Step: Int, Comparable {
        case auth = 0
        case privacy = 1
        case engine = 2
        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Total visible steps. The engine step is conditional on the user
    /// picking local-only in step 2 — `total` flips from 3 to 2 mid-flow
    /// when they pick cloud, and the progress indicator animates the
    /// shrink. Read inside `body` so SwiftUI re-evaluates when `prefs.mode`
    /// changes.
    private var totalSteps: Int { prefs.mode == .localOnly ? 3 : 2 }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgress(current: step.rawValue, total: totalSteps)
                .padding(.top, 22)
                .padding(.horizontal, 28)
                .padding(.bottom, 8)

            // Crossfade between steps. No slide — feels heavier than the
            // sheet's own transition and offers no extra information.
            Group {
                switch step {
                case .auth:
                    OnboardingStepAuth(advance: advanceFromAuth)
                case .privacy:
                    OnboardingStepPrivacy(onContinue: advanceFromPrivacy)
                case .engine:
                    OnboardingStepEngine(onDone: complete)
                }
            }
            .transition(.opacity)
            .id(step)

            // Back row hidden on step 1. ⎋ jumps back when visible — the
            // default cancel binding goes here rather than dismissing the
            // sheet so users can't accidentally bail mid-flow.
            if step > .auth {
                HStack {
                    Button {
                        goBack()
                    } label: {
                        Label(Loc.onboardingBack, systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 14)
                .padding(.top, 6)
            }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.appCanvas)
        .background(WindowBackgroundPainter(colorScheme: colorScheme).frame(width: 0, height: 0))
        .motionAwareAnimation(.easeOut(duration: 0.22), value: step)
    }

    // MARK: - Step transitions

    private func advanceFromAuth() {
        step = .privacy
    }

    private func advanceFromPrivacy() {
        // Local-only routes through the engine step; cloud is done after
        // step 2 because the engine choice is moot when cloud handles
        // background removal.
        if prefs.mode == .localOnly {
            step = .engine
        } else {
            complete()
        }
    }

    private func goBack() {
        switch step {
        case .auth: break
        case .privacy: step = .auth
        case .engine: step = .privacy
        }
    }

    private func complete() {
        hasSeenOnboarding = true
        dismiss()
    }
}
