import SwiftUI

/// First-launch welcome surface. Presented over the main window once,
/// gated by `@AppStorage("hasSeenWelcomeSignIn")`. The primary action is
/// Google sign-in (so Pro / credits sync across Macs); the secondary
/// "Maybe later" lets the user dismiss without signing in. Either path
/// flips the flag so the sheet never reappears.
///
/// We *don't* dismiss automatically when the OAuth round-trip starts —
/// the user has to leave Avatar to complete the sign-in in their browser,
/// and seeing the sheet still mounted on return is the natural visual
/// continuity. Dismissal only happens once `auth.isSignedIn` flips true.
struct WelcomeSignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    /// Persisted so the sheet only fires once. Mirrors the value the
    /// presenting view passed in — written here too so any path that
    /// dismisses the sheet (sign-in, skip, OS-level close) marks it seen.
    @AppStorage("hasSeenWelcomeSignIn") private var hasSeenWelcomeSignIn = false

    /// Drives the secondary "Already paid? Restore Pro" sheet that posts
    /// to `/v1/auth/send-recovery-email`. Local @State because the sheet
    /// is always presented as a child of this one and never persisted.
    @State private var showRecoverProSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Headline block
            VStack(alignment: .leading, spacing: 10) {
                Text(Loc.welcomeTitle)
                    .font(.system(size: 24, weight: .semibold))

                Text(Loc.welcomeBody)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 22)

            // Sign-in CTA + skip
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
                    skip()
                } label: {
                    Text(Loc.welcomeMaybeLater)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PressableButtonStyle())
                .keyboardShortcut(.cancelAction)

                // Subdued tertiary affordance for users who already bought
                // Pro on another Mac (or before signing in) — opens
                // `RecoverProSheet` which POSTs to /v1/auth/send-recovery-email.
                // Deliberately low-contrast so it doesn't compete with the
                // primary Google sign-in CTA above.
                Button {
                    showRecoverProSheet = true
                } label: {
                    Text(Loc.recoverProLink)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.appCanvas)
        .background(WindowBackgroundPainter(colorScheme: colorScheme).frame(width: 0, height: 0))
        .animation(.easeOut(duration: 0.18), value: appState.auth.lastSignInError)
        .sheet(isPresented: $showRecoverProSheet) {
            RecoverProSheet()
                .environment(appState)
        }
        .onChange(of: appState.auth.isSignedIn) { _, signedIn in
            // Auto-dismiss on successful sign-in — the user already gave
            // intent by clicking the button; no need for them to come
            // back and click "Continue".
            if signedIn {
                hasSeenWelcomeSignIn = true
                dismiss()
            }
        }
    }

    private func skip() {
        hasSeenWelcomeSignIn = true
        dismiss()
    }
}
