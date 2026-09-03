// E50.1 — map-brede acties + ⌘A per lens: de pure scope-helpers
// (FolderSetScope: map-filter + lens-volgorde + match-lighting-referentie) en
// de select-all-selectie-semantiek van ShellModel (⌘A / "Select all in folder").

import AppKit
import AvatarKit
import SwiftData
import XCTest
@testable import Avatar2

@MainActor
final class FolderSetScopeTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Portrait2.self, Folder2.self, configurations: config)
        return ModelContext(container)
    }

    /// Drie portretten, waarvan twee in een map — met bewust door elkaar
    /// gegooide updatedAt's zodat de sorteervolgorde iets te bewijzen heeft.
    private func seed(_ context: ModelContext) -> (folder: Folder2, inA: Portrait2, inB: Portrait2, unfiled: Portrait2) {
        let folder = Folder2(name: "Team")
        context.insert(folder)
        let inA = Portrait2(name: "Anna", cutoutData: Data([1]))
        let inB = Portrait2(name: "Bob", cutoutData: Data([2]))
        let unfiled = Portrait2(name: "Zoë", cutoutData: Data([3]))
        for p in [inA, inB, unfiled] { context.insert(p) }
        inA.folder = folder
        inB.folder = folder
        inA.updatedAt = Date(timeIntervalSince1970: 100)   // oudst in de map
        inB.updatedAt = Date(timeIntervalSince1970: 300)   // jongst in de map
        unfiled.updatedAt = Date(timeIntervalSince1970: 200)
        return (folder, inA, inB, unfiled)
    }

    // MARK: - FolderSetScope.items

    func testItemsFiltertOpMapEnSorteertJongsteEerst() throws {
        let context = try makeContext()
        let s = seed(context)
        let all = try context.fetch(FetchDescriptor<Portrait2>())

        let items = FolderSetScope.items(in: all, folderID: s.folder.persistentModelID)

        XCTAssertEqual(items.map(\.name), ["Bob", "Anna"], "alleen de map, jongst bewerkt eerst")
    }

    func testItemsZonderMapIDGeeftAllesInLensVolgorde() throws {
        let context = try makeContext()
        _ = seed(context)
        let all = try context.fetch(FetchDescriptor<Portrait2>())

        let items = FolderSetScope.items(in: all, folderID: nil)

        XCTAssertEqual(items.map(\.name), ["Bob", "Zoë", "Anna"], "nil = alle portretten, updatedAt desc")
    }

    // MARK: - FolderSetScope.matchLightingReference

    func testMatchLightingReferentieIsJongstBewerkt() throws {
        let context = try makeContext()
        let s = seed(context)
        let all = try context.fetch(FetchDescriptor<Portrait2>())
        let items = FolderSetScope.items(in: all, folderID: s.folder.persistentModelID)

        XCTAssertEqual(FolderSetScope.matchLightingReference(items)?.name, "Bob")
        XCTAssertNil(FolderSetScope.matchLightingReference([]), "lege map → geen referentie")
    }

    // MARK: - ShellModel.selectAllPortraits (⌘A / Select all in folder)

    func testSelectAllVervangtSelectieEnZetAnkerOpEerste() throws {
        let context = try makeContext()
        let s = seed(context)
        let all = try context.fetch(FetchDescriptor<Portrait2>())
        let ordered = FolderSetScope.items(in: all, folderID: s.folder.persistentModelID)
            .map(\.persistentModelID)

        let model = ShellModel(entitlement: EntitlementModel(auth: AuthService.isolated()))
        // Bestaande selectie buiten de map wordt VERVANGEN (⌘A = scope, geen union).
        model.selectedPortraitIDs = [s.unfiled.persistentModelID]
        model.selectAllPortraits(ordered)

        XCTAssertEqual(model.selectedPortraitIDs, Set(ordered))
        XCTAssertFalse(model.selectedPortraitIDs.contains(s.unfiled.persistentModelID))
        // Anker = eerste item → een ⇧-klik erna gedraagt zich Finder-achtig:
        // bereik vanaf de kop van de lens-volgorde.
        model.handlePortraitClick(s.inA, ordered: ordered, mods: .shift)
        XCTAssertEqual(model.selectedPortraitIDs, Set(ordered), "⇧-klik na ⌘A crasht/leegt niet")
    }

    func testSelectAllMetLegeScopeIsNoOp() throws {
        let context = try makeContext()
        let s = seed(context)

        let model = ShellModel(entitlement: EntitlementModel(auth: AuthService.isolated()))
        model.selectedPortraitIDs = [s.inA.persistentModelID]
        model.selectAllPortraits([])

        XCTAssertEqual(model.selectedPortraitIDs, [s.inA.persistentModelID], "lege scope laat de selectie staan")
    }
}
