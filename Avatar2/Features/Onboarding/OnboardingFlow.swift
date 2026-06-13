// Onboarding 2.0 — container (Figma: Stories → Onboarding). Fade tussen de
// stappen: designreview-punt was dat splash → e-mail anders als twee
// verschillende apps voelt.

import AvatarUI
import SwiftUI

struct OnboardingFlow: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        ZStack {
            DSColor.Background.app.ignoresSafeArea()
            switch model.step {
            case .splash:
                OnboardingSplashView(model: model)
                    .transition(.opacity)
            case .email:
                OnboardingEmailView(model: model)
                    .transition(.opacity)
            case .otp:
                OnboardingOTPView(model: model)
                    .transition(.opacity)
            case .privacy:
                OnboardingPrivacyView(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.step)
        .preferredColorScheme(.dark)
    }
}
