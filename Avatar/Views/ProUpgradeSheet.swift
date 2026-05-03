import SwiftUI
import AppKit

/// Paywall presented when a user hits a gated action — Magic Cutout toggle
/// or any 402 from the backend. State-aware:
///
/// - Free / lapsed users see the **Subscribe** flow with a Monthly/Yearly
///   toggle. Yearly is selected by default ("2 months free" anchor) so
///   the better-value path is the path of no clicks.
/// - Active Pro users out of credits see the **Top-up** flow with a
///   3-pack ladder (€1,99 / €4,99 / €14,99) — the largest pack carries
///   a "Best value" badge to anchor against.
///
/// Both routes hand off to Stripe Checkout in the default browser; return
/// is handled by the `aaavatar://` URL scheme handler which refreshes
/// `ProEntitlement` and dismisses the sheet.
struct ProUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var busy: Bool = false
    @State private var errorMessage: String?
    /// Which top-up pack the user has highlighted. Defaults to the
    /// best-value pack so a single-click "Buy" path picks the anchor.
    @State private var selectedPack: CreditPack = .credits750
    /// Mounted state for the staggered entrance of the pack cards.
    /// Reduced-motion accessibility skips the stagger by initialising
    /// to true via the .onAppear branch.
    @State private var packsMounted: Bool = false

    private var showsTopup: Bool {
        appState.proEntitlement.isPro
            && appState.proEntitlement.subscriptionStatus == .active
    }

    /// Selected billing cadence for the subscribe flow. Source of truth
    /// lives on `AppState` so the choice survives sheet dismissal +
    /// re-open within the same launch (small UX win).
    private var interval: Binding<SubscriptionInterval> {
        Binding(
            get: { appState.selectedSubscriptionInterval },
            set: { appState.selectedSubscriptionInterval = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                headline
                card
                if let errorMessage {
                    StatusChip(
                        severity: .danger,
                        message: errorMessage,
                        style: .soft,
                        action: StatusChipAction(label: Loc.tryAgain) {
                            Task {
                                if showsTopup {
                                    await startTopup()
                                } else {
                                    await startSubscribe()
                                }
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                footer
            }
            .padding(24)
        }
        // Top-up needs a bit more horizontal room for the 3 packs to breathe
        // without each card feeling cramped. Subscribe stays at 440.
        .frame(width: showsTopup ? 520 : 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.appCanvas)
        .background(WindowBackgroundPainter(colorScheme: colorScheme).frame(width: 0, height: 0))
        .animation(.easeOut(duration: 0.18), value: errorMessage)
        // Spring matches PillSegmentedControl elsewhere in the app — same
        // motion vocabulary so the sheet feels native to the product.
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: appState.selectedSubscriptionInterval)
        .onAppear {
            if reduceMotion {
                packsMounted = true
            } else {
                // Defer one tick so the @starting-style equivalent (initial
                // false) takes effect before flipping to true.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(20))
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                        packsMounted = true
                    }
                }
            }
        }
        .onDisappear {
            if appState.pendingMagicCutoutEnable && !appState.proEntitlement.isPro {
                appState.pendingMagicCutoutEnable = false
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text(showsTopup ? Loc.topupHeadline : Loc.proUpgradeTitle)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.secondary.opacity(0.12)))
            }
            .buttonStyle(PressableButtonStyle())
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var headline: some View {
        Text(headlineText)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var headlineText: String {
        if showsTopup {
            if let resetAt = appState.proEntitlement.monthlyResetAt {
                let fmt = DateFormatter()
                fmt.dateStyle = .medium
                fmt.timeStyle = .none
                return Loc.topupSubtitleResetsOn(fmt.string(from: resetAt))
            }
            return Loc.topupSubtitleNoDate
        }
        return Loc.proUpgradeSubtitle
    }

    // MARK: Card

    @ViewBuilder
    private var card: some View {
        if showsTopup {
            topupSection
        } else {
            subscribeSection
        }
    }

    // MARK: - Subscribe (free → Pro) flow

    /// Subscribe flow with monthly/yearly toggle on top + price card below.
    /// The toggle anchoring is critical: yearly is the default selection,
    /// so the user reads the "2 months free" line first and the monthly
    /// price reads as the "downgrade" instead of the "default."
    private var subscribeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            intervalToggle
            subscribeCard
        }
    }

    private var intervalToggle: some View {
        // Two-segment pill with the savings badge baked into the Yearly
        // segment. Built natively (not via PillSegmentedControl) because
        // we need the savings badge to render *inside* the segment.
        HStack(spacing: 4) {
            intervalSegment(.year, label: Loc.billingIntervalYear, accessory: yearlyBadge)
            intervalSegment(.month, label: Loc.billingIntervalMonth, accessory: nil)
        }
        .padding(3)
        .background(
            Capsule().fill(Color.secondary.opacity(0.10))
        )
    }

    private func intervalSegment(
        _ value: SubscriptionInterval,
        label: String,
        accessory: AnyView?
    ) -> some View {
        let selected = interval.wrappedValue == value
        return Button {
            interval.wrappedValue = value
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                if let accessory { accessory }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(selected ? Color.primary.opacity(0.10) : Color.clear)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(selected ? 0.08 : 0), lineWidth: 1)
                    )
                    .shadow(color: selected ? Color.black.opacity(0.25) : .clear, radius: 3, x: 0, y: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.97))
    }

    private var yearlyBadge: AnyView {
        AnyView(
            Text(Loc.yearlyPlanSavings)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(brandColor))
        )
    }

    private var subscribeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Plan name flips with the interval so the headline always
            // matches what the user is buying.
            Text(interval.wrappedValue == .year ? Loc.yearlyPlanTitle : Loc.monthlyPlanTitle)
                .font(.headline)

            priceBlock

            VStack(alignment: .leading, spacing: 8) {
                featureRow(Loc.proPlanFeatureUnlimited)
                featureRow(Loc.proPlanFeatureBatch(ProLimits.maxBatchImport))
                featureRow(Loc.proPlanFeatureCutout)
                featureRow(Loc.proPlanFeatureHair)
                featureRow(Loc.proPlanFeatureCredits)
            }

            // Pre-auth checkout: tap Subscribe → straight to Stripe. Stripe
            // collects email; the webhook links it to a Supabase account.
            // No sign-in friction before paying.
            primaryButton(title: Loc.proSubscribeCTA) {
                await startSubscribe()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    /// Big rounded price + cadence label. For yearly, also shows the
    /// per-month equivalent ("€4,16/mo billed annually") below — concrete
    /// numbers help users reason about the savings (Emil: prefer concrete
    /// values over abstract %).
    private var priceBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(interval.wrappedValue == .year ? ProTier.pro.annualPriceEUR : ProTier.pro.monthlyPriceEUR)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(interval.wrappedValue == .year ? Loc.proPerYear : Loc.proPerMonth)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if interval.wrappedValue == .year {
                Text(Loc.yearlyPlanMonthlyEquiv(ProTier.pro.annualPricePerMonthEUR))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Top-up (Pro out-of-credits) flow

    /// 3-pack ladder. Cards stagger in (60ms between each) for the first
    /// paint; reduced-motion users get the final state instantly.
    private var topupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(CreditPack.displayOrder.enumerated()), id: \.element) { index, pack in
                topupPackCard(pack: pack)
                    .opacity(packsMounted ? 1 : 0)
                    .offset(y: packsMounted ? 0 : 6)
                    .animation(
                        reduceMotion
                            ? nil
                            : .spring(response: 0.36, dampingFraction: 0.82)
                                .delay(Double(index) * 0.06),
                        value: packsMounted
                    )
            }
            // Single buy button below the cards. Buys whichever pack is
            // currently selected, so the user can preview prices before
            // committing.
            primaryButton(title: buyButtonTitle) {
                await startTopup()
            }
            .padding(.top, 4)
        }
    }

    private var buyButtonTitle: String {
        // Concrete number on the CTA so the user sees what they're
        // about to charge. ("Buy 200 credits" / "Koop 200 credits".)
        Loc.buyCreditsCTA(selectedPack.credits)
    }

    private func topupPackCard(pack: CreditPack) -> some View {
        let isSelected = pack == selectedPack
        return Button {
            selectedPack = pack
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(packLabel(pack))
                            .font(.system(size: 14, weight: .semibold))
                        if pack.isBestValue {
                            Text(Loc.packBestValueBadge)
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.3)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(brandColor))
                        }
                    }
                    Text(Loc.packCreditsDescriptor(
                        credits: pack.credits,
                        perCredit: formatPerCredit(pack)
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(pack.priceEUR)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                // Selection indicator. Filled circle when selected, ring
                // otherwise — same affordance as the macOS "radio" pattern.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(isSelected ? brandColor : Color.secondary.opacity(0.4))
                    .animation(.easeOut(duration: 0.16), value: isSelected)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? brandColor.opacity(0.08) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? brandColor.opacity(0.55) : Color.primary.opacity(0.06),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.985))
    }

    private func packLabel(_ pack: CreditPack) -> String {
        switch pack {
        case .credits50: return Loc.packStarterLabel
        case .credits200: return Loc.packStandardLabel
        case .credits750: return Loc.packBestValueLabel
        }
    }

    /// Formats centsPerCredit as "€0,040" / "€0.040" for display in the
    /// per-credit descriptor under each pack. Tracks the in-app
    /// language preference via `Loc.currencyLocale`.
    private func formatPerCredit(_ pack: CreditPack) -> String {
        let euros = pack.centsPerCredit / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 3
        formatter.maximumFractionDigits = 3
        formatter.locale = Loc.currencyLocale
        let value = formatter.string(from: NSNumber(value: euros)) ?? "0,000"
        return "€\(value)"
    }

    // MARK: - Shared sub-elements

    private var brandColor: Color { .appBrand }

    @ViewBuilder
    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
                .font(.callout)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func primaryButton(title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.small)
                }
                Text(title)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(busy)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Loc.proUpgradeFinePrint)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Link(Loc.termsOfService, destination: URL(string: "https://aaavatar.nl/terms-of-service")!)
                Link(Loc.privacyPolicy, destination: URL(string: "https://aaavatar.nl/privacy-policy")!)
            }
            .font(.caption)
        }
    }

    // MARK: Actions

    private func startSubscribe() async {
        errorMessage = nil
        busy = true
        defer { busy = false }
        do {
            let result = try await appState.backend.subscribeAnonymous(
                interval: appState.selectedSubscriptionInterval
            )
            try openCheckout(result)
        } catch let error as BackendError {
            errorMessage = userFacingMessage(for: error)
        } catch {
            errorMessage = Loc.checkoutGenericError
        }
    }

    private func startTopup() async {
        errorMessage = nil
        busy = true
        defer { busy = false }
        do {
            let result = try await appState.backend.topup(pack: selectedPack)
            try openCheckout(result)
        } catch BackendError.notSignedIn {
            errorMessage = Loc.proUpgradeSignInFirst
        } catch let error as BackendError {
            errorMessage = userFacingMessage(for: error)
        } catch {
            errorMessage = Loc.checkoutGenericError
        }
    }

    /// Map server / transport errors to short, friendly copy. Never lets a
    /// raw error code (like `checkout_failed`) leak to the chip — those are
    /// for the request log, not for users.
    private func userFacingMessage(for error: BackendError) -> String {
        switch error {
        case .server(_, "stripe_unavailable"):    return Loc.checkoutStripeUnavailable
        case .server(_, "checkout_init_failed"):  return Loc.checkoutInitFailed
        case .server(_, "pricing_misconfigured"): return Loc.checkoutPricingMisconfigured
        case .rateLimited:                         return Loc.checkoutRateLimited
        case .transport:                           return Loc.checkoutOffline
        default:                                   return Loc.checkoutGenericError
        }
    }

    private func openCheckout(_ result: CheckoutResult) throws {
        switch result {
        case .web(let url):
            NSWorkspace.shared.open(url)
        case .storeKit:
            throw BackendError.decode
        }
    }
}
