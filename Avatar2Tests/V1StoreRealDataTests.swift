// E13.7 — échte-data-test voor het migratiepad (GO-NO-GO-2.0 §5).
//
// Leest de ECHTE Aaavatar 1-container van de ingelogde gebruiker door de
// gesandboxte test-host (Aaavatar.app, dezelfde entitlements als de app). Dat
// bewijst drie dingen tegelijk: de read-only sandbox-uitzondering werkt, de
// reader verstaat een door v1 zelf geschreven store, en de importer neemt
// alles idempotent over. Env-gated: draait alleen met
//   TEST_RUNNER_V1_REAL_STORE=1 xcodebuild … test -only-testing:Avatar2Tests/V1StoreRealDataTests
// omdat de test-host op macOS 15+ dan de "data from other apps"-prompt toont
// (iemand moet Allow klikken) en omdat de uitkomst per Mac verschilt.
// Resultaat komt via `print` ("V1REAL: …") in het xcodebuild-log.

import AvatarKit
import Foundation
import SwiftData
import XCTest
@testable import Avatar2

@MainActor
final class V1StoreRealDataTests: XCTestCase {

    func testRealV1LibraryImportsIdempotently() throws {
        guard ProcessInfo.processInfo.environment["V1_REAL_STORE"] == "1" else {
            throw XCTSkip("Zet TEST_RUNNER_V1_REAL_STORE=1 om de échte v1-container te lezen.")
        }
        let directory = V1StoreReader.defaultStoreDirectory()
        print("V1REAL: store directory = \(directory.path)")

        let library = try V1StoreReader.read(storeDirectory: directory)
        print("V1REAL: \(library.portraits.count) portraits, \(library.skippedWithoutCutout) without cutout")
        for portrait in library.portraits {
            print("V1REAL: \(portrait.id.uuidString) name=\"\(portrait.name)\" tags=\"\(portrait.tags)\" "
                  + "cutout=\(portrait.cutoutPNG.count)B original=\(portrait.originalImage?.count ?? 0)B "
                  + "created=\(portrait.createdAt) updated=\(portrait.updatedAt)")
        }
        XCTAssertGreaterThan(library.portraits.count + library.skippedWithoutCutout, 0,
                             "een lege ZPORTRAIT-tabel op deze Mac — niets om te testen")

        // Twee keer importeren in een geïsoleerde store: alles komt binnen, en
        // de tweede ronde dupliceert niets.
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Portrait2.self, Folder2.self, configurations: config)
        let context = ModelContext(container)

        let first = try V1LibraryImporter.importLibrary(library, into: context)
        XCTAssertEqual(first.imported, library.portraits.count)
        XCTAssertEqual(first.duplicates, 0)
        let stored = try context.fetch(FetchDescriptor<Portrait2>())
        XCTAssertEqual(stored.count, library.portraits.count)
        XCTAssertTrue(stored.allSatisfy { $0.folder?.name == V1LibraryImporter.importFolderName })
        print("V1REAL: first import → \(first.userMessage); originals kept: \(stored.filter { $0.originalData != nil }.count)")

        let second = try V1LibraryImporter.importLibrary(library, into: context)
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.duplicates, library.portraits.count)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Portrait2>()).count, library.portraits.count)
        print("V1REAL: second import → \(second.userMessage)")
    }
}
