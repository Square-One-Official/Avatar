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

    /// Remote feature flags (E33+). Default = allEnabled zodat de app nooit
    /// kapot gaat als de CMS onbereikbaar is bij startup.
    private(set) var featureFlags: RemoteFeatureFlags = .allEnabled

    var isPaywallPresented = false
    /// Op=op-toast (HTTP 402 / credits op): toast eerst, paywall op tik.
    private(set) var isShowingOutOfCreditsToast = false

    /// E18.3: generieke fout-toast voor cloud-acties (Effects/Hair/Clothing/
    /// Boost) i.p.v. inline tekst onder de menutitel.
    private(set) var errorToast: String?

    /// Lopende cloud-actie-toast — statische titel + cycling copy per feature.
    struct WorkingContext {
        let title: String
        let messages: [String]
    }
    private(set) var workingContext: WorkingContext?

    /// E18.2: contextuele cloud-feature-gate. nil = niets te tonen.
    enum CloudGate: Equatable { case signIn }
    var cloudGate: CloudGate?

    /// Privacy Tier Picker: elevation modal wanneer feature hogere tier vereist.
    var privacyElevation: PrivacyElevationRequest?
    /// Deep-link naar Settings (ShellView opent deze pagina).
    var openSettingsPage: SettingsPage?

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

    /// `backendSession` is de E47.1-testseam: tests injecteren een
    /// URLProtocol-stub-sessie zodat elke backend-call stubbaar is. De
    /// default is exact wat `BackendClient` zelf zou kiezen — geen
    /// gedragsverandering voor bestaande call sites.
    init(auth: AuthService, backendSession: URLSession = TLSPinning.pinnedShared) {
        self.auth = auth
        self.backend = BackendClient(auth: auth, session: backendSession)
        auth.onSignedIn = { [weak self] in
            Task { await self?.refresh() }
        }
        #if DEBUG
        // Smoke-run-haak (E15.5): zet de dev-vlag vóór de first render i.p.v.
        // in een .task — twee post-render state-writes in hetzelfde frame
        // (deze + ShellView's --show-settings) wedgen het hiddenTitleBar-
        // venster. Een echt dev-account heeft de vlag óók al bij first render.
        if ProcessInfo.processInfo.arguments.contains("--dev-advanced") {
            debugForceDevUnlimited = true
        }
        #endif
    }

    var isProActive: Bool {
        // Spiegelt v1 `ProEntitlement.isPro` (tier != nil) én de server-
        // short-circuit in /v1/import-claim (`if (sub)` — past_due telt mee).
        // Alleen `.active` eisen maakte grace-period (`.lapsed`) onterecht Starter.
        account?.tier == .pro
    }

    /// Top-up-ladder in de paywall: alleen bij actief betaald abonnement.
    var showsTopupRoute: Bool {
        isProActive && account?.subscriptionStatus == .active
    }

    /// E15.5: dev-allowlisted account → toont de Advanced model-picker.
    var isDevUnlimited: Bool {
        #if DEBUG
        if debugForceDevUnlimited { return true }
        #endif
        return account?.isDevUnlimited ?? false
    }

    #if DEBUG
    /// Smoke-run-haak (E15.5): forceer de Advanced-sectie zichtbaar.
    var debugForceDevUnlimited = false
    #endif

    /// Routekeuze in de paywall (v1 `showsTopup`): actieve Pro zonder
    /// credits krijgt de top-up-ladder, ieder ander de subscribe-flow.
    var showsTopup: Bool {
        #if DEBUG
        if debugForceTopup { return true }
        #endif
        return showsTopupRoute
    }

    #if DEBUG
    /// Smoke-run-haak (E14.5): forceer de top-up-variant van de paywall.
    var debugForceTopup = false
    #endif

    var creditsRemaining: Int { account?.creditsRemaining ?? 0 }
    /// Maand-grant van het Pro-plan — het totaal voor de "X left of Y"-teller
    /// in de topbar. Backend is bron; valt terug op de plan-default (200)
    /// zowel vóór het laden als wanneer de backend 0 stuurt (anders zou de
    /// teller terugvallen op de kale balans).
    var monthlyQuota: Int {
        let q = account?.monthlyQuota ?? 0
        return q > 0 ? q : ProTier.pro.monthlyCredits
    }
    var freeImportsRemaining: Int? { account?.freeImportsRemaining }
    var monthlyResetAt: Date? { account?.monthlyResetAt }

    /// 14.7 (audit B8): de refill-datum, maar alléén als hij in de toekomst
    /// ligt. `subscriptions.current_period_end` kan server-side stale raken
    /// (gemiste Stripe-webhook-delivery) — een datum in het verleden is dan
    /// een leugen ("Refills on 4 Jun 2026"). De UI valt in dat geval terug
    /// op periodloze copy ("Refills monthly with your plan").
    var upcomingMonthlyResetAt: Date? {
        guard let reset = monthlyResetAt, reset > .now else { return nil }
        return reset
    }

    /// Aftellende quota-tekst ("X left of Y" / "N credits") — één bron voor de
    /// topbar én de left-nav (PoC). Pro: resterende credits over de maand-grant;
    /// top-ups stapelen erbovenop (geen vaste noemer) → kale balans. Free: rest
    /// van de lifetime-cap.
    var quotaSummary: String {
        if isProActive {
            let quota = monthlyQuota
            if quota > 0, creditsRemaining <= quota {
                return "\(creditsRemaining) left of \(quota)"
            }
            return "\(creditsRemaining) credits"
        }
        if let free = freeImportsRemaining {
            let remaining = max(0, min(FreeTier.maxPortraits, free))
            return "\(remaining) left of \(FreeTier.maxPortraits)"
        }
        return ""
    }

    // MARK: - Account-pagina (E15.3)

    var accountEmail: String? { auth.email }
    var isSignedIn: Bool { auth.isSignedIn }
    var planLabel: String { isProActive ? "Pro" : "Starter" }

    func signOutAccount() {
        auth.signOut()
        account = nil
    }

    // MARK: - Delete account (E15.7, audit C7 — GDPR art. 17)

    /// Loopt zolang de server-side wipe bezig is (disable de rij-knop).
    private(set) var isDeletingAccount = false

    /// Verwijdert het account definitief via `/v1/account/delete` (cancelt
    /// Stripe-subs, wist de Supabase-user) en logt bij succes lokaal uit.
    /// De lokale bibliotheek (portretten/banners op deze Mac) blijft bewust
    /// staan — die is van de gebruiker, niet van het account.
    /// Faalt de wipe, dan blijft de sessie intact en meldt de fout-toast dat
    /// een retry veilig is (het endpoint is idempotent).
    @discardableResult
    func deleteAccount() async -> Bool {
        guard !isDeletingAccount else { return false }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await backend.deleteAccount()
            signOutAccount()
            return true
        } catch {
            presentError("Couldn't delete your account. Please try again — nothing was left half-deleted.")
            return false
        }
    }

    // MARK: - Sign-in (E18.1) — e-mail + OTP vanuit Account/gate
    var authBusy: Bool { auth.isBusy }
    var authError: String? { auth.lastError }

    /// E18.21: wis de auth-fout (nadat de toast 'm getoond heeft / bij stap-wissel).
    func dismissAuthError() {
        auth.clearError()
    }

    /// Stap 1: Supabase mailt een OTP-code naar dit adres.
    func sendSignInCode(_ email: String) async {
        try? await auth.requestCode(email: email)
    }

    /// Stap 2: verifieer de code; bij succes ververst het account (plan/credits).
    @discardableResult
    func verifySignInCode(_ email: String, code: String) async -> Bool {
        do {
            try await auth.verifyCode(email: email, code: code)
        } catch {
            return false
        }
        await refresh()
        return true
    }

    /// Stripe Customer Portal in de browser ("Manage subscription").
    func openManageSubscription() {
        Task {
            if let url = try? await backend.openPortal(), url.isAllowedExternalScheme {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Anoniem-vriendelijk: zonder token valt /v1/account terug op de
    /// device-grant-lookup. Offline of fout → state blijft staan.
    func refresh() async {
        async let accountFetch = backend.me()
        async let flagsFetch = backend.featureFlags()
        if let payload = try? await accountFetch {
            account = payload
        }
        if let flags = try? await flagsFetch {
            featureFlags = flags
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

    // MARK: - E18.3 fout-toast

    /// E44.1 (audit B2/B3): auto-dismiss-duur van de fout-toast. 4s was
    /// makkelijk te missen — een gemiste colorise-fout oogde live als "er
    /// gebeurt niets". Een échte fout moet minimaal 8s leesbaar blijven
    /// (plan-DoD). Constante hier (niet inline in `Avatar2App`) zodat de
    /// ondergrens testbaar is.
    static let errorToastDuration: Duration = .seconds(8)

    func presentError(_ message: String) {
        errorToast = message
    }

    func dismissErrorToast() {
        errorToast = nil
    }

    /// E44.2 (audit B2): zichtbaar faalpad voor een geslaagde server-call
    /// (HTTP 200) waarvan de bytes niet tot een afbeelding decoderen. De
    /// server kan op dat pad al een credit hebben afgeschreven, dus naast de
    /// fout-toast hoort er een `refresh()` zodat het saldo in de QuotaBadge
    /// klopt — het stille `guard … else { return }`-pad produceerde alle
    /// Colorise-symptomen tegelijk (geen resultaat, geen zichtbare fout,
    /// saldo lijkt onveranderd terwijl er wél afgeschreven kan zijn).
    func presentCloudResultFailure(_ message: String) async {
        presentError(message)
        await refresh()
    }

    func presentWorking(title: String, messages: [String]) {
        workingContext = WorkingContext(title: title, messages: messages)
    }

    func dismissWorkingToast() {
        workingContext = nil
    }

    // MARK: - Privacy Tier Picker gate

    /// Mag een AI-feature draaien? Zo niet: elevation modal, sign-in of paywall.
    @discardableResult
    func allowAIFeature(_ feature: AIFeature) -> Bool {
        switch PrivacyGate.evaluate(feature, entitlement: self) {
        case .allowed:
            return true
        case .needsElevation(requiredTier: let tier, feature: let feature):
            privacyElevation = PrivacyElevationRequest(feature: feature, requiredTier: tier)
            return false
        case .needsSignIn:
            cloudGate = .signIn
            return false
        case .needsCredits:
            requestUpgrade()
            return false
        }
    }

    func dismissPrivacyElevation() {
        privacyElevation = nil
    }

    func openPrivacySettings() {
        privacyElevation = nil
        openSettingsPage = .aiModels
    }

    func dismissCloudGate() {
        cloudGate = nil
    }

    /// E14.2: free-tier importgate (3 lifetime-afbeeldingen, source-agnostic).
    /// Roept de atomic server-claim aan vóór elke import; Pro short-circuit
    /// `allowed`. Niet toegestaan (cap bereikt / 402) → paywall + false.
    /// Een netwerk-/transportfout blokkeert niet (de gebruiker mag offline
    /// niet vastlopen; de cloud-cutout dwingt server-side alsnog af) → true.
    func claimImport() async -> Bool {
        #if DEBUG
        // Smoke-runs (`--smoke-store` e.d.) draaien op een geïsoleerde store maar
        // delen het echte account; deze bypass houdt de gate uit de flow-smokes
        // zonder server-claims te verbruiken.
        if ProcessInfo.processInfo.arguments.contains("--bypass-import-gate") {
            return true
        }
        #endif
        do {
            let resp = try await backend.claimImport()
            if !resp.allowed {
                requestUpgrade()
                return false
            }
            // Bijgewerkte teller meteen zichtbaar in de QuotaBadge.
            await refresh()
            return true
        } catch BackendError.noCredits {
            requestUpgrade()
            return false
        } catch {
            return true
        }
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
            // stripe-return (URL-scheme staat al op het Avatar2-target). Guard
            // het scheme zodat alleen web-/eigen-scheme-URL's geopend worden.
            guard url.isAllowedExternalScheme else { throw BackendError.decode }
            NSWorkspace.shared.open(url)
            isPaywallPresented = false
        case .storeKit:
            // DMG-pad. Het StoreKit-pad hoort bij een latere MAS-story.
            throw BackendError.decode
        }
    }
}
