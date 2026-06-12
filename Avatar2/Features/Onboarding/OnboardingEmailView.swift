// Onboarding 2.0 — e-mailstap (Figma: Onboarding / Email, dark). Copy volgt
// de verwerkte review-fixes: subtitle legt uit waaróm e-mail nodig is,
// footer in portret-termen, expliciet continue-without-account-pad en de
// RecoverPro-hint voor Pro-gebruikers (bouwplan §Auth & betalingen, punt 4).
// Geen Google-knop in 2.0; foutmeldingen in neutrale tinten — het dark
// design system kent bewust geen signaalkleuren (E03.1).

import AvatarUI
import SwiftUI

struct OnboardingEmailView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: DSSpacing.gap2) {
                Text("No strings attached. No servers either.")
                    .dsTextStyle(.h4)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text("Your email unlocks your license — your photos never leave your Mac.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: DSSpacing.gap3) {
                DSTextField(
                    label: "Email",
                    placeholder: "you@company.com",
                    text: $model.emailInput
                )
                .onSubmit {
                    Task { await model.submitEmail() }
                }
                if let error = model.auth.lastError {
                    Text(error)
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.subtle)
                }
                Text("Upgraded to Pro before? Sign in with that same email to keep it.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            .frame(width: 320)
            .padding(.top, DSSpacing.gap8)

            DSPrimaryButton("Continue") {
                Task { await model.submitEmail() }
            }
            .disabled(!model.canSubmitEmail)
            .padding(.top, DSSpacing.gap6)

            Spacer()

            VStack(spacing: DSSpacing.gap3) {
                Button("Continue without an account") {
                    model.skipOnboarding()
                }
                .buttonStyle(.plain)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.subtle)
                .underline()

                Text("One look for every team portrait. Made on your Mac, not in the cloud.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }
        }
        .padding(DSSpacing.gap8)
    }
}
