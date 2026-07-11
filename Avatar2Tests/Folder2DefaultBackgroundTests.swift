// E55 — map-standaardachtergrond: model-helpers + import-koppeling.

import SwiftData
import XCTest
@testable import Avatar2

@MainActor
final class Folder2DefaultBackgroundTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Portrait2.self, Folder2.self, configurations: config)
        return ModelContext(container)
    }

    func testGeenDefaultAlsVeldenLeegZijn() throws {
        let folder = Folder2(name: "Team")
        XCTAssertNil(folder.defaultBackground)
    }

    func testSetDefaultBackgroundKleur() throws {
        let folder = Folder2(name: "Team")
        folder.setDefaultBackground(.color("#112233"))
        XCTAssertEqual(folder.defaultBackground, .color("#112233"))
        XCTAssertNil(folder.defaultBackgroundImageData)
    }

    func testSetDefaultBackgroundAfbeelding() throws {
        let folder = Folder2(name: "Team")
        let data = Data([1, 2, 3, 4])
        folder.setDefaultBackground(.image(data))
        XCTAssertEqual(folder.defaultBackground, .image(data))
        XCTAssertNil(folder.defaultBackgroundColorHex)
    }

    func testTransparentWistDefault() throws {
        let folder = Folder2(name: "Team")
        folder.setDefaultBackground(.color("#AABBCC"))
        folder.setDefaultBackground(.transparent)
        XCTAssertNil(folder.defaultBackground)
    }

    func testAttachImportPlaatstInMapEnPastDefaultToe() throws {
        let context = try makeContext()
        let folder = Folder2(name: "OPP")
        folder.setDefaultBackground(.color("#445566"))
        context.insert(folder)
        let portrait = Portrait2(name: "New", cutoutData: Data([9]))
        context.insert(portrait)

        FolderImportSupport.attachImport(
            portrait: portrait,
            section: .portraits,
            selectedFolderID: folder.persistentModelID,
            modelContext: context
        )

        XCTAssertTrue(portrait.folder === folder)
        XCTAssertEqual(portrait.background, .color("#445566"))
    }

    func testAttachImportNegeertHomeEnAllPortraits() throws {
        let context = try makeContext()
        let folder = Folder2(name: "OPP")
        folder.setDefaultBackground(.color("#445566"))
        context.insert(folder)
        let portrait = Portrait2(name: "New", cutoutData: Data([9]))
        context.insert(portrait)

        FolderImportSupport.attachImport(
            portrait: portrait,
            section: .home,
            selectedFolderID: folder.persistentModelID,
            modelContext: context
        )
        XCTAssertNil(portrait.folder)
        XCTAssertEqual(portrait.background, .transparent)

        FolderImportSupport.attachImport(
            portrait: portrait,
            section: .portraits,
            selectedFolderID: nil,
            modelContext: context
        )
        XCTAssertNil(portrait.folder)
    }

    func testAttachImportZonderDefaultAlleenMap() throws {
        let context = try makeContext()
        let folder = Folder2(name: "OPP")
        context.insert(folder)
        let portrait = Portrait2(name: "New", cutoutData: Data([9]))
        context.insert(portrait)

        FolderImportSupport.attachImport(
            portrait: portrait,
            section: .portraits,
            selectedFolderID: folder.persistentModelID,
            modelContext: context
        )

        XCTAssertTrue(portrait.folder === folder)
        XCTAssertEqual(portrait.background, .transparent)
    }
}
