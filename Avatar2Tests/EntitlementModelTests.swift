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
        devUnlimited: Bool = false
    ) -> String {
        """
        {
          "tier": \(tier == "pro" ? "\"pro\"" : "null"),
          "credits_remaining": \(credits),
          "monthly_quota": \(tier == "pro" ? 200 : 0),
          "monthly_reset_at": null,
          "subscription_status": "\(tier == "pro" ? "active" : "none")",
          "subscription_renews_at": null,
          "free_cutouts_used": 0,
          "free_cutouts_remaining": 3,
          "free_imports_used": \(3 - freeImportsRemaining),
          "free_imports_remaining": \(freeImportsRemaining),
          "needs_account_link": false\(devUnlimited ? ",\n  \"is_dev_unlimited\": true" : "")
        }
        """
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
