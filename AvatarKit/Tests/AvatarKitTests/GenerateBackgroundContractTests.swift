import Foundation
import XCTest
@testable import AvatarKit

/// E43.2 — contract-test voor `POST /v1/generate-background` (signed-URL-
/// contract, E42). De A2-outage ("Unexpected server response", wél 2 credits
/// afgeschreven) was precies een client↔backend-vormverschil dat één
/// fixture-decode-test had gevangen — zelfde patroon als
/// `MessagingServiceTests.testMessageDecodesBackendShape`.
///
/// De fixture hieronder is de LETTERLIJKE 200-respons van
/// `backend/api/v1/generate-background.ts` (res.status(200).json). Wijzigt de
/// backend die vorm, dan moet deze fixture — en dus bewust ook de Swift-decoder
/// `BackendClient.GenerateBackgroundResponse` — mee.
final class GenerateBackgroundContractTests: XCTestCase {

    /// Zelfde decoder-configuratie als `BackendClient.request` (200-pad):
    /// iso8601-datums + snake_case → camelCase. Als request() ooit een andere
    /// strategie krijgt, hoort deze helper mee te veranderen.
    private func backendDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Spiegel van backend/api/v1/generate-background.ts:215-222 — exact de
    /// keys en typen die de endpoint vandaag serveert.
    private let endpointFixture = """
    {
      "image_url": "https://xyz.supabase.co/storage/v1/object/sign/generated-results/user-1/abc.webp?token=sig",
      "credits_remaining": 28,
      "model": "nano-banana",
      "target_width": 1024,
      "target_height": 1024,
      "credits_charged": 2
    }
    """.data(using: .utf8)!

    func testSwiftDecoderAcceptsEndpointResponseShape() throws {
        let resp = try backendDecoder().decode(
            BackendClient.GenerateBackgroundResponse.self,
            from: endpointFixture
        )
        XCTAssertEqual(
            resp.imageUrl,
            "https://xyz.supabase.co/storage/v1/object/sign/generated-results/user-1/abc.webp?token=sig"
        )
        XCTAssertEqual(resp.creditsRemaining, 28)
        // generateBackground() maakt hier een URL van vóór de tweede hop
        // (signed Storage download) — dat mag nooit op de decode-guard stranden.
        XCTAssertNotNil(URL(string: resp.imageUrl))
    }

    /// De oude (27-jun) prod-iteratie serveerde een base64-`image` i.p.v.
    /// `image_url` — precies de A2-outage. Die vorm MOET falen, zodat een
    /// contract-regressie hier zichtbaar wordt en niet pas op prod.
    func testSwiftDecoderRejectsLegacyInlineImageShape() {
        let legacy = """
        { "image": "aWJt", "credits_remaining": 28 }
        """.data(using: .utf8)!
        XCTAssertThrowsError(
            try backendDecoder().decode(BackendClient.GenerateBackgroundResponse.self, from: legacy)
        )
    }

    /// Extra velden (zoals `model`/`credits_charged`) mogen de decode nooit
    /// breken — de backend moet velden kunnen toevoegen zonder app-release.
    func testSwiftDecoderIgnoresUnknownExtraFields() throws {
        let withExtra = """
        {
          "image_url": "https://example.com/x.webp",
          "credits_remaining": 5,
          "some_future_field": { "nested": true }
        }
        """.data(using: .utf8)!
        let resp = try backendDecoder().decode(
            BackendClient.GenerateBackgroundResponse.self,
            from: withExtra
        )
        XCTAssertEqual(resp.creditsRemaining, 5)
    }
}
