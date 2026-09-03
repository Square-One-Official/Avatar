// E05.4 — set/sidebar: Portrait2-persistentie (in-memory) en de
// naam/rol-doorschrijf van ShellModel naar het geselecteerde portret.

import AvatarKit
import SwiftData
import XCTest
@testable import Avatar2

@MainActor
final class Portrait2Tests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Portrait2.self, configurations: config)
        return ModelContext(container)
    }

    func testInsertEnFetch() throws {
        let context = try makeContext()
        context.insert(Portrait2(name: "Sonja Bakker", role: "Designer", cutoutData: Data([1])))
        let all = try context.fetch(FetchDescriptor<Portrait2>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "Sonja Bakker")
    }

    func testNaamRolSchrijvenDoorNaarSelectie() throws {
        let context = try makeContext()
        let portrait = Portrait2(cutoutData: Data([1]))
        context.insert(portrait)

        let model = ShellModel(entitlement: EntitlementModel(auth: AuthService.isolated()))
        model.modelContext = context
        model.select(portrait)
        model.portraitName = "Jan van den Berg"
        model.portraitRole = "CTO"

        XCTAssertEqual(portrait.name, "Jan van den Berg")
        XCTAssertEqual(portrait.role, "CTO")
    }

    // E49.3: effectCache slaat op als binaire plist (Data rauw, geen base64)
    // en blijft pre-E49.3-JSON (base64-Data) lezen.
    func testEffectCachePlistRoundtrip() throws {
        let context = try makeContext()
        let portrait = Portrait2(cutoutData: Data([1]))
        context.insert(portrait)

        let png = Data([0x89, 0x50, 0x4E, 0x47])
        portrait.effectCache = ["mono": png]

        XCTAssertEqual(portrait.effectCache, ["mono": png])
        // Opslagformaat is plist, niet JSON.
        let raw = try XCTUnwrap(portrait.effectCacheData)
        XCTAssertNoThrow(try PropertyListSerialization.propertyList(from: raw, options: [], format: nil))
        XCTAssertThrowsError(try JSONSerialization.jsonObject(with: raw))
        // effectBackgroundData pakt de actieve entry uit de plist.
        portrait.effectActiveRaw = "mono"
        XCTAssertEqual(portrait.effectBackgroundData, png)
    }

    func testEffectCacheLeestOudeJSONOpslag() throws {
        let context = try makeContext()
        let portrait = Portrait2(cutoutData: Data([1]))
        context.insert(portrait)

        let png = Data([0x89, 0x50, 0x4E, 0x47])
        // Pre-E49.3-formaat: JSONEncoder schreef Data als base64-string.
        portrait.effectCacheData = try JSONEncoder().encode(["mono": png])

        XCTAssertEqual(portrait.effectCache, ["mono": png])
        portrait.effectActiveRaw = "mono"
        XCTAssertEqual(portrait.effectBackgroundData, png)
    }
}
