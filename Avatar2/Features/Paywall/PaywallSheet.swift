// Paywall barebones (E08.3) — state-aware zoals v1 ProUpgradeSheet:
// free/lapsed → Subscribe (jaar/maand, jaar als anker), actieve Pro →
// top-up-ladder met best-value-anker. Bewust kaal: DS-componenten en
// tokens, geen stagger-animaties of pillen-maatwerk uit v1; dat komt
// terug wanneer Figma een paywall-frame heeft.

import AvatarKit
import AvatarUI
import SwiftUI

struct PaywallSheet: View {
    @Bindable var model: EntitlementModel

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap5) {
            header
            if model.showsTopup {
                topupSection
            } else {
                subscribeSection
            }
            if let error = model.checkoutError {
                Text(error)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
            }
            footer
        }
        .padding(DSSpacing.gap6)
        .frame(width: 440)
        .background(DSColor.Background.card)
        .preferredColorScheme(.dark)
        .task { await model.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: DSSpacing.gap2) {
            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                Text(model.showsTopup ? "Top up credits" : "Upgrade to Pro")
                    .dsTextStyle(.h4)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text(subtitle)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
            }
            Spacer(minLength: 0)
            DSIconButton(Image(systemName: "xmark"), size: .small) {
                model.isPaywallPresented = false
            }
        }
    }

    private var subtitle: String {
        if model.showsTopup {
            if let resetAt = model.monthlyResetAt {
                return "Your 200 monthly credits refill on \(resetAt.formatted(date: .abbreviated, time: .omitted))."
            }
            return "Your monthly credits refill with your plan."
        }
        return "One look for every team portrait — unlimited, on your Mac."
    }

    // MARK: - Subscribe (free/lapsed → Pro)

    private var subscribeSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            HStack(spacing: DSSpacing.gap2) {
                DSChip(
                    "Yearly · 2 months free",
                    type: model.selectedInterval == .year ? .brand : .neutral
                ) {
                    model.selectedInterval = .year
                }
                DSChip(
                    "Monthly",
                    type: model.selectedInterval == .month ? .brand : .neutral
                ) {
                    model.selectedInterval = .month
                }
            }

            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.gap1) {
                    Text(model.selectedInterval == .year ? ProTier.pro.annualPriceEUR : ProTier.pro.monthlyPriceEUR)
                        .dsTextStyle(.h3)
                        .foregroundStyle(DSColor.Foreground.primary)
                        .contentTransition(.numericText())
                    Text(model.selectedInterval == .year ? "/year" : "/month")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.subtle)
                }
                if model.selectedInterval == .year {
                    Text("\(ProTier.pro.annualPricePerMonthEUR)/mo billed annually")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                }
            }

            VStack(alignment: .leading, spacing: DSSpacing.gap1_5) {
                featureRow("Unlimited portraits")
                featureRow("\(ProTier.pro.monthlyCredits) credits per month for cloud edits")
                featureRow("Magic Cutout, clothing and hair edits")
            }

            DSPrimaryButton("Subscribe") {
                Task { await model.startSubscribe() }
            }
            .disabled(model.isCheckoutBusy)
        }
        .animation(.easeOut(duration: 0.18), value: model.selectedInterval)
    }

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: DSSpacing.gap2) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DSColor.Action.primary)
            Text(text)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.primary)
        }
    }

    // MARK: - Top-up (actieve Pro, credits op)

    private var topupSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap3) {
            ForEach(CreditPack.allCases) { pack in
                packRow(pack)
            }
            DSPrimaryButton("Buy \(model.selectedPack.credits) credits") {
                Task { await model.startTopup() }
            }
            .disabled(model.isCheckoutBusy)
        }
    }

    private func packRow(_ pack: CreditPack) -> some View {
        let isSelected = pack == model.selectedPack
        return Button {
            model.selectedPack = pack
        } label: {
            HStack(spacing: DSSpacing.gap3) {
                Text("\(pack.credits) credits")
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                if pack == .credits750 {
                    DSBadge("Best value", type: .brand)
                }
                Spacer(minLength: 0)
                Text(pack.priceEUR)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? DSColor.Action.primary : DSColor.Foreground.muted)
            }
            .padding(.horizontal, DSSpacing.gap4)
            .padding(.vertical, DSSpacing.gap3)
            .background(DSColor.Background.neutral, in: RoundedRectangle(cornerRadius: DSRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.lg).strokeBorder(
                    isSelected ? DSColor.Action.primary : DSColor.Foreground.divider,
                    lineWidth: DSBorderWidth.thin
                )
            }
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.lg))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            Text("Cancel anytime. Checkout runs through Stripe in your browser.")
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
            HStack(spacing: DSSpacing.gap3) {
                Link("Terms of Service", destination: URL(string: "https://aaavatar.nl/terms-of-service")!)
                Link("Privacy Policy", destination: URL(string: "https://aaavatar.nl/privacy-policy")!)
            }
            .dsTextStyle(.labelSmall)
            .foregroundStyle(DSColor.Foreground.muted)
        }
    }
}
