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

    @State private var isHovering = false

    private var rowBackground: Color {
        if isSelected { return DSColor.Background.neutral }
        guard !isDisabled else { return .clear }
        return DSColor.neutralSurface(pressed: false, hovering: isHovering)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: DSSpacing.gap3) {
                    Circle()
                        .fill(DSColor.Background.action)
                        .frame(width: 28, height: 28)
                        .overlay {
                            DSIcon(tier.icon, size: 13, weight: .bold)
                                .foregroundStyle(DSColor.Action.onAction)
                        }
                        .opacity(isDisabled ? 0.45 : 1)

                    VStack(alignment: .leading, spacing: DSSpacing.gap0_5) {
                        Text(tier.title)
                            .dsTextStyle(.labelBase)
                            .foregroundStyle(isDisabled ? DSColor.Foreground.muted : DSColor.Foreground.primary)
                        Text(tier.description)
                            .dsTextStyle(.bodySmall)
                            .foregroundStyle(DSColor.Foreground.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: DSSpacing.gap2)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(
                            isSelected ? DSColor.Action.primaryForeground : DSColor.Foreground.muted
                        )
                        .opacity(isDisabled ? 0.4 : 1)
                }
                .padding(DSSpacing.gap4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .onHover { isHovering = $0 && !isDisabled }
            .animation(DSMotion.micro, value: isHovering)

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
