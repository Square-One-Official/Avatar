// Onboarding 2.0 — Privacy-stap (E04.3). Twee keuzes: Local only / Cloud
// (besluit Thierry 2026-09-02; Figma toont nog drie rijen).

import AvatarUI
import SwiftUI

struct OnboardingPrivacyView: View {
    @Bindable var model: OnboardingModel
    private let prefs = PrivacyPreferences2.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                VStack(spacing: DSSpacing.gap2) {
                    Text("Choose how Aaavatar uses AI")
                        .dsTextStyle(.h1)
                        .foregroundStyle(DSColor.Foreground.primary)
                    Text("You control how far your photos travel. Change this anytime in Settings.")
                        .dsTextStyle(.bodyMedium)
                        .foregroundStyle(DSColor.Foreground.subtle)
                }
                .multilineTextAlignment(.center)

                PrivacyTierRadioGroup(
                    selection: Binding(
                        get: { prefs.tier },
                        set: { prefs.tier = $0 }
                    )
                )
                .padding(.top, DSSpacing.gap12)

                DSPrimaryButton("Continue", fullWidth: true) {
                    model.finishFromPrivacy()
                }
                .padding(.top, DSSpacing.gap12)
            }
            .frame(width: 332)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
