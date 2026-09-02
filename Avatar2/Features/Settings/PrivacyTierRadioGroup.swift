// Twee spacious radio-rijen voor de privacy-keuze (onboarding + Settings).

import AvatarUI
import SwiftUI

struct PrivacyTierRadioGroup: View {
    @Binding var selection: AIPrivacyTier

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            ForEach(AIPrivacyTier.userFacingChoices, id: \.self) { tier in
                PrivacyTierRadioRow(
                    tier: tier,
                    isSelected: selection.userFacing == tier
                ) {
                    selection = tier
                }
            }
        }
    }
}

private struct PrivacyTierRadioRow: View {
    let tier: AIPrivacyTier
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        SettingsCheckmarkRow(
            title: tier.title,
            subtitle: tier.description,
            isSelected: isSelected,
            leading: {
                Circle()
                    .fill(DSColor.Background.action)
                    .frame(width: 28, height: 28)
                    .overlay {
                        // Lime fill is theme-constant → always on-action ink
                        // (not Foreground.primary, which is white in dark).
                        DSIcon.image(tier.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(DSColor.Action.onAction)
                    }
            },
            action: onSelect
        )
    }
}
