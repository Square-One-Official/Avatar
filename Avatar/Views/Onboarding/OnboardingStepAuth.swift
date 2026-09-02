import SwiftUI

/// Step 1 — sign in or skip. Same content as the previous standalone
/// `WelcomeSignInSheet`, refactored to invoke `advance()` instead of
/// dismissing so the host can route to the privacy step. Both successful
/// sign-in and "Maybe later" advance — the sheet doesn't gate progression
/// on having an account, only on the user expressing intent either way.
struct OnboardingStepAuth: View {
    @Environment(AppState.self) private var appState

    /// Called when the user has either signed in or chosen to skip.
    /// Host advances to the privacy step.
    let advance: () -> Void

    @State private var showRecoverProSheet = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Loc.welcomeTitle)
                    .font(.title2.weight(.semibold))
                Text(Loc.welcomeBody)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 22)

            VStack(spacing: 12) {
                GoogleSignInButton(isLoading: appState.auth.isSigningIn) {
                    appState.auth.startSignIn()
                }

                if let err = appState.auth.lastSignInError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.appWarningInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.appWarning.opacity(0.30))
                        )
                        .transition(.opacity)
                }

                Button {
                    advance()
                } label: {
                    Text(Loc.welcomeMaybeLater)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PressableButtonStyle())

                // Restore Pro for users who paid before signing in on
                // another Mac / install. Secondary (not tertiary) so the
                // link clears contrast while staying quieter than Google.
                Button {
                    showRecoverProSheet = true
                } label: {
                    Text(Loc.recoverProLink)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
        }
        .motionAwareAnimation(.easeOut(duration: 0.18), value: appState.auth.lastSignInError)
        .sheet(isPresented: $showRecoverProSheet) {
            RecoverProSheet()
                .environment(appState)
        }
        .onChange(of: appState.auth.isSignedIn) { _, signedIn in
            // Auto-advance on sign-in — the user expressed clear intent,
            // they shouldn't have to come back and click "Continue".
            if signedIn { advance() }
        }
    }
}
