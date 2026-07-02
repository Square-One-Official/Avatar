import Foundation
import XCTest
@testable import AvatarKit

/// E47.1 — fixture-decode-tests per backend-endpoint. De JSON-vormen komen
/// 1:1 uit wat `backend/api/v1/*.ts` daadwerkelijk retourneert (snake_case;
/// de client decodeert via `.convertFromSnakeCase` + `.iso8601`). Zelfde
/// patroon als `MessagingServiceTests.testMessageDecodesBackendShape`, maar
/// dan door de échte `BackendClient`-request-pijplijn heen (URLProtocol-stub)
/// zodat óók de status-→-error-mapping meegetest wordt.
@MainActor
final class BackendClientDecodeTests: XCTestCase {
    private var auth: BackendStubAuth!
    private var client: BackendClient!

    override func setUp() {
        super.setUp()
        BackendStubURLProtocol.reset()
        auth = BackendStubAuth()
        client = BackendClient(auth: auth, session: BackendStubURLProtocol.makeSession())
    }

    override func tearDown() {
        BackendStubURLProtocol.reset()
        BackendClient.resultDownloadSessionOverride = nil
        client = nil
        auth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Stubt de upload-leg die elke image-processing-call vooraf gaat:
    /// POST /v1/cutout/upload-url + de PUT naar de signed Storage-URL.
    private func stubUploadLeg() {
        // Vorm uit backend/api/v1/cutout/upload-url.ts (200-pad).
        BackendStubURLProtocol.setStub(.json(200, """
            {
              "url": "https://storage.example.test/upload/abc123?token=signed",
              "key": "uploads/u1/abc123.png",
              "expires_in": 60
            }
            """), forPath: "/v1/cutout/upload-url")
        BackendStubURLProtocol.setStub(
            .http(status: 200, body: Data()), forPath: "/upload/abc123"
        )
    }

    private func base64(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    // MARK: - GET /v1/account

    func testAccountDecodesBackendShape() async throws {
        // Vorm uit backend/api/v1/account.ts (signed-in, actieve sub).
        BackendStubURLProtocol.setStub(.json(200, """
            {
              "tier": "pro",
              "credits_remaining": 137,
              "monthly_quota": 200,
              "monthly_reset_at": "2026-08-01T00:00:00Z",
              "subscription_status": "active",
              "subscription_renews_at": "2026-08-01T00:00:00Z",
              "free_cutouts_used": 0,
              "free_cutouts_remaining": 3,
              "free_imports_used": 3,
              "free_imports_remaining": 0,
              "needs_account_link": false
            }
            """), forPath: "/v1/account")

        let account = try await client.me()
        XCTAssertEqual(account.tier, .pro)
        XCTAssertEqual(account.creditsRemaining, 137)
        XCTAssertEqual(account.monthlyQuota, 200)
        XCTAssertEqual(account.subscriptionStatus, .active)
        XCTAssertEqual(account.freeImportsRemaining, 0)
        XCTAssertEqual(account.needsAccountLink, false)
        XCTAssertNil(account.isDevUnlimited)
        let expected = ISO8601DateFormatter().date(from: "2026-08-01T00:00:00Z")
        XCTAssertEqual(account.monthlyResetAt, expected)
    }

    func testAccountDevUnlimitedDecodes() async throws {
        // Dev-allowlist-pad uit account.ts: sentinel-quota + is_dev_unlimited.
        BackendStubURLProtocol.setStub(.json(200, """
            {
              "tier": "pro",
              "credits_remaining": 999999,
              "monthly_quota": 999999,
              "monthly_reset_at": null,
              "subscription_status": "active",
              "subscription_renews_at": null,
              "free_cutouts_used": 0,
              "free_cutouts_remaining": 3,
              "free_imports_used": 0,
              "free_imports_remaining": 3,
              "needs_account_link": false,
              "is_dev_unlimited": true
            }
            """), forPath: "/v1/account")

        let account = try await client.me()
        XCTAssertEqual(account.isDevUnlimited, true)
        XCTAssertNil(account.monthlyResetAt)
        XCTAssertEqual(account.creditsRemaining, 999_999)
    }

    // MARK: - POST /v1/import-claim

    func testImportClaimDecodesBackendShape() async throws {
        // Vorm uit backend/api/v1/import-claim.ts (200, free user met ruimte).
        BackendStubURLProtocol.setStub(.json(200, """
            { "allowed": true, "imports_used": 1, "imports_remaining": 2 }
            """), forPath: "/v1/import-claim")

        let claim = try await client.claimImport()
        XCTAssertTrue(claim.allowed)
        XCTAssertEqual(claim.importsUsed, 1)
        XCTAssertEqual(claim.importsRemaining, 2)
        XCTAssertNil(claim.pro)
    }

    func testImportClaimProShortCircuitDecodes() async throws {
        // Pro-pad: sentinel-tellers + pro:true.
        BackendStubURLProtocol.setStub(.json(200, """
            { "allowed": true, "imports_used": 0, "imports_remaining": 3, "pro": true }
            """), forPath: "/v1/import-claim")

        let claim = try await client.claimImport()
        XCTAssertTrue(claim.allowed)
        XCTAssertEqual(claim.pro, true)
    }

    // MARK: - POST /v1/stylize

    func testStylizeDecodesBackendShape() async throws {
        stubUploadLeg()
        // Vorm uit backend/api/v1/stylize.ts (200-pad, incl. dimensies).
        BackendStubURLProtocol.setStub(.json(200, """
            {
              "image": "\(base64("styled-png"))",
              "credits_remaining": 41,
              "model": "google/nano-banana",
              "input_width": 512,
              "input_height": 640,
              "output_width": 1024,
              "output_height": 1280
            }
            """), forPath: "/v1/stylize")

        let result = try await client.stylize(
            imagePNG: Data("input-png".utf8), styleKey: "cartoonify"
        )
        XCTAssertEqual(String(decoding: result.data, as: UTF8.self), "styled-png")
        XCTAssertEqual(result.creditsRemaining, 41)
        XCTAssertEqual(result.dimensions?.inputWidth, 512)
        XCTAssertEqual(result.dimensions?.outputHeight, 1280)
        XCTAssertEqual(result.dimensions?.outputLongEdge, 1280)
    }

    func testStylizeWithoutDimensionsDecodesToNil() async throws {
        stubUploadLeg()
        // Oudere/afwijkende respons zonder maatvelden mag niet breken (A2-les).
        BackendStubURLProtocol.setStub(.json(200, """
            { "image": "\(base64("styled-png"))", "credits_remaining": 40 }
            """), forPath: "/v1/stylize")

        let result = try await client.stylize(
            imagePNG: Data("input-png".utf8), styleKey: "cartoonify"
        )
        XCTAssertNil(result.dimensions)
        XCTAssertEqual(result.creditsRemaining, 40)
    }

    // MARK: - POST /v1/upscale

    func testUpscaleDecodesBackendShape() async throws {
        stubUploadLeg()
        // Vorm uit backend/api/v1/upscale.ts (200-pad).
        BackendStubURLProtocol.setStub(.json(200, """
            { "cutout": "\(base64("upscaled-png"))", "credits_remaining": 39 }
            """), forPath: "/v1/upscale")

        let (data, credits) = try await client.upscale(imagePNG: Data("input-png".utf8))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "upscaled-png")
        XCTAssertEqual(credits, 39)
    }

    // MARK: - POST /v1/colorize

    func testColorizeDecodesBackendShape() async throws {
        stubUploadLeg()
        // Vorm uit backend/api/v1/colorize.ts (200-pad).
        BackendStubURLProtocol.setStub(.json(200, """
            { "cutout": "\(base64("colorized-png"))", "credits_remaining": 38 }
            """), forPath: "/v1/colorize")

        let (data, credits) = try await client.colorize(imagePNG: Data("input-png".utf8))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "colorized-png")
        XCTAssertEqual(credits, 38)
    }

    // MARK: - POST /v1/generate-background

    func testGenerateBackgroundDecodesBackendShape() async throws {
        // Vorm uit backend/api/v1/generate-background.ts (200-pad): het
        // resultaat komt als signed URL (geen inline base64 — Vercel-bodycap),
        // dus de tweede hop loopt via de resultDownload-testseam.
        BackendStubURLProtocol.setStub(.json(200, """
            {
              "image_url": "https://storage.example.test/results/bg.png?token=signed",
              "credits_remaining": 7,
              "model": "google/nano-banana",
              "target_width": 1600,
              "target_height": 900,
              "credits_charged": 2
            }
            """), forPath: "/v1/generate-background")
        BackendStubURLProtocol.setStub(
            .http(status: 200, body: Data("generated-bg-png".utf8)),
            forPath: "/results/bg.png"
        )
        BackendClient.resultDownloadSessionOverride = BackendStubURLProtocol.makeSession()

        let result = try await client.generateBackground(
            userPrompt: "misty forest at dawn",
            styleKey: "photoreal",
            customStyleText: nil,
            viewKey: "wide",
            targetWidth: 1600,
            targetHeight: 900,
            generationModel: "nano-banana"
        )
        XCTAssertEqual(String(decoding: result.imageData, as: UTF8.self), "generated-bg-png")
        XCTAssertEqual(result.creditsRemaining, 7)
    }

    // MARK: - Error-mapping

    func test402MapsToNoCredits() async {
        // 402-vorm uit import-claim.ts; élk endpoint deelt deze mapping in
        // BackendClient.send → dit is dé paywall-trigger.
        BackendStubURLProtocol.setStub(.json(402, """
            { "allowed": false, "imports_used": 3, "imports_remaining": 0 }
            """), forPath: "/v1/import-claim")

        do {
            _ = try await client.claimImport()
            XCTFail("verwachtte BackendError.noCredits")
        } catch BackendError.noCredits {
            // verwacht
        } catch {
            XCTFail("verkeerde fout: \(error)")
        }
    }

    func test403ProRequiredMapsToProRequired() async {
        BackendStubURLProtocol.setStub(.json(403, """
            { "error": "pro_required" }
            """), forPath: "/v1/account")

        do {
            _ = try await client.me()
            XCTFail("verwachtte BackendError.proRequired")
        } catch BackendError.proRequired {
            // verwacht
        } catch {
            XCTFail("verkeerde fout: \(error)")
        }
    }

    func test401MapsToUnauthorized() async {
        BackendStubURLProtocol.setStub(.json(401, """
            { "error": "invalid_token" }
            """), forPath: "/v1/account")

        do {
            _ = try await client.me()
            XCTFail("verwachtte BackendError.unauthorized")
        } catch BackendError.unauthorized {
            // verwacht
        } catch {
            XCTFail("verkeerde fout: \(error)")
        }
    }
}
