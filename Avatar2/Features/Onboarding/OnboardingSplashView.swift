// Onboarding 2.0 — splash (Figma: Onboarding / Splash). Donker i.p.v. het
// lichte Figma-moment: de review markeerde de licht→donker-overgang als
// onopgelost ontwerppunt, dus tot dat besluit valt blijft de hele flow
// dark-only (zoals de rest van het design system). CTA op Default-formaat
// (review: de kleine knop verdronk).

import AvatarUI
import SwiftUI

struct OnboardingSplashView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: DSSpacing.gap6) {
            Spacer()
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
            VStack(spacing: DSSpacing.gap2) {
                Text("Aaavatar")
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text("One look for every team portrait.")
                    .dsTextStyle(.bodyMedium)
                    .foregroundStyle(DSColor.Foreground.subtle)
            }
            Spacer()
            DSPrimaryButton("Continue") {
                model.advanceFromSplash()
            }
        }
        .padding(DSSpacing.gap8)
        .padding(.bottom, DSSpacing.gap8)
    }
}
