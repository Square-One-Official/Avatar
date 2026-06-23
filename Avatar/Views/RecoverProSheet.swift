import SwiftUI

/// "Restore Pro on this Mac" sheet — wires the welcome surface to
/// `POST /v1/auth/send-recovery-email`. The use case: someone bought
/// Pro on a previous Mac (or a previous install) using one Mac's
/// Stripe checkout, then either reinstalled or moved to a new
/// machine, and now starts the app fresh with no signed-in session
/// and no device_grants row. They have nothing to identify their
/// account with except the email they typed into Stripe.
///
/// The sheet is intentionally information-light so the endpoint
/// stays oracle-resistant: success copy is "If we have an account
/// for that email, we sent a sign-in link" — never "no such email".
/// Rate-limit and shape errors get distinct copy because they're
/// safe to surface (not account-existence signals).
struct RecoverProSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var email: String = ""
    @State private var isSending: Bool = false
    @State private var didSend: Bool = false
    @State private var errorMessage: String?
    @FocusState private var emailFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Headline block — mirrors WelcomeSignInSheet's hierarchy.
            VStack(alignment: .leading, spacing: 10) {
                Text(Loc.recoverProTitle)
                    .font(.system(size: 22, weight: .semibold))

                Text(Loc.recoverProBody)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 18)

            // Email input
            VStack(alignment: .leading, spacing: 8) {
                Text(Loc.recoverProEmailLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("name@example.com", text: $email)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.appSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .focused($emailFocused)
                    .disabled(isSending || didSend)
                    .onSubmit(send)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 16)

            // Status row (success or error)
            statusRow
                .padding(.horizontal, 28)

            // CTAs
            VStack(spacing: 10) {
                Button(action: send) {
                    HStack(spacing: 8) {
                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(Loc.recoverProSendCta)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appBrand)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSend)

                Button {
                    dismiss()
                } label: {
                    Text(didSend ? Loc.welcomeMaybeLater : Loc.recoverProCancel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 28)
            .padding(.top, didSend || errorMessage != nil ? 16 : 18)
            .padding(.bottom, 22)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.appCanvas)
        .background(WindowBackgroundPainter(colorScheme: colorScheme).frame(width: 0, height: 0))
        .animation(.easeOut(duration: 0.18), value: didSend)
        .animation(.easeOut(duration: 0.18), value: errorMessage)
        .onAppear { emailFocused = true }
    }

    /// Email is considered submittable when it has the basic local@domain
    /// shape — keep the check loose; the backend does the strict validation
    /// and we don't want to block valid-but-unusual addresses on the client.
    private var canSend: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending, !didSend, trimmed.count >= 3, trimmed.count <= 254 else {
            return false
        }
        return trimmed.contains("@") && trimmed.contains(".")
    }

    @ViewBuilder
    private var statusRow: some View {
        if didSend {
            statusBanner(
                icon: "envelope.badge.fill",
                text: Loc.recoverProSent,
                tint: Color.appSuccess,
                ink: Color.appSuccessInk
            )
            .padding(.bottom, 8)
        } else if let msg = errorMessage {
            statusBanner(
                icon: "exclamationmark.triangle.fill",
                text: msg,
                tint: Color.appWarning,
                ink: Color.appWarningInk
            )
            .padding(.bottom, 8)
        }
    }

    private func statusBanner(icon: String, text: String, tint: Color, ink: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.30))
            )
            .transition(.opacity)
    }

    private func send() {
        guard canSend else { return }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        isSending = true
        errorMessage = nil
        Task { @MainActor in
            defer { isSending = false }
            do {
                try await appState.backend.sendRecoveryEmail(trimmed)
                didSend = true
            } catch let recoveryErr as BackendClient.RecoveryEmailError {
                errorMessage = recoveryErr.errorDescription
            } catch {
                errorMessage = BackendClient.RecoveryEmailError.unknown.errorDescription
            }
        }
    }
}
