import AvatarKit
import Foundation
import XCTest
@testable import Avatar2

/// E47.2 — testsuite voor de monetisatie-kern (`EntitlementModel`). Gebruikt
/// de E47.1-seam: een URLProtocol-stub-sessie gaat via `init(auth:
/// backendSession:)` de `BackendClient` in, zodat élke backend-call
/// (import-claim, account, feature-flags) per test stubbaar is. Fixtures
/// spiegelen de echte responsvormen uit `backend/api/v1/*.ts`.
@MainActor
final class EntitlementModelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        EntitlementStubURLProtocol.reset()
    }

    override func tearDown() {
        EntitlementStubURLProtocol.reset()
        super.tearDown()
    }

    private func makeModel() -> EntitlementModel {
        EntitlementModel(auth: AuthService(), backendSession: EntitlementStubURLProtocol.makeSession())
    }

    /// Vorm uit backend/api/v1/account.ts; alleen de velden die per test
    /// variëren zijn parameters. Free-tier krijgt `tier: null` — precies wat
    /// `mapTierForClient` serverzijde doet.
    private func accountJSON(
        tier: String = "free",
        credits: Int = 0,
        freeImportsRemaining: Int = 3,
        devUnlimited: Bool = false,
        monthlyResetAt: Date? = nil,
        subscriptionStatus: String? = nil
    ) -> String {
        let status = subscriptionStatus ?? (tier == "pro" ? "active" : "none")
        return """
        {
          "tier": \(tier == "pro" ? "\"pro\"" : "null"),
          "credits_remaining": \(credits),
          "monthly_quota": \(tier == "pro" ? 200 : 0),
          "monthly_reset_at": \(monthlyResetAt.map { "\"\(ISO8601DateFormatter().string(from: $0))\"" } ?? "null"),
          "subscription_status": "\(status)",
          "subscription_renews_at": null,
          "free_cutouts_used": 0,
          "free_cutouts_remaining": 3,
          "free_imports_used": \(3 - freeImportsRemaining),
          "free_imports_remaining": \(freeImportsRemaining),
          "needs_account_link": false\(devUnlimited ? ",\n  \"is_dev_unlimited\": true" : "")
        }
        """
    }

    /// Grace-period (past_due → `lapsed`) telt als Pro — zelfde als v1
    /// `ProEntitlement.isPro` en server-side import-claim short-circuit.
    func testLapsedProTierCountsAsProActive() async {
        EntitlementStubURLProtocol.setStub(
            .json(200, accountJSON(tier: "pro", credits: 12, subscriptionStatus: "lapsed")),
            forPath: "/v1/account"
        )
        EntitlementStubURLProtocol.setStub(.json(200, allFlagsOnJSON), forPath: "/v1/feature-flags")
        let model = makeModel()

        await model.refresh()

        XCTAssertTrue(model.isProActive)
        XCTAssertFalse(model.showsTopup, "top-up alleen bij actief abonnement")
    }

    private let allFlagsOnJSON = """
        {
          "effects_enabled": true,
          "hair_enabled": true,
          "clothes_enabled": true,
          "face_enabled": true,
          "backgrounds_enabled": true
        }
        """

    // MARK: - Free-cap / paywall-routing

    /// Free-cap bereikt: de server weigert de claim (defensief 200-pad met
    /// `allowed:false`) → geen import, paywall open.
    func testClaimImportDeniedAtFreeCapRoutesToPaywall() async {
        EntitlementStubURLProtocol.setStub(.json(200, """
            { "allowed": false, "imports_used": 3, "imports_remaining": 0 }
            """), forPath: "/v1/import-claim")
        let model = makeModel()

        let allowed = await model.claimImport()

        XCTAssertFalse(allowed)
        XCTAssertTrue(model.isPaywallPresented)
    }

    /// Het échte productiepad voor de cap: HTTP 402 → `BackendError.noCredits`
    /// → paywall. (import-claim.ts stuurt 402 zodra een teller op de cap zit.)
    func testClaimImport402RoutesToPaywall() async {
        EntitlementStubURLProtocol.setStub(.json(402, """
            { "allowed": false, "imports_used": 3, "imports_remaining": 0 }
            """), forPath: "/v1/import-claim")
        let model = makeModel()

        let allowed = await model.claimImport()

        XCTAssertFalse(allowed)
        XCTAssertTrue(model.isPaywallPresented)
        // requestUpgrade ruimt de op=op-toast op zodra de paywall opent.
        XCTAssertFalse(model.isShowingOutOfCreditsToast)
    }

    /// Toegestane claim ververst meteen account + teller (QuotaBadge).
    func testClaimImportAllowedRefreshesAccount() async {
        EntitlementStubURLProtocol.setStub(.json(200, """
            { "allowed": true, "imports_used": 1, "imports_remaining": 2 }
            """), forPath: "/v1/import-claim")
        EntitlementStubURLProtocol.setStub(
            .json(200, accountJSON(freeImportsRemaining: 2)), forPath: "/v1/account"
        )
        EntitlementStubURLProtocol.setStub(.json(200, allFlagsOnJSON), forPath: "/v1/feature-flags")
        let model = makeModel()

        let allowed = await model.claimImport()

        XCTAssertTrue(allowed)
        XCTAssertFalse(model.isPaywallPresented)
        XCTAssertEqual(model.freeImportsRemaining, 2)
        XCTAssertEqual(model.quotaSummary, "2 left of \(FreeTier.maxPortraits)")
    }

    /// Offline/transportfout mag een import nooit blokkeren — de cloud-kant
    /// dwingt de cap server-side alsnog af.
    func testClaimImportTransportErrorDoesNotBlock() async {
        EntitlementStubURLProtocol.setStub(
            .failure(URLError(.notConnectedToInternet)), forPath: "/v1/import-claim"
        )
        let model = makeModel()

        let allowed = await model.claimImport()

        XCTAssertTrue(allowed)
        XCTAssertFalse(model.isPaywallPresented)
    }

    // MARK: - Dev-unlimited override

    /// `is_dev_unlimited` uit /v1/account zet de Advanced-override aan;
    /// zonder account-payload staat hij uit.
    func testDevUnlimitedFollowsAccountPayload() async {
        EntitlementStubURLProtocol.setStub(
            .json(200, accountJSON(tier: "pro", credits: 999_999, devUnlimited: true)),
            forPath: "/v1/account"
        )
        EntitlementStubURLProtocol.setStub(.json(200, allFlagsOnJSON), forPath: "/v1/feature-flags")
        let model = makeModel()

        XCTAssertFalse(model.isDevUnlimited, "zonder account-payload geen dev-override")
        await model.refresh()
        XCTAssertTrue(model.isDevUnlimited)
        XCTAssertTrue(model.isProActive)
    }

    // MARK: - Feature-flags

    /// CMS onbereikbaar (500) → flags blijven op de allEnabled-fallback en
    /// het account-deel van refresh() blijft gewoon werken.
    func testFeatureFlagsFetchFailureFallsBackToAllEnabled() async {
        EntitlementStubURLProtocol.setStub(
            .json(500, #"{ "error": "cms_unreachable" }"#), forPath: "/v1/feature-flags"
        )
        EntitlementStubURLProtocol.setStub(
            .json(200, accountJSON(tier: "pro", credits: 12)), forPath: "/v1/account"
        )
        let model = makeModel()

        await model.refresh()

        XCTAssertTrue(model.featureFlags.effectsEnabled)
        XCTAssertTrue(model.featureFlags.hairEnabled)
        XCTAssertTrue(model.featureFlags.clothesEnabled)
        XCTAssertTrue(model.featureFlags.faceEnabled)
        XCTAssertTrue(model.featureFlags.backgroundsEnabled)
        XCTAssertEqual(model.creditsRemaining, 12, "account-fetch mag niet meesneuvelen")
    }

    /// Een geslaagde flags-fetch overschrijft de fallback wél.
    func testFeatureFlagsFetchAppliesRemoteValues() async {
        EntitlementStubURLProtocol.setStub(.json(200, """
            {
              "effects_enabled": true,
              "hair_enabled": false,
              "clothes_enabled": false,
              "face_enabled": true,
              "backgrounds_enabled": true
            }
            """), forPath: "/v1/feature-flags")
        EntitlementStubURLProtocol.setStub(.json(200, accountJSON()), forPath: "/v1/account")
        let model = makeModel()

        await model.refresh()

        XCTAssertTrue(model.featureFlags.effectsEnabled)
        XCTAssertFalse(model.featureFlags.hairEnabled)
        XCTAssertFalse(model.featureFlags.clothesEnabled)
    }

    // MARK: - Refill-datum-guard (14.7, audit B8)

    /// Een stale `current_period_end` in het verleden (gemiste webhook-
    /// delivery) mag nooit als refill-datum de UI in — "Refills on 4 Jun
    /// 2026" was het productie-symptoom.
    func testMonthlyResetInPastIsNotUpcoming() async {
        let past = Date(timeIntervalSinceNow: -14 * 86_400)
        EntitlementStubURLProtocol.setStub(
            .json(200, accountJSON(tier: "pro", credits: 42, monthlyResetAt: past)),
            forPath: "/v1/account"
        )
        EntitlementStubURLProtocol.setStub(.json(200, allFlagsOnJSON), forPath: "/v1/feature-flags")
        let model = makeModel()

        await model.refresh()

        XCTAssertNotNil(model.monthlyResetAt, "de rauwe datum blijft beschikbaar")
        XCTAssertNil(model.upcomingMonthlyResetAt, "verleden-datum → geen refill-datum in de UI")
    }

    /// Een toekomstige refill-datum passeert de guard ongewijzigd.
    func testMonthlyResetInFutureIsUpcoming() async {
        let future = Date(timeIntervalSinceNow: 14 * 86_400)
        EntitlementStubURLProtocol.setStub(
            .json(200, accountJSON(tier: "pro", credits: 42, monthlyResetAt: future)),
            forPath: "/v1/account"
        )
        EntitlementStubURLProtocol.setStub(.json(200, allFlagsOnJSON), forPath: "/v1/feature-flags")
        let model = makeModel()

        await model.refresh()

        let upcoming = try? XCTUnwrap(model.upcomingMonthlyResetAt)
        XCTAssertNotNil(upcoming)
        // ISO8601-roundtrip kapt subseconden af (truncatie, geen afronding) —
        // trunceer dus beide kanten; .rounded() flakete bij fractie ≥ 0.5.
        XCTAssertEqual(
            upcoming.map { $0.timeIntervalSince1970.rounded(.down) },
            future.timeIntervalSince1970.rounded(.down)
        )
    }

    // MARK: - Delete account (15.7, audit C7)

    /// Faalt de server-side wipe (5xx uit delete.ts) of ontbreekt de sessie,
    /// dan blijft er geen halve state achter: geen sign-out, wél een
    /// fout-toast zodat de gebruiker weet dat een retry veilig is. Het
    /// succes-pad (header/method/response-contract) zit in AvatarKitTests →
    /// BackendClientDecodeTests; hier kan de sessie niet geforceerd worden
    /// (AuthService.accessToken is private(set), echte Supabase-flow).
    func testDeleteAccountFailureKeepsStateAndShowsErrorToast() async {
        EntitlementStubURLProtocol.setStub(.json(500, """
            { "deleted": false, "scope": { "errors": ["auth_delete: boom"] } }
            """), forPath: "/v1/account/delete")
        let model = makeModel()

        let deleted = await model.deleteAccount()

        XCTAssertFalse(deleted)
        XCTAssertNotNil(model.errorToast, "fout moet zichtbaar zijn (toast)")
        XCTAssertFalse(model.isDeletingAccount, "busy-vlag moet terugvallen")
    }

    // MARK: - Credits-refresh na gefaalde cloud-actie

    /// Het 402-pad van een cloud-actie (Effects/Hair/Boost): toast eerst,
    /// daarna haalt refresh() het geslonken saldo op zodat de teller klopt.
    func testCreditsRefreshAfterFailedCloudAction() async {
        EntitlementStubURLProtocol.setStub(
            .json(200, accountJSON(tier: "pro", credits: 5)), forPath: "/v1/account"
        )
        EntitlementStubURLProtocol.setStub(.json(200, allFlagsOnJSON), forPath: "/v1/feature-flags")
        let model = makeModel()
        await model.refresh()
        XCTAssertEqual(model.creditsRemaining, 5)

        // Cloud-actie faalt met 402 → call site meldt het via handleOutOfCredits.
        model.handleOutOfCredits()
        XCTAssertTrue(model.isShowingOutOfCreditsToast)

        // De backend is inmiddels de bron van het nieuwe saldo.
        EntitlementStubURLProtocol.setStub(
            .json(200, accountJSON(tier: "pro", credits: 0)), forPath: "/v1/account"
        )
        await model.refresh()
        XCTAssertEqual(model.creditsRemaining, 0)

        // Tik op de toast → paywall; toast weg.
        model.requestUpgrade()
        XCTAssertTrue(model.isPaywallPresented)
        XCTAssertFalse(model.isShowingOutOfCreditsToast)
    }

    // MARK: - E44.1/44.2 — cloud-actie foutafhandeling (audit B2/B3)

    /// E44.1: een échte fout-toast moet minimaal 8 seconden leesbaar blijven.
    /// De 4s-auto-dismiss maakte een colorise-fout onzichtbaar ("er gebeurt
    /// niets"). `Avatar2App` leest deze constante; de test borgt de ondergrens.
    func testErrorToastStaysVisibleAtLeastEightSeconds() {
        XCTAssertGreaterThanOrEqual(
            EntitlementModel.errorToastDuration, .seconds(8),
            "fout-toasts moeten ≥ 8s zichtbaar blijven (E44.1-DoD)"
        )
    }

    // MARK: - UXS-2 — toast-prioriteit (UX4)

    /// Er is één toast-slot. Een fout moet een lopende working-toast verdringen:
    /// de operatie waar die spinner bij hoorde is juist mislukt, dus de spinner
    /// laten winnen betekent dat de gebruiker de fout nooit ziet.
    func testErrorOutranksWorkingToast() {
        let working = EntitlementModel.WorkingContext(title: "Applying style", messages: ["…"])

        XCTAssertEqual(
            EntitlementModel.resolveToast(error: "boom", outOfCredits: false, working: working),
            .error("boom")
        )
        XCTAssertEqual(
            EntitlementModel.resolveToast(error: "boom", outOfCredits: true, working: working),
            .error("boom")
        )
    }

    /// Zonder fout blijft de bestaande volgorde staan: op-is-op vóór bezig.
    func testToastPriorityBelowError() {
        let working = EntitlementModel.WorkingContext(title: "Applying style", messages: ["…"])

        XCTAssertEqual(
            EntitlementModel.resolveToast(error: nil, outOfCredits: true, working: working),
            .outOfCredits
        )
        XCTAssertEqual(
            EntitlementModel.resolveToast(error: nil, outOfCredits: false, working: working),
            .working(working)
        )
        XCTAssertNil(
            EntitlementModel.resolveToast(error: nil, outOfCredits: false, working: nil)
        )
    }

    /// De reducer hangt aan het model, niet alleen aan losse argumenten.
    func testActiveToastFollowsModelState() {
        let model = EntitlementModel(auth: AuthService())
        XCTAssertNil(model.activeToast)

        model.presentWorking(title: "Applying style", messages: ["…"])
        XCTAssertEqual(
            model.activeToast,
            .working(EntitlementModel.WorkingContext(title: "Applying style", messages: ["…"]))
        )

        model.presentError("boom")
        XCTAssertEqual(model.activeToast, .error("boom"), "een fout verdringt de spinner")

        model.dismissErrorToast()
        XCTAssertEqual(
            model.activeToast,
            .working(EntitlementModel.WorkingContext(title: "Applying style", messages: ["…"])),
            "na het wegklikken van de fout hoort de lopende actie weer zichtbaar te zijn"
        )
    }

    /// Niet-kritieke meldingen delen één duur-constante i.p.v. losse literals.
    func testInfoToastDurationIsShorterThanErrorDuration() {
        XCTAssertLessThan(EntitlementModel.infoToastDuration, EntitlementModel.errorToastDuration)
        XCTAssertGreaterThanOrEqual(EntitlementModel.infoToastDuration, .seconds(4))
    }

    /// E44.2: een 200-response met onbruikbare bytes (guard-pad in
    /// EditorView's Boost/Colorise/Fill-in-body) moet een zichtbare fout
    /// tonen ÉN het saldo verversen — de server kan op dat pad al een credit
    /// hebben afgeschreven.
    func testPresentCloudResultFailureShowsToastAndRefreshesBalance() async {
        EntitlementStubURLProtocol.setStub(
            .json(200, accountJSON(tier: "pro", credits: 7)), forPath: "/v1/account"
        )
        EntitlementStubURLProtocol.setStub(.json(200, allFlagsOnJSON), forPath: "/v1/feature-flags")
        let model = makeModel()

        await model.presentCloudResultFailure("Couldn't colorise this portrait. Please try again.")

        XCTAssertEqual(
            model.errorToast, "Couldn't colorise this portrait. Please try again.",
            "guard-pad moet een zichtbare fout opleveren, geen stil return"
        )
        XCTAssertEqual(
            model.creditsRemaining, 7,
            "saldo moet ná de fout meteen vers van de server komen"
        )
    }

    /// E44.2 offline-variant: faalt de refresh (transportfout), dan blijft
    /// de fout-toast gewoon staan — refresh() slikt zijn eigen fouten.
    func testPresentCloudResultFailureKeepsToastWhenRefreshFails() async {
        EntitlementStubURLProtocol.setStub(
            .failure(URLError(.notConnectedToInternet)), forPath: "/v1/account"
        )
        EntitlementStubURLProtocol.setStub(
            .failure(URLError(.notConnectedToInternet)), forPath: "/v1/feature-flags"
        )
        let model = makeModel()

        await model.presentCloudResultFailure("Couldn't boost the resolution. Please try again.")

        XCTAssertEqual(model.errorToast, "Couldn't boost the resolution. Please try again.")
    }
}

// MARK: - Stub-infra (kopie van AvatarKit's BackendStubURLProtocol — test-
// helpers zijn niet deelbaar tussen een SwiftPM-testtarget en Avatar2Tests)

/// URLProtocol-stub: beantwoordt elke request van de geïnjecteerde sessie
/// via een pad-gebaseerde routetabel.
final class EntitlementStubURLProtocol: URLProtocol {
    enum Stub {
        case http(status: Int, body: Data)
        case failure(Error)

        static func json(_ status: Int, _ json: String) -> Stub {
            .http(status: status, body: Data(json.utf8))
        }
    }

    nonisolated(unsafe) private static var routes: [String: Stub] = [:]
    private static let lock = NSLock()

    static func setStub(_ stub: Stub, forPath path: String) {
        lock.lock(); defer { lock.unlock() }
        routes[path] = stub
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        routes = [:]
    }

    private static func stub(forPath path: String) -> Stub? {
        lock.lock(); defer { lock.unlock() }
        return routes[path]
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EntitlementStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let stub = Self.stub(forPath: url.path) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch stub {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .http(let status, let body):
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
