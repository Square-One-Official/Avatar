// Onboarding 2.0 — e-mailstap (Figma: Onboarding / Email, 2611:39442).
// E04.5: 1-op-1 met het frame — contentkolom 360 exact gecentreerd: kop H1,
// gap-8, input (placeholder "Work email address", mail-icoon, géén label),
// gap-2, full-width "Continue with email"; footer Body/Small muted op
// gap-12 van de onderrand met Terms/Privacy-links in lime (zelfde URL's
// als v1 ProUpgradeSheet). Buiten het frame maar functioneel vereist
// (bouwplan §Auth, in de geest van het design): foutmelding + RecoverPro-
// hint onder het veld, continue-without-account boven de footer.

import AvatarUI
import SwiftUI

struct OnboardingEmailView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                Text("Your email unlocks your license, your photos never leave your Mac.")
                    .dsTextStyle(.h1)
                    .foregroundStyle(DSColor.Foreground.primary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                    DSTextField(
                        placeholder: "Work email address",
                        icon: Image(systemName: "envelope"),
                        validation: model.auth.lastError == nil ? .normal : .error,
                        text: $model.emailInput
                    )
                    .onSubmit {
                        Task { await model.submitEmail() }
                    }
                    DSPrimaryButton("Continue with email", fullWidth: true) {
                        Task { await model.submitEmail() }
                    }
                    .disabled(!model.canSubmitEmail)

                    if let error = model.auth.lastError {
                        // E49.2: fouten in signaalstijl (rood veld + rode copy),
                        // in lijn met SignInSheet — niet dezelfde subtle-grijs
                        // als een bevestiging.
                        Text(error)
                            .dsTextStyle(.bodySmall)
                            .foregroundStyle(DSColor.Signal.error)
                    }
                    Text("Upgraded to Pro before? Sign in with that same email to keep it.")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                }
                .padding(.top, DSSpacing.gap8)
            }
            .frame(width: 360)

            Spacer()

            VStack(spacing: DSSpacing.gap3) {
                Button("Continue without an account") {
                    model.skipOnboarding()
                }
                .buttonStyle(.plain)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.subtle)
                .underline()

                footerText
                    .dsTextStyle(.bodySmall)
                    .multilineTextAlignment(.center)
                    .frame(width: 360)
            }
            .padding(.bottom, DSSpacing.gap12)
        }
        .frame(maxWidth: .infinity)
    }

    /// Footer uit het frame; links in lime zoals het design (AttributedString
    /// zodat de regel als één lopende tekst wikkelt).
    private var footerText: Text {
        var plain = AttributedString(
            "One look for every team portrait. Made on your Mac, not in the cloud. By clicking continue, you agree to our "
        )
        plain.foregroundColor = DSColor.Foreground.muted
        var terms = AttributedString("Terms of Service")
        terms.foregroundColor = DSColor.Action.primary
        terms.link = AppLinks.termsOfService
        var middle = AttributedString(" and ")
        middle.foregroundColor = DSColor.Foreground.muted
        var privacy = AttributedString("Privacy Policy")
        privacy.foregroundColor = DSColor.Action.primary
        privacy.link = AppLinks.privacyPolicy
        var dot = AttributedString(".")
        dot.foregroundColor = DSColor.Foreground.muted
        return Text(plain + terms + middle + privacy + dot)
    }
}
