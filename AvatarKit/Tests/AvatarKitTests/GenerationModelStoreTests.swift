import Foundation
import XCTest
@testable import AvatarKit

/// Persistente GenerationModelStore (niet meer user-facing). Encoding-tests
/// blijven: `generation_model` verdwijnt uit de JSON als de client `nil` stuurt
/// — BackendClient laat het veld nu altijd weg tenzij een caller hem zet.
@MainActor
final class GenerationModelStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "GenerationModelStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultShowsOpenAIButSendsNothing() {
        let store = GenerationModelStore(defaults: defaults)
        // Settings toont de code-default…
        XCTAssertEqual(store.current, .openAI)
        // …maar zonder expliciete keuze gaat er géén veld mee de request in.
        XCTAssertNil(store.explicit)
    }

    func testExplicitChoicePersistsBackendKey() {
        GenerationModelStore(defaults: defaults).current = .nanoBanana
        let reread = GenerationModelStore(defaults: defaults)
        XCTAssertEqual(reread.explicit, .nanoBanana)
        XCTAssertEqual(reread.current, .nanoBanana)
        // De rawValue is de server-side key die in de request belandt.
        XCTAssertEqual(reread.explicit?.rawValue, "nano-banana")
    }

    func testChoosingTheDefaultIsStillExplicit() {
        // Wie bewust OpenAI kiest, blijft OpenAI sturen — ook als de
        // server-default ooit via env terugflipt naar nano.
        let store = GenerationModelStore(defaults: defaults)
        store.current = .openAI
        XCTAssertEqual(GenerationModelStore(defaults: defaults).explicit, .openAI)
        XCTAssertEqual(store.explicit?.rawValue, "gpt-image-2")
    }

    func testUnknownStoredValueFallsBackToServerDefault() {
        defaults.set("model-van-de-toekomst", forKey: "generation.model")
        let store = GenerationModelStore(defaults: defaults)
        XCTAssertNil(store.explicit)
        XCTAssertEqual(store.current, .openAI)
    }

    func testLegacyGptImage15PreferenceDegradesToServerDefault() {
        // gpt-image-2-swap: een oude dev-voorkeur "gpt-image-1.5" is geen
        // geldige case meer → geen veld in de request, server-default regeert.
        defaults.set("gpt-image-1.5", forKey: "generation.model")
        let store = GenerationModelStore(defaults: defaults)
        XCTAssertNil(store.explicit)
        XCTAssertEqual(store.current, .openAI)
    }

    // MARK: - Request-encoding (E55.2)

    /// Zonder keuze moet `generation_model` volledig uit de JSON verdwijnen —
    /// `null` zou server-side ook werken maar is contract-ruis; afwezig is
    /// het bewijs dat de server-default regeert.
    func testStylizeBodyOmitsGenerationModelWhenNil() throws {
        let body = BackendClient.StylizeBody(
            storageKey: "u/x.png", generationModel: nil, modelOverride: nil,
            cutoutW: nil, cutoutH: nil, style: "balloon", hairPreset: nil,
            hairPrompt: nil, clothesPreset: nil, clothesPrompt: nil,
            facePreset: nil, softSource: nil, preserveFraming: true
        )
        let json = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        XCTAssertFalse(json.contains("generation_model"), "nil-keuze moet het veld weglaten, kreeg \(json)")
        XCTAssertTrue(json.contains("\"style\":\"balloon\""))
    }

    func testStylizeBodyCarriesExplicitChoice() throws {
        let body = BackendClient.StylizeBody(
            storageKey: "u/x.png", generationModel: "nano-banana", modelOverride: nil,
            cutoutW: nil, cutoutH: nil, style: "balloon", hairPreset: nil,
            hairPrompt: nil, clothesPreset: nil, clothesPrompt: nil,
            facePreset: nil, softSource: nil, preserveFraming: nil
        )
        let json = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        XCTAssertTrue(json.contains("\"generation_model\":\"nano-banana\""))
    }
}
