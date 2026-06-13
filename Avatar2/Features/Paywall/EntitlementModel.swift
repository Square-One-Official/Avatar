// Paywall/credit-states barebones (E08.3) — entitlementstate + presentatie.
// De checkout-logica is de v1 ProUpgradeSheet-flow via AvatarKit
// (BackendClient.subscribeAnonymous/topup/me); v1's Loc en AppState zijn
// verboden terrein, dus copy is hier Engelstalig hardcoded en de state
// leeft in dit model.

import AppKit
import AvatarKit
import Foundation
import Observation

@MainActor
@Observable
final class EntitlementModel {
    private(set) var account: AccountPayload?

    var isPaywallPresented = false
    /// Op=op-toast (HTTP 402 / credits op): toast eerst, paywall op tik.
    private(set) var isShowingOutOfCreditsToast = false

    /// Jaar als default-anker ("2 months free") — zelfde besluit als v1:
    /// het betere-waardepad is het pad zonder kliks.
    var selectedInterval: SubscriptionInterval = .year
    /// Default op het best-value-pack, zodat één klik op Buy het anker koopt.
    var selectedPack: CreditPack = .credits750

    private(set) var isCheckoutBusy = false
    private(set) var checkoutError: String?

    /// Designbesluit (E05.1): geen quota-druk vóór waarde — de quota-badge
    /// verschijnt pas ná de eerste geslaagde cutout. De import-flow (E05.2+)
    /// roept markFirstCutoutCompleted() aan.
    private static let firstCutoutKey = "shell.firstCutoutDone"
    private(set) var hasCompletedFirstCutout =
        UserDefaults.standard.bool(forKey: firstCutoutKey)

    func markFirstCutoutCompleted() {
        hasCompletedFirstCutout = true
        UserDefaults.standard.set(true, forKey: Self.firstCutoutKey)
    }

    let backend: BackendClient

    /// BackendClient houdt `auth` unowned vast; dit model borgt de levensduur.
    private let auth: AuthService

    init(auth: AuthService) {
        self.auth = auth
        self.backend = BackendClient(auth: auth)
    }

    var isProActive: Bool {
        account?.tier == .pro && account?.subscriptionStatus == .active
    }

    /// Routekeuze in de paywall (v1 `showsTopup`): actieve Pro zonder
    /// credits krijgt de top-up-ladder, ieder ander de subscribe-flow.
    var showsTopup: Bool {
        #if DEBUG
        if debugForceTopup { return true }
        #endif
        return isProActive
    }

    #if DEBUG
    /// Smoke-run-haak (E14.5): forceer de top-up-variant van de paywall.
    var debugForceTopup = false
    #endif

    var creditsRemaining: Int { account?.creditsRemaining ?? 0 }
    var freeImportsRemaining: Int? { account?.freeImportsRemaining }
    var monthlyResetAt: Date? { account?.monthlyResetAt }

    // MARK: - Account-pagina (E15.3)

    var accountEmail: String? { auth.email }
    var isSignedIn: Bool { auth.isSignedIn }
    var planLabel: String { isProActive ? "Pro" : "Starter" }

    func signOutAccount() {
        auth.signOut()
    }

    /// Stripe Customer Portal in de browser ("Manage subscription").
    func openManageSubscription() {
        Task {
            if let url = try? await backend.openPortal() {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Anoniem-vriendelijk: zonder token valt /v1/account terug op de
    /// device-grant-lookup. Offline of fout → state blijft staan.
    func refresh() async {
        if let payload = try? await backend.me() {
            account = payload
        }
    }

    /// Eén opstap voor alle gating: DSGated.onUpgradeRequested en 402-paden.
    func requestUpgrade() {
        checkoutError = nil
        isShowingOutOfCreditsToast = false
        isPaywallPresented = true
    }

    func handleOutOfCredits() {
        isShowingOutOfCreditsToast = true
    }

    func dismissOutOfCreditsToast() {
        isShowingOutOfCreditsToast = false
    }

    // MARK: - Checkout (v1 ProUpgradeSheet-logica via AvatarKit)

    func startSubscribe() async {
        await startCheckout {
            // E14.6: ingelogd → authed flow (gekoppeld aan Supabase user-id,
            // hergebruikt de Stripe-customer; geen dubbele customer). Anoniem
            // → de e-mail-gebaseerde flow.
            if self.auth.isSignedIn {
                return try await self.backend.subscribe(interval: self.selectedInterval)
            }
            return try await self.backend.subscribeAnonymous(interval: self.selectedInterval)
        }
    }

    func startTopup() async {
        await startCheckout {
            try await self.backend.topup(pack: self.selectedPack)
        }
    }

    private func startCheckout(_ request: () async throws -> CheckoutResult) async {
        guard !isCheckoutBusy else { return }
        checkoutError = nil
        isCheckoutBusy = true
        defer { isCheckoutBusy = false }
        do {
            try openCheckout(try await request())
        } catch BackendError.notSignedIn {
            checkoutError = "Sign in first so we can top up the right account."
        } catch let error as BackendError {
            checkoutError = userFacingMessage(for: error)
        } catch {
            checkoutError = "Something went wrong starting checkout. Please try again."
        }
    }

    /// Korte, vriendelijke copy — rauwe servercodes zijn voor het request-log.
    private func userFacingMessage(for error: BackendError) -> String {
        switch error {
        case .server(_, "stripe_unavailable"):    return "Payments are briefly unavailable. Try again in a minute."
        case .server(_, "checkout_init_failed"):  return "Couldn't start checkout. Please try again."
        case .server(_, "pricing_misconfigured"): return "Pricing is being updated. Try again shortly."
        case .rateLimited:                        return "Too many attempts. Give it a moment."
        case .transport:                          return "You appear to be offline. Check your connection."
        default:                                  return "Something went wrong starting checkout. Please try again."
        }
    }

    private func openCheckout(_ result: CheckoutResult) throws {
        switch result {
        case .web(let url):
            // Stripe Checkout in de browser; terugkeer via aaavatar://
            // stripe-return (URL-scheme staat al op het Avatar2-target).
            NSWorkspace.shared.open(url)
            isPaywallPresented = false
        case .storeKit:
            // DMG-pad. Het StoreKit-pad hoort bij een latere MAS-story.
            throw BackendError.decode
        }
    }
}
