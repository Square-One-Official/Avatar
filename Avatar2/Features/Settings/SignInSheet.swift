// Sign-in-sheet (E18.1) — e-mail + OTP, los van onboarding zodat een
// uitgelogde gebruiker overal kan inloggen (Account-pagina + later de
// cloud-feature-gate E18.2). Hergebruikt AuthService via EntitlementModel
// (requestCode/verifyCode). DS-stijl gespiegeld op de onboarding-stappen.
// E53.7: flow-state leeft in EntitlementModel.signInFlow.

import AvatarKit
import AvatarUI
import SwiftUI

struct SignInSheet: View {
    @Bindable var entitlement: EntitlementModel
    /// Aangeroepen ná een geslaagde login (bv. om de gate-actie te hervatten).
    var onSignedIn: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                DSIconButton(Image(systemName: "xmark"), label: "Close", size: .small) { close() }
            }
            Group {
                switch entitlement.signInFlow.phase {
                case .email: emailStep
                case .otp: otpStep
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(DSSpacing.gap8)
        .frame(width: 420)
        .background(DSColor.Background.app)
        .appliedAppearancePreference()
        .overlay(alignment: .bottom) {
            if let error = entitlement.authError {
                // UXS-2: duur uit het model (geen eigen literal) en de toast
                // regelt zelf aftellen + hover-pauze.
                DSToast(
                    title: "Couldn't sign you in",
                    description: error,
                    autoDismiss: EntitlementModel.infoToastDuration,
                    onClose: { entitlement.dismissAuthError() }
                )
                .padding(DSSpacing.gap4)
                .transition(.dsSlide(.bottom, reduceMotion: reduceMotion))
            }
        }
        .dsMotion(DSMotion.enter, value: entitlement.authError)
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
                validation: entitlement.signInFlow.emailValidation,
                text: $entitlement.signInFlow.email
            )
            .onSubmit { sendCode() }
            .onChange(of: entitlement.signInFlow.email) { _, _ in
                entitlement.signInFlow.emailValidation = .normal
            }
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
                Text("We've sent a code to \(entitlement.signInFlow.email)")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            DSOTPField(
                code: $entitlement.signInFlow.code,
                length: SignInFlowState.otpLength,
                validation: entitlement.signInFlow.otpValidation
            )
            .onChange(of: entitlement.signInFlow.code) { _, _ in
                if entitlement.signInFlow.otpValidation == .error {
                    entitlement.signInFlow.otpValidation = .normal
                }
            }
            DSPrimaryButton("Verify", fullWidth: true) { verify() }
                .disabled(
                    entitlement.signInFlow.code.count != SignInFlowState.otpLength
                        || entitlement.authBusy
                )
            DSGhostButton("Resend code", fullWidth: true) { sendCode() }
                .disabled(entitlement.authBusy)
            Button("Wrong email? Go back") {
                entitlement.signInFlow.phase = .email
                entitlement.signInFlow.code = ""
                entitlement.signInFlow.otpValidation = .normal
                entitlement.dismissAuthError()
            }
            .buttonStyle(.plain)
            .dsFocusEffectDisabled()
            .dsTextStyle(.bodySmall)
            .foregroundStyle(DSColor.Foreground.subtle)
        }
    }

    private var canSubmitEmail: Bool {
        let t = entitlement.signInFlow.email.trimmingCharacters(in: .whitespaces)
        return t.contains("@") && t.contains(".")
    }

    private func close() {
        entitlement.closeSignIn()
    }

    private func sendCode() {
        guard canSubmitEmail else { return }
        let address = entitlement.signInFlow.email.trimmingCharacters(in: .whitespaces)
        Task {
            await entitlement.sendSignInCode(address)
            if entitlement.authError == nil {
                entitlement.signInFlow.emailValidation = .normal
                entitlement.signInFlow.phase = .otp
            } else {
                entitlement.signInFlow.emailValidation = .error
                try? await Task.sleep(for: .seconds(3))
                if entitlement.signInFlow.emailValidation == .error {
                    entitlement.signInFlow.emailValidation = .normal
                }
            }
        }
    }

    private func verify() {
        let address = entitlement.signInFlow.email.trimmingCharacters(in: .whitespaces)
        let code = entitlement.signInFlow.code
        Task {
            if await entitlement.verifySignInCode(address, code: code) {
                entitlement.signInFlow.otpValidation = .success
                try? await Task.sleep(for: .seconds(0.7))
                onSignedIn()
                entitlement.closeSignIn()
            } else {
                entitlement.signInFlow.otpValidation = .error
                try? await Task.sleep(for: .seconds(3))
                if entitlement.signInFlow.otpValidation == .error {
                    entitlement.signInFlow.otpValidation = .normal
                }
            }
        }
    }
}
