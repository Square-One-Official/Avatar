import Foundation
import XCTest
@testable import AvatarKit

/// E55.6 — disk-persistentie van de CMS-lijsten. Bewijst de round-trip voor
/// beide lijsten (incl. URL-nil en de Codable-symmetrie van de modellen), de
/// corrupt-bestand-tolerantie (nil + opruimen) en dat een koude load ver onder
/// de oude netwerk-round-trip blijft (de "instant"-claim van het paneel).
final class EffectsListCacheTests: XCTestCase {

    private var directory: URL!
    private var cache: EffectsListCache!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EffectsListCacheTests-\(UUID().uuidString)", isDirectory: true)
        cache = EffectsListCache(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        cache = nil
    }

    func testMissingFileReturnsNil() {
        XCTAssertNil(cache.loadEffects())
        XCTAssertNil(cache.loadCustomEffects())
    }

    func testEffectsRoundTripPreservesFields() {
        let effects = [
            RemoteEffect(
                key: "balloon", label: "Balloon",
                thumbnailUrl: URL(string: "https://x.storage.supabase.co/storage/v1/render/image/public/m/a.png?width=320"),
                order: 10
            ),
            RemoteEffect(key: "windy", label: "Windy", thumbnailUrl: nil, order: 11),
        ]
        cache.saveEffects(effects)
        let loaded = cache.loadEffects()
        XCTAssertEqual(loaded, effects)
        XCTAssertEqual(loaded?.first?.thumbnailUrl?.query, "width=320")
    }

    func testCustomEffectsRoundTrip() {
        let effects = [
            RemoteCustomEffect(
                id: "abc-123", label: "Mijn stijl",
                thumbnailUrl: URL(string: "https://x.supabase.co/storage/v1/object/public/custom-effects/u/e.png"),
                order: 0
            ),
        ]
        cache.saveCustomEffects(effects)
        XCTAssertEqual(cache.loadCustomEffects(), effects)
        // De built-in-lijst blijft er los van.
        XCTAssertNil(cache.loadEffects())
    }

    func testOverwriteReplacesSnapshot() {
        cache.saveEffects([RemoteEffect(key: "a", label: "A", thumbnailUrl: nil, order: 1)])
        cache.saveEffects([RemoteEffect(key: "b", label: "B", thumbnailUrl: nil, order: 2)])
        XCTAssertEqual(cache.loadEffects()?.map(\.key), ["b"])
    }

    func testCorruptFileReturnsNilAndIsRemoved() throws {
        let file = directory.appendingPathComponent("effects.json")
        try Data("dit is geen json {".utf8).write(to: file)
        XCTAssertNil(cache.loadEffects())
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "rot bestand hoort opgeruimd")
    }

    /// De hele winst van E55.6: de lijst-hydratie die voorheen een netwerk-
    /// round-trip was (~200–500 ms prod-gemeten) moet van disk in de
    /// microseconden–millisecondenklasse zitten. Ruime bound tegen CI-ruis.
    func testColdLoadIsFast() {
        cache.saveEffects(RemoteEffect.fallback)
        let start = ContinuousClock.now
        let loaded = EffectsListCache(directory: directory).loadEffects()
        let elapsed = ContinuousClock.now - start
        XCTAssertEqual(loaded?.count, RemoteEffect.fallback.count)
        XCTAssertLessThan(elapsed, .milliseconds(100), "disk-hydratie hoort (ver) onder 100 ms")
    }

    func testFallbackCarriesTheSixStyles20Keys() {
        XCTAssertEqual(
            RemoteEffect.fallback.map(\.key),
            ["balloon", "windy", "sticker", "flowers", "3d-head", "hairy"]
        )
    }
}
