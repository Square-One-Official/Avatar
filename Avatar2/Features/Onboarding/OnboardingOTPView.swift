// Onboarding 2.0 — OTP-stap (Figma: Onboarding / OTP, dark). Review-fixes:
// auto-verify bij het 6e cijfer, Verify-knop met echte disabled-state,
// 'Wrong email? Go back'-link, en Resend-link in subtle i.p.v. het te lage
// contrast uit het oorspronkelijke frame.

import AvatarUI
import SwiftUI

struct OnboardingOTPView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: DSSpacing.gap2) {
                Text("Check your inbox")
                    .dsTextStyle(.h4)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text("We sent a 6-digit code to \(model.trimmedEmail).")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
            }
            .multilineTextAlignment(.center)

            VStack(spacing: DSSpacing.gap3) {
                DSOTPField(code: $model.otpCode, length: OnboardingModel.otpLength)
                    .onChange(of: model.otpCode) { _, newValue in
                        guard newValue.count == OnboardingModel.otpLength else { return }
                        Task { await model.verifyCode() }
                    }
                if let error = model.auth.lastError {
                    Text(error)
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.subtle)
                } else if model.didResendCode {
                    Text("New code sent.")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.subtle)
                }
            }
            .padding(.top, DSSpacing.gap8)

            DSPrimaryButton("Verify") {
                Task { await model.verifyCode() }
            }
            .disabled(!model.canVerifyCode)
            .padding(.top, DSSpacing.gap6)

            Spacer()

            VStack(spacing: DSSpacing.gap3) {
                Button("Resend code") {
                    Task { await model.resendCode() }
                }
                .buttonStyle(.plain)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.subtle)
                .underline()
                .disabled(model.auth.isBusy)

                Button("Wrong email? Go back") {
                    model.goBackToEmail()
                }
                .buttonStyle(.plain)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.subtle)
                .underline()
            }
        }
        .padding(DSSpacing.gap8)
    }
}
