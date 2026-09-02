// Audit-opschoning background-paneel (2026-07-03) — de brand-kleuren-kit
// liep vol met bijna identieke picker-tussenstanden ("veel random rood").
// Deze tests dekken de éénmalige sanering bij laden, het schoon houden bij
// `add` en het daadwerkelijk verdwijnen bij `remove` (het hover-kruisje).

import XCTest
@testable import Avatar2

@MainActor
final class BrandColorKitTests: XCTestCase {

    private func makeDefaults(_ hexes: [String]? = nil) -> UserDefaults {
        let suite = "BrandColorKitTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if let hexes { defaults.set(hexes, forKey: "backgroundBrandColorsHex") }
        return defaults
    }

    func testLoadCollapsesNearDuplicateShades() {
        // Tien picker-tussenstanden van vrijwel hetzelfde rood + één blauw.
        let reds = (0..<10).map { String(format: "#%02X1010", 0x8B + $0) }
        let kit = BrandColorKit(defaults: makeDefaults(reds + ["#1040FF"]))
        XCTAssertEqual(kit.hexColors.count, 2, "near-duplicate roden moeten samenvouwen")
        XCTAssertTrue(kit.hexColors.contains("#1040FF"))
    }

    func testLoadKeepsDistinctColorsAndCapsAtMax() {
        // 20 duidelijk verschillende kleuren → alleen de recentste 12 blijven.
        let distinct = (0..<20).map { String(format: "#%02X%02X%02X", $0 * 12, 255 - $0 * 12, ($0 * 40) % 255) }
        let kit = BrandColorKit(defaults: makeDefaults(distinct))
        XCTAssertEqual(kit.hexColors.count, BrandColorKit.maxStored)
        XCTAssertEqual(kit.hexColors.last, distinct.last, "recentste kleur blijft achteraan")
    }

    func testSanitizedResultIsPersisted() {
        let defaults = makeDefaults(["#FF0000", "#FE0101", "junk", "#00FF00"])
        _ = BrandColorKit(defaults: defaults)
        let persisted = defaults.stringArray(forKey: "backgroundBrandColorsHex")
        XCTAssertEqual(persisted, ["#FE0101", "#00FF00"],
                       "sanering moet ook worden weggeschreven (nieuwste van het rode paar wint)")
    }

    func testAddReplacesNearDuplicateInsteadOfAppending() {
        let kit = BrandColorKit(defaults: makeDefaults(["#8B1010", "#1040FF"]))
        kit.add("#8D1212") // vrijwel hetzelfde rood → vervangt, groeit niet
        XCTAssertEqual(kit.hexColors, ["#1040FF", "#8D1212"])
    }

    func testAddPlacesNewestLastInStorageNewestFirstWhenReversed() {
        let kit = BrandColorKit(defaults: makeDefaults(["#1040FF"]))
        kit.add("#8B1010")
        XCTAssertEqual(kit.hexColors, ["#1040FF", "#8B1010"])
        XCTAssertEqual(kit.hexColors.reversed().first, "#8B1010",
                       "Gallery toont newest naast de plus via reversed()")
    }

    func testRemoveDeletesAndPersists() {
        let defaults = makeDefaults(["#8B1010", "#1040FF"])
        let kit = BrandColorKit(defaults: defaults)
        kit.remove("#8B1010")
        XCTAssertEqual(kit.hexColors, ["#1040FF"])
        XCTAssertEqual(defaults.stringArray(forKey: "backgroundBrandColorsHex"), ["#1040FF"])
    }
}
