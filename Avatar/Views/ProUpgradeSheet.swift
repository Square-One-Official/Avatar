import SwiftUI
import AppKit

/// Paywall presented when a user hits a gated action — Magic Cutout toggle
/// or any 402 from the backend. State-aware: free users see a single
/// Subscribe card; Pro users out of credits see a single Top-up card.
/// Both routes hand off to Stripe Checkout in the default browser; return is
/// handled by the `aaavatar://` URL scheme handler which refreshes
/// `ProEntitlement` and dismisses the sheet.
struct ProUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var busy: Bool = false
    @State private var errorMessage: String?
    /// Set when Subscribe is tapped while the user isn't signed in. Swaps the
    /// "Subscribe" CTA for the Google sign-in button so the user can resolve
    /// the prerequisite without leaving the paywall. Once `auth.isSignedIn`
    /// flips true we auto-resume the subscribe call so the user only has to
    /// click once to express intent.
    @State private var awaitingSignIn: Bool = false

    /// Top-up is only relevant once the user has an active Pro subscription —
    /// credits are useless without Pro since the gated feature requires it.
    /// Grace-period (`.lapsed`) is treated as "no longer Pro" for paywall
    /// purposes: prompt to renew, not to top up.
    private var showsTopup: Bool {
        appState.proEntitlement.isPro
            && appState.proEntitlement.subscriptionStatus == .active
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                headline
                card
                if let errorMessage {
                    StatusChip(severity: .danger, message: errorMessage, style: .soft)
                        .transition(.opacity)
                }
                footer
            }
            .padding(24)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.appCanvas)
        .background(WindowBackgroundPainter(colorScheme: colorScheme).frame(width: 0, height: 0))
        .animation(.easeOut(duration: 0.18), value: errorMessage)
        .onChange(of: appState.auth.isSignedIn) { _, signedIn in
            // Auto-resume Subscribe once the user finishes Google OAuth in
            // the browser and the URL-scheme callback flips auth on. The
            // user clicked Subscribe once; they shouldn't have to click it
            // again after sign-in.
            if signedIn && awaitingSignIn {
                awaitingSignIn = false
                Task { await startSubscribe() }
            }
        }
        .onDisappear {
            // If the user closes the sheet without completing checkout, drop
            // the toggle-driven intent so a later upgrade via a different
            // entry point doesn't silently flip the toggle on.
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

    // MARK: Headline

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
            topupCard
        } else {
            subscribeCard
        }
    }

    private var subscribeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Loc.proPlanName).font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Loc.proPlanPrice)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text(Loc.proPerMonth)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                featureRow(Loc.proPlanFeatureUnlimited)
                featureRow(Loc.proPlanFeatureBatch(ProLimits.maxBatchImport))
                featureRow(Loc.proPlanFeatureCutout)
                featureRow(Loc.proPlanFeatureHair)
                featureRow(Loc.proPlanFeatureCredits)
            }

            // Primary action morphs between Subscribe and Sign-in. The
            // sign-in branch only appears after the user clicked Subscribe
            // and we discovered they weren't signed in — never as a
            // first-impression CTA. Once auth flips true, the subscribe
            // call resumes automatically (see `.onChange` below).
            ZStack {
                if awaitingSignIn {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Loc.proUpgradeSignInToContinue)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        GoogleSignInButton(isLoading: appState.auth.isSigningIn) {
                            appState.auth.startSignIn()
                        }
                    }
                    .transition(.opacity)
                } else {
                    primaryButton(title: Loc.proSubscribeCTA) {
                        await startSubscribe()
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.22), value: awaitingSignIn)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var topupCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Loc.topupCardTitle).font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Loc.topupCardPrice)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text(Loc.topupOneTime)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text(Loc.topupCardDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            primaryButton(title: Loc.topupCTA) {
                await startTopup()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

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

    // MARK: Footer

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
            let result = try await appState.backend.subscribe()
            // Subscribe succeeded — clear any prior sign-in morph state so
            // the card returns to its normal CTA on the next open.
            awaitingSignIn = false
            try openCheckout(result)
            // Sheet stays open — URL-scheme callback refreshes ProEntitlement
            // and dismisses via NotificationCenter when checkout completes.
        } catch BackendError.notSignedIn {
            // Inline morph instead of the cross-window Settings prompt:
            // the user already expressed intent here, keep them on the
            // paywall and offer Google sign-in directly.
            awaitingSignIn = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func startTopup() async {
        errorMessage = nil
        busy = true
        defer { busy = false }
        do {
            let result = try await appState.backend.topup(pack: .credits200)
            try openCheckout(result)
        } catch BackendError.notSignedIn {
            // Top-up only fires for active Pro users, so a missing session
            // here usually means the keychain entry expired. Show the
            // inline error chip — no global alert needed since the sheet
            // is already in focus.
            errorMessage = Loc.proUpgradeSignInFirst
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Branches on the `CheckoutResult` union from the backend. DMG-build
    /// only handles `.web`; `.storeKit` is a backend bug here and we surface
    /// it as a decode error. Real StoreKit purchase support arrives with
    /// the App Store-build (deferred).
    private func openCheckout(_ result: CheckoutResult) throws {
        switch result {
        case .web(let url):
            NSWorkspace.shared.open(url)
        case .storeKit:
            throw BackendError.decode
        }
    }
}

