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

    // E32.4: face-edits sturen `preserve_framing` mee, net als hair/clothes —
    // zonder de framing-clausule herkadreerde nano-banana soms, waarna de
    // client bij ≥2% ratio-drift de transform reset ("beeld verandert van
    // formaat"). Deze test pint de request-body van `editFace`.
    func testEditFaceSendsPreserveFramingAndPreset() async throws {
        stubUploadLeg()
        BackendStubURLProtocol.setStub(.json(200, """
            { "image": "\(base64("edited-png"))", "credits_remaining": 37 }
            """), forPath: "/v1/stylize")

        _ = try await client.editFace(
            imagePNG: Data("input-png".utf8), presetKey: "whiten-teeth"
        )

        let stylizeRequest = BackendStubURLProtocol.requestLog.last {
            $0.url?.path == "/v1/stylize"
        }
        let body = try XCTUnwrap(stylizeRequest.flatMap(bodyData(of:)))
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["face_preset"] as? String, "whiten-teeth")
        XCTAssertEqual(json["preserve_framing"] as? Bool, true)
        XCTAssertNil(json["style"])
        XCTAssertNil(json["hair_preset"])
    }

    /// URLSession levert een POST-body bij de URLProtocol als stream aan;
    /// deze helper leest 'm terug naar Data voor body-asserties.
    private func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
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

    // E41.5: de high-tier gaat over hetzelfde endpoint (alleen `quality` in de
    // body verschilt) en mapt op het 3-credits-tarief.
    func testUpscaleHighQualityTier() async throws {
        stubUploadLeg()
        BackendStubURLProtocol.setStub(.json(200, """
            { "cutout": "\(base64("upscaled-hi-png"))", "credits_remaining": 36 }
            """), forPath: "/v1/upscale")

        let (data, credits) = try await client.upscale(
            imagePNG: Data("input-png".utf8), quality: .high
        )
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "upscaled-hi-png")
        XCTAssertEqual(credits, 36)
        XCTAssertEqual(BackendClient.UpscaleQuality.high.creditAction, .upscaleHigh)
        XCTAssertEqual(BackendClient.UpscaleQuality.regular.creditAction, .upscale)
        XCTAssertEqual(BackendClient.UpscaleQuality.high.rawValue, "high")
        XCTAssertEqual(BackendClient.UpscaleQuality.regular.rawValue, "regular")
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

    // MARK: - GET /v1/feature-flags

    func testFeatureFlagsDecodesBackendShape() async throws {
        // Vorm uit backend/api/v1/feature-flags.ts. Deze test ving de
        // dubbele-mapping-bug: expliciete snake_case-CodingKeys bovenop
        // .convertFromSnakeCase lieten élke decode falen → app bleef stil
        // op de allEnabled-fallback (fix: E47.2).
        BackendStubURLProtocol.setStub(.json(200, """
            {
              "effects_enabled": true,
              "hair_enabled": false,
              "clothes_enabled": true,
              "face_enabled": false,
              "backgrounds_enabled": true
            }
            """), forPath: "/v1/feature-flags")

        let flags = try await client.featureFlags()
        XCTAssertTrue(flags.effectsEnabled)
        XCTAssertFalse(flags.hairEnabled)
        XCTAssertTrue(flags.clothesEnabled)
        XCTAssertFalse(flags.faceEnabled)
        XCTAssertTrue(flags.backgroundsEnabled)
    }

    // MARK: - GET /v1/banner-presets (E39.1)

    func testBannerPresetsDecodesBackendShape() async throws {
        // Vorm uit backend/api/v1/banner-presets.ts (200-pad): snake_case-
        // envelope `banner_presets` + per item key/label/category/
        // thumbnail_url/config/order. `config` is een opake JSON-string die
        // de app zelf naar `BannerLayers` decodeert.
        BackendStubURLProtocol.setStub(.json(200, """
            {
              "banner_presets": [
                {
                  "key": "mesh-sunset",
                  "label": "Sunset",
                  "category": "mesh",
                  "thumbnail_url": "https://cdn.example.test/banners/mesh-sunset.png",
                  "config": "{\\"fill\\":{\\"kind\\":\\"meshGradient\\"}}",
                  "order": 1
                },
                {
                  "key": "solid-ink",
                  "label": "Ink",
                  "category": "solid",
                  "thumbnail_url": null,
                  "config": "{\\"fill\\":{\\"kind\\":\\"solid\\"}}",
                  "order": 2
                }
              ]
            }
            """), forPath: "/v1/banner-presets")

        let presets = try await client.bannerPresets()
        XCTAssertEqual(presets.count, 2)
        let first = try XCTUnwrap(presets.first)
        XCTAssertEqual(first.key, "mesh-sunset")
        XCTAssertEqual(first.label, "Sunset")
        XCTAssertEqual(first.category, "mesh")
        XCTAssertEqual(first.thumbnailUrl,
                       URL(string: "https://cdn.example.test/banners/mesh-sunset.png"))
        XCTAssertEqual(first.configJSON, "{\"fill\":{\"kind\":\"meshGradient\"}}")
        XCTAssertEqual(first.order, 1)
        XCTAssertNil(presets[1].thumbnailUrl)
    }

    func testBannerPresetsAppliesLenientDefaults() async throws {
        // Kale/lege CMS-velden mogen nooit de hele lijst laten falen (soft-
        // fail-semantiek): label ← key, lege category → "default", lege
        // thumbnail_url/config → nil, ontbrekende order → 0.
        BackendStubURLProtocol.setStub(.json(200, """
            {
              "banner_presets": [
                { "key": "bare", "category": "", "thumbnail_url": "", "config": "" }
              ]
            }
            """), forPath: "/v1/banner-presets")

        let presets = try await client.bannerPresets()
        let bare = try XCTUnwrap(presets.first)
        XCTAssertEqual(bare.label, "bare")
        XCTAssertEqual(bare.category, "default")
        XCTAssertNil(bare.thumbnailUrl)
        XCTAssertNil(bare.configJSON)
        XCTAssertEqual(bare.order, 0)
    }

    func testBannerPresetsEmptyListDecodes() async throws {
        // Het soft-fail-pad van het endpoint (CMS-hik → lege lijst i.p.v.
        // 5xx); de app valt dan terug op z'n lokale fallback-presets.
        BackendStubURLProtocol.setStub(.json(200, """
            { "banner_presets": [] }
            """), forPath: "/v1/banner-presets")

        let presets = try await client.bannerPresets()
        XCTAssertTrue(presets.isEmpty)
    }

    // MARK: - GET /v1/hair-presets (E52.1 — thumbnail_url)

    func testHairPresetsDecodesBackendShapeWithThumbnail() async throws {
        // Vorm uit backend/api/v1/hair-presets.ts ná E52.1: naast key/label/
        // order een optionele `thumbnail_url` (Supabase render-variant). Oude
        // CMS-items zonder thumbnail sturen null → nil, en een item zónder het
        // veld (oude backend-deploy) decodeert ook.
        BackendStubURLProtocol.setStub(.json(200, """
            {
              "presets": [
                {
                  "key": "buzz-cut",
                  "label": "Buzz cut",
                  "thumbnail_url": "https://cdn.example.test/storage/v1/render/image/public/media/buzz.jpg?width=320&quality=75",
                  "order": 1
                },
                { "key": "long-waves", "label": "Long waves", "thumbnail_url": null, "order": 2 },
                { "key": "legacy", "label": "Legacy", "order": 3 }
              ]
            }
            """), forPath: "/v1/hair-presets")

        let presets = try await client.hairPresets()
        XCTAssertEqual(presets.count, 3)
        XCTAssertEqual(presets[0].key, "buzz-cut")
        XCTAssertEqual(
            presets[0].thumbnailUrl,
            URL(string: "https://cdn.example.test/storage/v1/render/image/public/media/buzz.jpg?width=320&quality=75")
        )
        XCTAssertNil(presets[1].thumbnailUrl)
        XCTAssertNil(presets[2].thumbnailUrl, "ontbrekend veld hoort nil te zijn, geen decode-fout")
    }

    func testFacePresetsLenientDefaultsDecode() async throws {
        // Lege thumbnail_url ("") → nil; ontbrekend label ← key; ontbrekende
        // order → 99 (sorteert achteraan, zoals de server-default).
        BackendStubURLProtocol.setStub(.json(200, """
            { "presets": [ { "key": "whiten-teeth", "thumbnail_url": "" } ] }
            """), forPath: "/v1/face-presets")

        let presets = try await client.facePresets()
        let bare = try XCTUnwrap(presets.first)
        XCTAssertEqual(bare.label, "whiten-teeth")
        XCTAssertNil(bare.thumbnailUrl)
        XCTAssertEqual(bare.order, 99)
    }

    // MARK: - GET /v1/backgrounds (E52.1 — thumbnail_url-variant)

    func testBackgroundsDecodesBackendShape() async throws {
        // Vorm uit backend/api/v1/backgrounds.ts: image_url = origineel (voor
        // export-compositing), thumbnail_url = verkleinde render-variant voor
        // de panel-swatch. Ontbreekt thumbnail_url (oude backend), dan valt de
        // client terug op image_url.
        BackendStubURLProtocol.setStub(.json(200, """
            {
              "backgrounds": [
                {
                  "key": "studio-grey",
                  "label": "Studio grey",
                  "category": "Studio",
                  "image_url": "https://cdn.example.test/storage/v1/object/public/media/studio.jpg",
                  "thumbnail_url": "https://cdn.example.test/storage/v1/render/image/public/media/studio.jpg?width=160&quality=75",
                  "order": 1
                },
                {
                  "key": "legacy-beach",
                  "category": "Outdoor",
                  "image_url": "https://cdn.example.test/storage/v1/object/public/media/beach.jpg"
                }
              ]
            }
            """), forPath: "/v1/backgrounds")

        let backgrounds = try await client.backgrounds()
        XCTAssertEqual(backgrounds.count, 2)
        let first = try XCTUnwrap(backgrounds.first)
        XCTAssertEqual(first.key, "studio-grey")
        XCTAssertEqual(
            first.thumbnailUrl,
            URL(string: "https://cdn.example.test/storage/v1/render/image/public/media/studio.jpg?width=160&quality=75")
        )
        XCTAssertEqual(
            first.imageUrl,
            URL(string: "https://cdn.example.test/storage/v1/object/public/media/studio.jpg")
        )
        // Fallback-pad: zonder thumbnail_url wordt image_url de swatch-bron.
        XCTAssertEqual(backgrounds[1].thumbnailUrl, backgrounds[1].imageUrl)
        XCTAssertEqual(backgrounds[1].label, "legacy-beach")
    }

    // MARK: - POST /v1/account/delete (E15.7)

    /// Contract met backend/api/v1/account/delete.ts: POST + Bearer + de
    /// `X-Confirm-Delete: yes`-header (tweede consent). Zonder die header
    /// weigert de server met 400 — de header is dus deel van het contract.
    func testDeleteAccountSendsConfirmHeaderViaPost() async throws {
        // 200-vorm uit delete.ts (scope-details genegeerd door de client).
        BackendStubURLProtocol.setStub(.json(200, """
            {
              "deleted": true,
              "scope": {
                "stripe_subscriptions_cancelled": 1,
                "stripe_customer_kept": true,
                "storage_objects_removed": 0,
                "auth_user_deleted": true,
                "errors": []
              }
            }
            """), forPath: "/v1/account/delete")

        try await client.deleteAccount()

        let req = try XCTUnwrap(
            BackendStubURLProtocol.requestLog.last(where: { $0.url?.path == "/v1/account/delete" })
        )
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Confirm-Delete"), "yes")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }

    /// 500-pad uit delete.ts (auth-delete faalde): moet als serverfout
    /// propageren zodat de UI een retry aanbiedt i.p.v. succes te veinzen.
    func testDeleteAccountServerFailureThrows() async {
        BackendStubURLProtocol.setStub(.json(500, """
            { "deleted": false, "scope": { "errors": ["auth_delete: boom"] } }
            """), forPath: "/v1/account/delete")

        do {
            try await client.deleteAccount()
            XCTFail("verwachtte BackendError.server")
        } catch BackendError.server(let status, _) {
            XCTAssertEqual(status, 500)
        } catch {
            XCTFail("verkeerde fout: \(error)")
        }
    }

    /// Delete vereist een sessie — de JWT ís het consent-signaal.
    func testDeleteAccountWithoutSessionThrowsNotSignedIn() async {
        auth.accessToken = nil

        do {
            try await client.deleteAccount()
            XCTFail("verwachtte BackendError.notSignedIn")
        } catch BackendError.notSignedIn {
            // verwacht
        } catch {
            XCTFail("verkeerde fout: \(error)")
        }
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
