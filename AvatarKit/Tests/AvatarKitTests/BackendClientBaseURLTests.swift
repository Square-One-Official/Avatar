import Foundation
import XCTest
@testable import AvatarKit

/// E01.15: de DEBUG backend-endpoint-override. Bewijst dat een gezette
/// `dev.apiBase` (Advanced-settings) de baseURL verlegt in DEBUG, en dat de
/// productie-URL geldt zonder override. (In Release compileert het override-
/// pad niet mee → altijd productie.)
@MainActor
final class BackendClientBaseURLTests: XCTestCase {
    private final class StubAuth: AccessTokenProviding {
        var accessToken: String? { nil }
    }

    private let key = "dev.apiBase"
    /// Eigen, per-test UserDefaults-suite: `swift test --parallel` draait
    /// methoden in aparte processen die `.standard` op schijf delen, dus een
    /// gedeelde sleutel racet tussen de override- en de leeg-override-test.
    private var suiteName = ""
    private var defaults: UserDefaults { BackendClient.devOverrideDefaults }

    override func setUp() {
        suiteName = "nl.squareone.aaavatar2.tests.\(UUID().uuidString)"
        BackendClient.devOverrideDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        BackendClient.devOverrideDefaults = .standard
    }

    func testDefaultsToProduction() {
        let client = BackendClient(auth: StubAuth())
        XCTAssertEqual(client.baseURL.absoluteString, "https://api.aaavatar.nl")
    }

    func testDebugOverrideRedirectsBaseURL() throws {
        // Env AAAVATAR_API_BASE heeft voorrang; in de testomgeving is die niet
        // gezet, dus de UserDefaults-tak wordt geraakt.
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AAAVATAR_API_BASE"] == nil,
                          "AAAVATAR_API_BASE env override active; UserDefaults-pad niet meetbaar")
        defaults.set("https://preview.example.com", forKey: key)
        let client = BackendClient(auth: StubAuth())
        #if DEBUG
        XCTAssertEqual(client.baseURL.absoluteString, "https://preview.example.com")
        #else
        XCTAssertEqual(client.baseURL.absoluteString, "https://api.aaavatar.nl")
        #endif
    }

    func testEmptyOverrideIgnored() {
        defaults.set("", forKey: key)
        let client = BackendClient(auth: StubAuth())
        XCTAssertEqual(client.baseURL.absoluteString, "https://api.aaavatar.nl")
    }
}
