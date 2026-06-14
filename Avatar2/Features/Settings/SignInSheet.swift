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
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            Text("Sign in")
                .dsTextStyle(.h3)
                .foregroundStyle(DSColor.Foreground.primary)
            Text("We'll email you a 6-digit code. Your photos never leave your Mac.")
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
            DSTextField(placeholder: "Email address", icon: Image(systemName: "envelope"), text: $email)
                .onSubmit { sendCode() }
            DSPrimaryButton("Send code", fullWidth: true) { sendCode() }
                .disabled(!canSubmitEmail || entitlement.authBusy)
            if let error = entitlement.authError {
                Text(error).dsTextStyle(.bodySmall).foregroundStyle(DSColor.Foreground.subtle)
            }
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
            DSOTPField(code: $code, length: Self.otpLength)
                .onChange(of: code) { _, newValue in
                    if newValue.count == Self.otpLength { verify() }
                }
            if let error = entitlement.authError {
                Text(error).dsTextStyle(.bodySmall).foregroundStyle(DSColor.Foreground.subtle)
            }
            DSPrimaryButton("Verify", fullWidth: true) { verify() }
                .disabled(code.count != Self.otpLength || entitlement.authBusy)
            DSGhostButton("Resend code", fullWidth: true) { sendCode() }
                .disabled(entitlement.authBusy)
            Button("Wrong email? Go back") { phase = .email; code = "" }
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
            if entitlement.authError == nil { phase = .otp }
        }
    }

    private func verify() {
        let address = email.trimmingCharacters(in: .whitespaces)
        Task {
            if await entitlement.verifySignInCode(address, code: code) {
                onSignedIn()
                dismiss()
            } else {
                code = ""
            }
        }
    }
}
