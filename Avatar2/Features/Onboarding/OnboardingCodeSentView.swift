// Onboarding 2.0 — tijdelijke landing na het versturen van de code.
// E04.2 vervangt dit door de echte OTP-stap (DSOTPField, auto-verify bij
// het 6e cijfer, disabled-state, 'Wrong email? Go back'-link). De skip-link
// blijft hier zodat niemand vastzit zolang die stap er nog niet is.

import AvatarUI
import SwiftUI

struct OnboardingCodeSentView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: DSSpacing.gap2) {
                Text("Check your inbox")
                    .dsTextStyle(.h4)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text("We sent a sign-in code to \(model.trimmedEmail).")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
            }
            .multilineTextAlignment(.center)
            Spacer()
            Button("Continue without an account") {
                model.skipOnboarding()
            }
            .buttonStyle(.plain)
            .dsTextStyle(.labelBase)
            .foregroundStyle(DSColor.Foreground.subtle)
            .underline()
        }
        .padding(DSSpacing.gap8)
    }
}
