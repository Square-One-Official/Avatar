// Drie spacious radio-rijen voor de privacy-tier-keuze (onboarding + Settings).

import AvatarUI
import SwiftUI

struct PrivacyTierRadioGroup: View {
    @Binding var selection: AIPrivacyTier
    var disabledTiers: Set<AIPrivacyTier> = []

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            ForEach(AIPrivacyTier.allCases, id: \.self) { tier in
                PrivacyTierRadioRow(
                    tier: tier,
                    isSelected: selection == tier,
                    isDisabled: disabledTiers.contains(tier),
                    disabledFootnote: disabledFootnote(for: tier)
                ) {
                    selection = tier
                }
            }
        }
    }

    private func disabledFootnote(for tier: AIPrivacyTier) -> String? {
        guard disabledTiers.contains(tier), tier == .appleCloud else { return nil }
        return AppleIntelligenceAvailability.status.footnote
    }
}

private struct PrivacyTierRadioRow: View {
    let tier: AIPrivacyTier
    let isSelected: Bool
    let isDisabled: Bool
    var disabledFootnote: String?
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            SettingsCheckmarkRow(
                title: tier.title,
                subtitle: tier.description,
                isSelected: isSelected,
                isDisabled: isDisabled,
                leading: {
                    Circle()
                        .fill(DSColor.Background.action)
                        .frame(width: 28, height: 28)
                        .overlay {
                            DSIcon(tier.icon, size: 13, weight: .bold)
                                .foregroundStyle(DSColor.Action.onAction)
                        }
                        .opacity(isDisabled ? 0.45 : 1)
                },
                action: onSelect
            )

            if isDisabled, let disabledFootnote {
                disabledFootnoteBlock(disabledFootnote)
            }
        }
    }

    @ViewBuilder
    private func disabledFootnoteBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            Text(text)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
                .fixedSize(horizontal: false, vertical: true)

            if tier == .appleCloud,
               AppleIntelligenceAvailability.status.offersSystemSettingsShortcut {
                DSGhostButton("Open System Settings", size: .small) {
                    AppleIntelligenceAvailability.openAppleIntelligenceSettings()
                }
            }
        }
        .padding(.leading, 28 + DSSpacing.gap3)
    }
}
