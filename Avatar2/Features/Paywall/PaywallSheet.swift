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

    @State private var cmsProFeatures: [String] = PaywallSheet.proFeaturesCache ?? []
    private static var proFeaturesCache: [String]? = nil

    private static let fallbackProFeatures = [
        "Unlimited images",
        "All Starter features",
        "All editing features",
        "\(ProTier.pro.monthlyCredits) editing credits",
    ]

    private var proFeatures: [String] {
        cmsProFeatures.isEmpty ? PaywallSheet.fallbackProFeatures : cmsProFeatures
    }

    var body: some View {
        Group {
            if model.account == nil {
                // Fix: tot het account geladen is NIET gokken tussen subscribe en
                // top-up — anders flitst de paywall "Upgrade to Pro" voor een
                // actieve Pro/credit-houder en springt 'ie ná de refresh-on-appear
                // naar "Top up credits". Even laden i.p.v. de verkeerde variant.
                loadingPlaceholder
            } else if model.showsTopup {
                // Top-up (actieve Pro) — barebones, smal (ongewijzigd).
                VStack(alignment: .leading, spacing: DSSpacing.gap5) {
                    header
                    topupSection
                    checkoutErrorView
                    footer
                }
                .padding(DSSpacing.gap6)
                .frame(width: 440)
            } else {
                // E14.1: plan-kiezer conform frame 4019:953.
                planChooser
                    .padding(DSSpacing.gap8)
                    .frame(width: 900)
            }
        }
        .background(DSColor.Background.card)
        .appliedAppearancePreference()
        .task { await model.refresh() }
        .task {
            guard PaywallSheet.proFeaturesCache == nil else { return }
            if let config = try? await model.backend.appConfig(),
               !config.paywallProFeatures.isEmpty {
                PaywallSheet.proFeaturesCache = config.paywallProFeatures
                cmsProFeatures = config.paywallProFeatures
            }
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: DSSpacing.gap4) {
            HStack {
                Spacer(minLength: 0)
                DSIconButton(Image(systemName: "xmark"), size: .small) {
                    model.isPaywallPresented = false
                }
            }
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.gap8)
        }
        .padding(DSSpacing.gap6)
        .frame(width: 440)
    }

    @ViewBuilder
    private var checkoutErrorView: some View {
        if let error = model.checkoutError {
            Text(error)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.subtle)
        }
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

    // MARK: - Plan-kiezer (E14.1, frame 4019:953)

    private var planChooser: some View {
        VStack(spacing: DSSpacing.gap6) {
            ZStack {
                Text("Choose your plan")
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
                HStack {
                    Spacer()
                    DSIconButton(Image(systemName: "xmark"), size: .small) {
                        model.isPaywallPresented = false
                    }
                }
            }

            intervalToggle

            HStack(alignment: .top, spacing: DSSpacing.gap4) {
                starterCard
                proCard
            }

            checkoutErrorView
            footer
        }
        .animation(DSMotion.base, value: model.selectedInterval)
    }

    // Monthly / Yearly segmented pill (lokaal; geen AvatarUI-wijziging).
    private var intervalToggle: some View {
        HStack(spacing: 0) {
            segment("Monthly", interval: .month)
            segment("Yearly (2 months free)", interval: .year)
        }
        .padding(DSSpacing.gap0_5)
        .background(DSColor.Background.neutral, in: Capsule())
    }

    private func segment(_ title: String, interval: SubscriptionInterval) -> some View {
        let isSelected = model.selectedInterval == interval
        return Button {
            model.selectedInterval = interval
        } label: {
            Text(title)
                .dsTextStyle(.labelBase)
                .foregroundStyle(isSelected ? DSColor.Foreground.primary : DSColor.Foreground.muted)
                .padding(.horizontal, DSSpacing.gap4)
                .padding(.vertical, DSSpacing.gap2)
                .background {
                    if isSelected {
                        Capsule().fill(DSColor.Background.neutralStronger)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var starterCard: some View {
        planCard(highlighted: false) {
            VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                Text("Starter")
                    .dsTextStyle(.labelLarge)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text("Free")
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
            }
            VStack(alignment: .leading, spacing: DSSpacing.gap1_5) {
                featureRow("3 images total")
                featureRow("Local processing")
                featureRow("No bots")
                featureRow("Export")
            }
            .padding(.top, DSSpacing.gap3)
            Spacer(minLength: 0)
        }
    }

    private var proCard: some View {
        planCard(highlighted: true) {
            HStack(alignment: .top) {
                Text("Pro")
                    .dsTextStyle(.labelLarge)
                    .foregroundStyle(DSColor.Foreground.primary)
                Spacer()
                DSBadge("Upgrade", type: .brand)
            }
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.gap1) {
                Text(model.selectedInterval == .year ? ProTier.pro.annualPriceEUR : ProTier.pro.monthlyPriceEUR)
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
                    .contentTransition(.numericText())
                Text(model.selectedInterval == .year ? "/yr" : "/mo")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
            }
            VStack(alignment: .leading, spacing: DSSpacing.gap1_5) {
                ForEach(proFeatures, id: \.self) { featureRow($0) }
            }
            .padding(.top, DSSpacing.gap3)
            Spacer(minLength: DSSpacing.gap6)
            DSPrimaryButton("Upgrade to pro", fullWidth: true) {
                Task { await model.startSubscribe() }
            }
            .disabled(model.isCheckoutBusy)
        }
    }

    @ViewBuilder
    private func planCard<Content: View>(highlighted: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(DSSpacing.gap5)
        .frame(maxWidth: .infinity, minHeight: 380, alignment: .topLeading)
        .background(DSColor.Background.app, in: RoundedRectangle(cornerRadius: DSRadius.xl2))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.xl2).strokeBorder(
                highlighted ? DSColor.Action.primaryForeground : DSColor.Foreground.divider,
                lineWidth: highlighted ? DSBorderWidth.medium : DSBorderWidth.thin
            )
        }
    }

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: DSSpacing.gap2) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DSColor.Action.primaryForeground)
            Text(text)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.subtle)
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
                    .foregroundStyle(isSelected ? DSColor.Action.primaryForeground : DSColor.Foreground.muted)
            }
            .padding(.horizontal, DSSpacing.gap4)
            .padding(.vertical, DSSpacing.gap3)
            .background(DSColor.Background.neutral, in: RoundedRectangle(cornerRadius: DSRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.lg).strokeBorder(
                    isSelected ? DSColor.Action.primaryForeground : DSColor.Foreground.divider,
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
