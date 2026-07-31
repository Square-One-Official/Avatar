// Onboarding 2.0 — OTP-stap (Figma: Onboarding / OTP, 2611:39463). E04.5:
// contentkolom 332 exact gecentreerd — kop H1 "Check your email", gap-2,
// subregel Body/Medium subtle, gap-12, OTP-veld, gap-12, full-width Verify
// (lime) met gap-2 daaronder de ghost "Resend code" (DSGhostButton, E03.9).
// Buiten het frame, functioneel behouden (review/bouwplan): dynamisch
// e-mailadres in de subregel, foutmelding/resend-bevestiging, 'Wrong
// email? Go back'. Auto-verify bij het 6e cijfer blijft.

import AvatarUI
import SwiftUI

struct OnboardingOTPView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                VStack(spacing: DSSpacing.gap2) {
                    Text("Check your email")
                        .dsTextStyle(.h1)
                        .foregroundStyle(DSColor.Foreground.primary)
                    Text("We've sent a 6-digit code to \(model.trimmedEmail)")
                        .dsTextStyle(.bodyMedium)
                        .foregroundStyle(DSColor.Foreground.subtle)
                }
                .multilineTextAlignment(.center)

                VStack(spacing: DSSpacing.gap2) {
                    DSOTPField(
                        code: $model.otpCode,
                        length: OnboardingModel.otpLength,
                        validation: model.auth.lastError == nil ? .normal : .error
                    )
                        .onChange(of: model.otpCode) { _, newValue in
                            guard newValue.count == OnboardingModel.otpLength else { return }
                            Task { await model.verifyCode() }
                        }
                    if let error = model.auth.lastError {
                        // E49.2: fout in signaalstijl (rood veld + rode copy, in
                        // lijn met SignInSheet); de succesbevestiging hieronder
                        // blijft subtle.
                        Text(error)
                            .dsTextStyle(.bodySmall)
                            .foregroundStyle(DSColor.Signal.error)
                    } else if model.didResendCode {
                        Text("New code sent.")
                            .dsTextStyle(.bodySmall)
                            .foregroundStyle(DSColor.Foreground.subtle)
                    }
                }
                .padding(.top, DSSpacing.gap12)

                VStack(spacing: DSSpacing.gap2) {
                    DSPrimaryButton("Verify", fullWidth: true) {
                        Task { await model.verifyCode() }
                    }
                    .disabled(!model.canVerifyCode)

                    DSGhostButton("Resend code", fullWidth: true) {
                        Task { await model.resendCode() }
                    }
                    .disabled(model.auth.isBusy)
                }
                .padding(.top, DSSpacing.gap12)
            }
            .frame(width: 332)

            Spacer()

            Button("Wrong email? Go back") {
                model.goBackToEmail()
            }
            .buttonStyle(.plain)
            .dsTextStyle(.labelBase)
            .foregroundStyle(DSColor.Foreground.subtle)
            .underline()
            .padding(.bottom, DSSpacing.gap12)
        }
        .frame(maxWidth: .infinity)
    }
}
