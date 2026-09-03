import Foundation
import XCTest
@testable import AvatarKit

// Sticker-fix (2026-09-02): `/v1/effects` levert `composition` ("die_cut" |
// "portrait"); ontbrekend of onbekend → portrait, zodat een oude lijst-
// snapshot of een nieuwere server de lijst nooit laat falen.
final class RemoteEffectCompositionTests: XCTestCase {

    private func decode(_ json: String) throws -> RemoteEffect {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(RemoteEffect.self, from: Data(json.utf8))
    }

    func testDieCutDecodes() throws {
        let e = try decode(#"{"key":"sticker","label":"Sticker","order":12,"composition":"die_cut"}"#)
        XCTAssertEqual(e.composition, .dieCut)
        XCTAssertTrue(e.isDieCut)
    }

    func testMissingCompositionIsPortrait() throws {
        let e = try decode(#"{"key":"windy","label":"Windy","order":11}"#)
        XCTAssertEqual(e.composition, .portrait)
        XCTAssertFalse(e.isDieCut)
    }

    func testUnknownCompositionFallsBackToPortrait() throws {
        let e = try decode(#"{"key":"x","label":"X","order":1,"composition":"hologram"}"#)
        XCTAssertEqual(e.composition, .portrait)
    }

    func testEncodeRoundTripKeepsComposition() throws {
        let original = RemoteEffect(key: "sticker", label: "Sticker", thumbnailUrl: nil, order: 12, composition: .dieCut)
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(RemoteEffect.self, from: data)
        XCTAssertEqual(back, original)
    }

    func testFallbackMarksStickerAndBalloonAsDieCut() {
        // Vrijstaande stijlen (server: DIE_CUT_STYLE_KEYS) — sticker + balloon.
        let freestanding: Set<String> = ["sticker", "balloon"]
        for key in freestanding {
            XCTAssertEqual(RemoteEffect.fallback.first { $0.key == key }?.composition, .dieCut, key)
        }
        XCTAssertTrue(RemoteEffect.fallback.filter { !freestanding.contains($0.key) }.allSatisfy { !$0.isDieCut })
    }
}
