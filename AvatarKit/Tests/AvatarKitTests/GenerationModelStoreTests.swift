import Foundation
import XCTest
@testable import AvatarKit

/// E15.6: de gebruikersgerichte generatie-modelkeuze. Bewijst dat nano-banana
/// de default is (ongewijzigd gedrag tot iemand bewust schakelt) en dat een
/// keuze persisteert met de juiste backend-key — exact wat BackendClient.
/// stylize als `generation_model` meestuurt.
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

    func testDefaultIsNanoBanana() {
        let store = GenerationModelStore(defaults: defaults)
        XCTAssertEqual(store.current, .nanoBanana)
        // De rawValue is de server-side key die in de request belandt.
        XCTAssertEqual(store.current.rawValue, "nano-banana")
    }

    func testSelectingOpenAIPersistsBackendKey() {
        GenerationModelStore(defaults: defaults).current = .openAI
        // Nieuwe instance leest dezelfde store: keuze overleeft.
        let reread = GenerationModelStore(defaults: defaults)
        XCTAssertEqual(reread.current, .openAI)
        XCTAssertEqual(reread.current.rawValue, "gpt-image-1.5")
    }

    func testRoundTripBackToDefault() {
        let store = GenerationModelStore(defaults: defaults)
        store.current = .openAI
        store.current = .nanoBanana
        XCTAssertEqual(GenerationModelStore(defaults: defaults).current, .nanoBanana)
    }
}
