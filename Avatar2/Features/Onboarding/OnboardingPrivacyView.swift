// Onboarding 2.0 — Privacy/online-modellen-stap (E04.3, Figma: Onboarding /
// Permissions 2611:39477). Kop H1 "Allow online models", subregel met de
// consequentie, daaronder de toggle-kaart (dezelfde rij als Settings >
// AI & Models, E15.2) en één full-width Continue. De toggle schrijft live
// naar PrivacyPreferences2 — dezelfde keys/rawValues als v1, incl.
// fingerprint-beleid. Waveform-icoon in het frame is placeholder → cloud.
//
// Contentkolom 332 + gecentreerd, zelfde scaffold als de OTP-stap.

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
                    Text("Allow online models")
                        .dsTextStyle(.h1)
                        .foregroundStyle(DSColor.Foreground.primary)
                    Text("Unlocks Magic Cutout, clothing and hair edits. Photos are processed securely and never stored.")
                        .dsTextStyle(.bodyMedium)
                        .foregroundStyle(DSColor.Foreground.subtle)
                }
                .multilineTextAlignment(.center)

                toggleCard
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

    // Zelfde rij als de AI & Models-kaart (E15.2): cloud-glyph + titel +
    // consequentie + DSToggle die `mode` schrijft.
    private var toggleCard: some View {
        HStack(spacing: DSSpacing.gap3) {
            Circle()
                .fill(DSColor.Background.action)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DSColor.Action.onAction)
                }
            VStack(alignment: .leading, spacing: DSSpacing.gap0_5) {
                Text("Allow online models")
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text("This will give you more advanced editing features")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            Spacer(minLength: DSSpacing.gap2)
            DSToggle(isOn: Binding(
                get: { prefs.mode == .cloudAllowed },
                set: { prefs.mode = $0 ? .cloudAllowed : .localOnly }
            ))
        }
        .padding(DSSpacing.gap4)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
    }
}
