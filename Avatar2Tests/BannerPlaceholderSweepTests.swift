// E37.18 (audit-B6) — Placeholder-tekstlagen mogen niet persisteren of de
// hit-test blokkeren. Drie contracten: (1) `BannerDoc.dropEmptyTextLayers` is
// document-breed (met een keep-uitzondering voor de laag in bewerking),
// (2) hit-testing laat échte content altijd winnen van lege/placeholder-lagen,
// (3) de eenmalige migratie leegt literal-placeholder-lagen uit bestaande
// documenten en herbakt hun preview.

import AppKit
import SwiftData
import XCTest
@testable import Avatar2

@MainActor
final class BannerPlaceholderSweepTests: XCTestCase {

    private let canvas = CGSize(width: 1500, height: 500)

    private func makeDoc(texts: [BannerTextLayer]) -> BannerDoc {
        BannerDoc(canvasSize: canvas, layers: BannerLayers(fill: .solid(hex: "#101010"), texts: texts))
    }

    // MARK: dropEmptyTextLayers

    func testDropRemovesEmptyAndLiteralPlaceholderLayersDocumentWide() {
        let real = BannerTextLayer(string: "Aaavatar", fontSize: 64, colorHex: "#FFFFFF")
        let empty = BannerTextLayer(string: "", fontSize: 64, colorHex: "#FFFFFF")
        let literal = BannerTextLayer(string: BannerTextPresets.placeholder, fontSize: 64, colorHex: "#FFFFFF")
        let whitespace = BannerTextLayer(string: "  \n ", fontSize: 64, colorHex: "#FFFFFF")
        let doc = makeDoc(texts: [real, empty, literal, whitespace])

        let change = doc.dropEmptyTextLayers()

        XCTAssertNotNil(change)
        XCTAssertEqual(doc.layers.texts.map(\.id), [real.id], "alleen de échte laag hoort te blijven")
        XCTAssertEqual(change?.before.texts.count, 4)
        XCTAssertEqual(change?.after.texts.count, 1)
    }

    func testDropKeepsTheLayerBeingEdited() {
        let editing = BannerTextLayer(string: "", fontSize: 64, colorHex: "#FFFFFF")
        let stale = BannerTextLayer(string: BannerTextPresets.placeholder, fontSize: 64, colorHex: "#FFFFFF")
        let doc = makeDoc(texts: [stale, editing])

        doc.dropEmptyTextLayers(keeping: [editing.id])

        XCTAssertEqual(doc.layers.texts.map(\.id), [editing.id])
    }

    func testDropIsNoOpWithoutEmptyLayersAndDoesNotTouchUpdatedAt() {
        let real = BannerTextLayer(string: "Hi", fontSize: 64, colorHex: "#FFFFFF")
        let doc = makeDoc(texts: [real])
        let stamp = doc.updatedAt

        XCTAssertNil(doc.dropEmptyTextLayers())
        XCTAssertEqual(doc.updatedAt, stamp, "een no-op-sweep mag geen touch()/herbake triggeren")
    }

    // MARK: Hit-test-prioriteit

    func testHitTestPrefersRealTextOverNewerEmptyLayerOnTop() {
        // De lege laag komt LATER in de stack (hogere paint-order) en heeft een
        // placeholder-breed kader over dezelfde plek — vóór 37.18 won die de
        // hit-test en voelde het banner "bedekt".
        let real = BannerTextLayer(string: "Aaavatar", fontSize: 64, colorHex: "#FFFFFF", alignRaw: 1, x: 0.5, y: 0.5)
        let empty = BannerTextLayer(string: "", fontSize: 64, colorHex: "#FFFFFF", alignRaw: 1, x: 0.5, y: 0.5)
        let doc = makeDoc(texts: [real, empty])

        let hit = BannerLayoutMetrics.hitTest(
            at: CGPoint(x: canvas.width / 2, y: canvas.height / 2), doc: doc, canvas: canvas
        )

        XCTAssertEqual(hit, .text(real.id), "échte content hoort te winnen van een lege placeholder-laag")
    }

    func testHitTestStillFindsEmptyLayerWhenNothingElseIsThere() {
        let empty = BannerTextLayer(string: "", fontSize: 64, colorHex: "#FFFFFF", alignRaw: 1, x: 0.5, y: 0.5)
        let doc = makeDoc(texts: [empty])

        let hit = BannerLayoutMetrics.hitTest(
            at: CGPoint(x: canvas.width / 2, y: canvas.height / 2), doc: doc, canvas: canvas
        )

        XCTAssertEqual(hit, .text(empty.id), "een lege laag blijft klikbaar — alleen met laagste prioriteit")
    }

    func testHitTestPrefersLogoOverEmptyTextLayer() throws {
        let empty = BannerTextLayer(string: "", fontSize: 64, colorHex: "#FFFFFF", alignRaw: 1, x: 0.5, y: 0.5)
        let doc = makeDoc(texts: [empty])
        doc.logoImageData = try XCTUnwrap(solidPNG(width: 32, height: 32))
        var layers = doc.layers
        layers.logo = BannerLogoLayer(x: 0.5, y: 0.5, scale: 0.3)
        doc.layers = layers

        let hit = BannerLayoutMetrics.hitTest(
            at: CGPoint(x: canvas.width / 2, y: canvas.height / 2), doc: doc, canvas: canvas
        )

        XCTAssertEqual(hit, .logo)
    }

    // MARK: Eenmalige migratie

    private static let suite = "nl.aaavatar.tests.bannerPlaceholderSweep"

    private func freshDefaults() throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suite))
        defaults.removePersistentDomain(forName: Self.suite)
        return defaults
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
        super.tearDown()
    }

    func testMigrationDropsLiteralPlaceholderLayersAndRebakesPreview() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BannerDoc.self, configurations: config)
        let context = ModelContext(container)
        let legacy = makeDoc(texts: [
            BannerTextLayer(string: BannerTextPresets.placeholder, fontSize: 96, colorHex: "#FFFFFF"),
        ])
        let stalePreview = Data([1, 2, 3])
        legacy.previewImageData = stalePreview
        let clean = makeDoc(texts: [BannerTextLayer(string: "Keep me", fontSize: 96, colorHex: "#FFFFFF")])
        let cleanStamp = clean.updatedAt
        context.insert(legacy)
        context.insert(clean)
        try context.save()

        let defaults = try freshDefaults()
        await BannerPlaceholderMigration.runIfNeeded(context: context, defaults: defaults)

        XCTAssertTrue(legacy.layers.texts.isEmpty, "literal-placeholder-laag hoort geleegd te zijn")
        XCTAssertNotNil(legacy.previewImageData)
        XCTAssertNotEqual(legacy.previewImageData, stalePreview, "stale preview hoort herbakken te zijn")
        XCTAssertEqual(clean.layers.texts.count, 1, "documenten zonder placeholder-lagen blijven ongemoeid")
        XCTAssertEqual(clean.updatedAt, cleanStamp)
        XCTAssertTrue(defaults.bool(forKey: BannerPlaceholderMigration.defaultsKey))
    }

    // UXS-5 (v2-sweep): het legacy "Your text"-literal van het oude Text-paneel
    // (E37.4) telt óók als placeholder — filter, sweep en migratie.
    func testMigrationMatchesLegacyYourTextPlaceholder() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BannerDoc.self, configurations: config)
        let context = ModelContext(container)
        let legacy = makeDoc(texts: [
            BannerTextLayer(string: "Your text", fontSize: 96, colorHex: "#FFFFFF"),
        ])
        context.insert(legacy)
        try context.save()

        let defaults = try freshDefaults()
        await BannerPlaceholderMigration.runIfNeeded(context: context, defaults: defaults)

        XCTAssertTrue(legacy.layers.texts.isEmpty, "legacy 'Your text'-laag hoort geleegd te zijn")
    }

    // UXS-5 (v2-sweep): een doc met schone lagen maar een bestaande bake wordt
    // eenmalig herbakken (bake kan van vóór de render-guard stammen).
    func testMigrationRebakesCleanDocsWithExistingPreview() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BannerDoc.self, configurations: config)
        let context = ModelContext(container)
        let clean = makeDoc(texts: [BannerTextLayer(string: "Keep me", fontSize: 96, colorHex: "#FFFFFF")])
        let staleBake = Data([9, 9, 9])
        clean.previewImageData = staleBake
        context.insert(clean)
        try context.save()

        let defaults = try freshDefaults()
        await BannerPlaceholderMigration.runIfNeeded(context: context, defaults: defaults)

        XCTAssertNotNil(clean.previewImageData)
        XCTAssertNotEqual(clean.previewImageData, staleBake, "bestaande bake hoort eenmalig herbakken te zijn")
    }

    func testMigrationRunsOnlyOnce() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BannerDoc.self, configurations: config)
        let context = ModelContext(container)
        let doc = makeDoc(texts: [
            BannerTextLayer(string: BannerTextPresets.placeholder, fontSize: 96, colorHex: "#FFFFFF"),
        ])
        context.insert(doc)
        try context.save()

        let defaults = try freshDefaults()
        defaults.set(true, forKey: BannerPlaceholderMigration.defaultsKey)
        await BannerPlaceholderMigration.runIfNeeded(context: context, defaults: defaults)

        XCTAssertEqual(doc.layers.texts.count, 1, "met gezet stempel hoort de bulk-sweep niets te doen")
    }

    private func solidPNG(width: Int, height: Int) -> Data? {
        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
