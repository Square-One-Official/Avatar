// Onboarding 2.0 — Privacy tier-stap (E04.3). Drie radio-rijen i.p.v. toggle.

import AvatarUI
import SwiftUI

struct OnboardingPrivacyView: View {
    @Bindable var model: OnboardingModel
    private let prefs = PrivacyPreferences2.shared

    private var disabledTiers: Set<AIPrivacyTier> {
        AppleIntelligenceAvailability.supportsApplePrivateCloud ? [] : [.appleCloud]
    }

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
                    ),
                    disabledTiers: disabledTiers
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
        .refreshAppleIntelligenceAvailability {
            PrivacyPreferences2.shared.reapplyFingerprintPolicy()
        }
    }
}
