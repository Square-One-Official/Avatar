// E13.2 — importer: v1-back-up → Portrait2-store.
//
// Idempotentie is het hart: gebruikers klikken "Import" gerust twee keer, en
// de tweede keer mag niets dupliceren én niets overschrijven (het portret kan
// in v2 al bewerkt zijn).

import AvatarKit
import Foundation
import SwiftData
import XCTest
@testable import Avatar2

@MainActor
final class V1LibraryImporterTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Portrait2.self, Folder2.self, configurations: config
        )
        return ModelContext(container)
    }

    private func payload(
        id: UUID = UUID(),
        name: String = "Ava",
        tags: String = "CEO",
        png: Data = Data([1, 2, 3])
    ) -> V1LibraryArchive.PortraitPayload {
        V1LibraryArchive.PortraitPayload(
            id: id, name: name, tags: tags,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            cutoutPNG: png
        )
    }

    private func library(
        _ portraits: [V1LibraryArchive.PortraitPayload],
        skipped: Int = 0
    ) -> V1LibraryArchive.Library {
        V1LibraryArchive.Library(
            schemaVersion: 1, appVersion: "1.2.1", exportedAt: .now,
            portraits: portraits, skippedWithoutCutout: skipped
        )
    }

    func testImportCreatesPortraitInImportFolder() throws {
        let context = try makeContext()
        let p = payload()

        let summary = try V1LibraryImporter.importLibrary(library([p]), into: context)

        XCTAssertEqual(summary.imported, 1)
        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<Portrait2>()).first)
        XCTAssertEqual(stored.name, "Ava")
        XCTAssertEqual(stored.role, "CEO", "v1-tags landen als rol — zichtbaar, hernoembaar")
        XCTAssertEqual(stored.cutoutData, Data([1, 2, 3]))
        XCTAssertEqual(stored.v1ImportID, p.id.uuidString)
        XCTAssertNil(stored.originalData, "de v1-back-up bevat geen origineel")
        XCTAssertEqual(stored.folder?.name, V1LibraryImporter.importFolderName)
        // De échte v1-datums, niet vandaag — anders overspoelt een migratie de
        // Recent-sectie op Home.
        XCTAssertEqual(stored.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(stored.updatedAt, Date(timeIntervalSince1970: 1_750_000_000))
    }

    func testReimportIsIdempotent() throws {
        let context = try makeContext()
        let p = payload()

        _ = try V1LibraryImporter.importLibrary(library([p]), into: context)
        // Bewerk het portret in "v2" — een her-import mag dit niet terugdraaien.
        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<Portrait2>()).first)
        stored.name = "Renamed in v2"
        try context.save()

        let second = try V1LibraryImporter.importLibrary(library([p]), into: context)

        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.duplicates, 1)
        let all = try context.fetch(FetchDescriptor<Portrait2>())
        XCTAssertEqual(all.count, 1, "geen duplicaat")
        XCTAssertEqual(all.first?.name, "Renamed in v2", "her-import overschrijft niet")
    }

    func testPartialOverlapImportsOnlyTheNewOnes() throws {
        let context = try makeContext()
        let a = payload(name: "A")
        let b = payload(name: "B")

        _ = try V1LibraryImporter.importLibrary(library([a]), into: context)
        let second = try V1LibraryImporter.importLibrary(library([a, b]), into: context)

        XCTAssertEqual(second.imported, 1)
        XCTAssertEqual(second.duplicates, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Portrait2>()).count, 2)
    }

    func testImportFolderIsReusedAcrossImports() throws {
        let context = try makeContext()
        _ = try V1LibraryImporter.importLibrary(library([payload()]), into: context)
        _ = try V1LibraryImporter.importLibrary(library([payload()]), into: context)

        let folders = try context.fetch(FetchDescriptor<Folder2>())
        XCTAssertEqual(folders.count, 1, "één 'Aaavatar 1'-map, niet één per import-run")
        XCTAssertEqual(folders.first?.portraits.count, 2)
    }

    func testSkippedWithoutCutoutSurfacesInSummary() throws {
        let context = try makeContext()
        let summary = try V1LibraryImporter.importLibrary(
            library([payload()], skipped: 2), into: context
        )
        XCTAssertEqual(summary.withoutCutout, 2)
        XCTAssertTrue(summary.userMessage.contains("skipped"), summary.userMessage)
    }

    func testV2NativePortraitsAreInvisibleToDedup() throws {
        let context = try makeContext()
        // Een v2-eigen portret zonder v1ImportID mag de dedup niet raken.
        context.insert(Portrait2(name: "Native", cutoutData: Data([9])))
        try context.save()

        let summary = try V1LibraryImporter.importLibrary(library([payload()]), into: context)
        XCTAssertEqual(summary.imported, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Portrait2>()).count, 2)
    }

    // E13.7: de live v1-store levert het origineel mee (de zip niet).
    func testOriginalImageLandsInOriginalData() throws {
        let context = try makeContext()
        let original = Data([9, 9, 9])
        let p = V1LibraryArchive.PortraitPayload(
            id: UUID(), name: "Ava", tags: "",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            cutoutPNG: Data([1, 2, 3]), originalImage: original
        )

        let summary = try V1LibraryImporter.importLibrary(library([p]), into: context)

        XCTAssertEqual(summary.imported, 1)
        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<Portrait2>()).first)
        XCTAssertEqual(stored.originalData, original)
    }
}
