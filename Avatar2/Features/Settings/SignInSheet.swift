// Sign-in-sheet (E18.1) — e-mail + OTP, los van onboarding zodat een
// uitgelogde gebruiker overal kan inloggen (Account-pagina + later de
// cloud-feature-gate E18.2). Hergebruikt AuthService via EntitlementModel
// (requestCode/verifyCode). DS-stijl gespiegeld op de onboarding-stappen.

import AvatarKit
import AvatarUI
import SwiftUI

struct SignInSheet: View {
    @Bindable var entitlement: EntitlementModel
    /// Aangeroepen ná een geslaagde login (bv. om de gate-actie te hervatten).
    var onSignedIn: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    private enum Phase { case email, otp }
    @State private var phase: Phase = .email
    @State private var email = ""
    @State private var code = ""
    // E18.24: error/success-states op de inputvelden i.p.v. een losse toast.
    @State private var emailValidation: DSValidationState = .normal
    @State private var otpValidation: DSValidationState = .normal

    private static let otpLength = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                DSIconButton(Image(systemName: "xmark"), size: .small) { dismiss() }
                    .accessibilityLabel("Close")
            }
            Group {
                switch phase {
                case .email: emailStep
                case .otp: otpStep
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(DSSpacing.gap8)
        .frame(width: 420)
        .background(DSColor.Background.app)
        // Schone start: geen oude fout van een vorige poging.
        .onAppear { entitlement.dismissAuthError() }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            Text("Sign in")
                .dsTextStyle(.h3)
                .foregroundStyle(DSColor.Foreground.primary)
            Text("We'll email you a 6-digit code. Your photos never leave your Mac.")
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
            DSTextField(
                placeholder: "Email address",
                icon: Image(systemName: "envelope"),
                validation: emailValidation,
                text: $email
            )
            .onSubmit { sendCode() }
            // Bij bewerken terug naar normaal (E18.24).
            .onChange(of: email) { _, _ in emailValidation = .normal }
            DSPrimaryButton("Send code", fullWidth: true) { sendCode() }
                .disabled(!canSubmitEmail || entitlement.authBusy)
        }
    }

    private var otpStep: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                Text("Check your email")
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text("We've sent a code to \(email)")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            DSOTPField(code: $code, length: Self.otpLength, validation: otpValidation)
                .onChange(of: code) { _, newValue in
                    // Bewerken wist een error-state (E18.24).
                    if otpValidation == .error { otpValidation = .normal }
                    if newValue.count == Self.otpLength { verify() }
                }
            DSPrimaryButton("Verify", fullWidth: true) { verify() }
                .disabled(code.count != Self.otpLength || entitlement.authBusy)
            DSGhostButton("Resend code", fullWidth: true) { sendCode() }
                .disabled(entitlement.authBusy)
            Button("Wrong email? Go back") {
                phase = .email
                code = ""
                otpValidation = .normal
                entitlement.dismissAuthError()
            }
            .buttonStyle(.plain)
            .dsTextStyle(.bodySmall)
            .foregroundStyle(DSColor.Foreground.subtle)
        }
    }

    private var canSubmitEmail: Bool {
        let t = email.trimmingCharacters(in: .whitespaces)
        return t.contains("@") && t.contains(".")
    }

    private func sendCode() {
        guard canSubmitEmail else { return }
        let address = email.trimmingCharacters(in: .whitespaces)
        Task {
            await entitlement.sendSignInCode(address)
            if entitlement.authError == nil {
                emailValidation = .normal
                phase = .otp
            } else {
                // E18.24: e-mailveld licht rood op; auto-herstel na enkele sec.
                emailValidation = .error
                entitlement.dismissAuthError()
                try? await Task.sleep(for: .seconds(3))
                if emailValidation == .error { emailValidation = .normal }
            }
        }
    }

    private func verify() {
        let address = email.trimmingCharacters(in: .whitespaces)
        Task {
            if await entitlement.verifySignInCode(address, code: code) {
                // E18.24: success-state kort tonen vóór het sluiten.
                otpValidation = .success
                try? await Task.sleep(for: .seconds(0.7))
                onSignedIn()
                dismiss()
            } else {
                // Fout: code-veld licht rood op, blijft staan tot bewerken of
                // auto-herstel na enkele seconden.
                otpValidation = .error
                entitlement.dismissAuthError()
                try? await Task.sleep(for: .seconds(3))
                if otpValidation == .error { otpValidation = .normal }
            }
        }
    }
}
