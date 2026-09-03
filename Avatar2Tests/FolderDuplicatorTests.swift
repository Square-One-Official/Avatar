// E50.5 — map dupliceren mét inhoud: kopienaam, diepe portret-kopie,
// map-default-achtergrond, lens-volgorde en de undo/redo-groep.

import AvatarKit
import SwiftData
import XCTest
@testable import Avatar2

@MainActor
final class FolderDuplicatorTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Portrait2.self, Folder2.self, configurations: config)
        return ModelContext(container)
    }

    /// Map met twee portretten in bewust omgekeerde updatedAt-volgorde, plus
    /// één portret buiten de map dat NIET mee mag.
    private func seed(_ context: ModelContext) -> (folder: Folder2, old: Portrait2, young: Portrait2, unfiled: Portrait2) {
        let folder = Folder2(name: "Team")
        folder.setDefaultBackground(.color("#112233"))
        context.insert(folder)
        let old = Portrait2(name: "Anna", role: "CEO", cutoutData: Data([1, 2, 3]), originalData: Data([9]))
        let young = Portrait2(name: "Bob", cutoutData: Data([4]))
        let unfiled = Portrait2(name: "Zoë", cutoutData: Data([5]))
        for p in [old, young, unfiled] { context.insert(p) }
        old.folder = folder
        young.folder = folder
        old.updatedAt = Date(timeIntervalSince1970: 100)
        young.updatedAt = Date(timeIntervalSince1970: 300)
        return (folder, old, young, unfiled)
    }

    // MARK: - copyName

    func testCopyNameFinderStijlEnUniek() {
        XCTAssertEqual(FolderDuplicator.copyName(for: "Team", existingNames: ["Team"]), "Team copy")
        XCTAssertEqual(
            FolderDuplicator.copyName(for: "Team", existingNames: ["Team", "team copy"]),
            "Team copy 2", "hoofdletter-ongevoelig uniek"
        )
        XCTAssertEqual(
            FolderDuplicator.copyName(for: "Team", existingNames: ["Team", "Team copy", "Team copy 2"]),
            "Team copy 3"
        )
        XCTAssertEqual(FolderDuplicator.copyName(for: "  ", existingNames: []), "Untitled folder copy")
    }

    // MARK: - duplicate

    func testDuplicateKopieertMapMetInhoudEnDefaultAchtergrond() throws {
        let context = try makeContext()
        let s = seed(context)

        let copy = FolderDuplicator.duplicate(
            s.folder, existingNames: ["Team"], in: context, now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(copy.folder.name, "Team copy")
        XCTAssertEqual(copy.folder.defaultBackground, .color("#112233"), "map-default gaat mee")
        XCTAssertEqual(copy.portraits.count, 2, "alleen de inhoud van de map, niet 'Zoë'")
        XCTAssertTrue(copy.portraits.allSatisfy { $0.folder === copy.folder })
        XCTAssertEqual(copy.portraits.map(\.name), ["Anna", "Bob"], "bronvolgorde oudst → jongst")
        XCTAssertLessThan(copy.portraits[0].updatedAt, copy.portraits[1].updatedAt, "onderlinge volgorde blijft in de lens")
        XCTAssertGreaterThan(copy.portraits[0].updatedAt, s.young.updatedAt, "kopieën landen bovenaan")

        let folders = try context.fetch(FetchDescriptor<Folder2>())
        let portraits = try context.fetch(FetchDescriptor<Portrait2>())
        XCTAssertEqual(folders.count, 2)
        XCTAssertEqual(portraits.count, 5)
        XCTAssertEqual(s.folder.portraits.count, 2, "origineel onaangeraakt")
    }

    func testPortraitDuplicateIsDiepEnResetBoardEnHistorie() throws {
        let context = try makeContext()
        let original = Portrait2(name: "Anna", role: "CEO", cutoutData: Data([1, 2, 3]), originalData: Data([9]))
        context.insert(original)
        original.setBackground(.image(Data([7, 7])))
        original.adjust = PortraitAdjust(exposure: 0.2, contrast: 1.1, saturation: 0.9, temperature: -0.1)
        original.frameShape = .square
        original.offsetX = 10; original.offsetY = 20; original.scale = 1.5
        original.effectActiveRaw = "sketch"
        original.effectCache = ["sketch": Data([3, 3])]
        original.effectBaseData = Data([1, 2, 3])
        original.portraitBlur = true
        original.cutoutDerivesFromOriginal = false
        original.setBannerBackground(.color("#abcdef"))
        original.boardX = 5; original.boardY = 6; original.boardPlaced = true
        original.lastOpenedAt = .now
        original.v1ImportID = "v1-uuid"

        let copy = original.duplicate()

        XCTAssertEqual(copy.name, "Anna")
        XCTAssertEqual(copy.role, "CEO")
        XCTAssertEqual(copy.cutoutData, original.cutoutData)
        XCTAssertEqual(copy.originalData, original.originalData)
        XCTAssertEqual(copy.background, .image(Data([7, 7])))
        XCTAssertEqual(copy.adjust, original.adjust)
        XCTAssertEqual(copy.frameShape, .square)
        XCTAssertEqual(copy.offsetX, 10); XCTAssertEqual(copy.offsetY, 20); XCTAssertEqual(copy.scale, 1.5)
        XCTAssertEqual(copy.effectActiveRaw, "sketch")
        XCTAssertEqual(copy.effectCache, ["sketch": Data([3, 3])], "effect-cache mee: schakelen blijft gratis")
        XCTAssertEqual(copy.effectBaseData, Data([1, 2, 3]))
        XCTAssertTrue(copy.portraitBlur)
        XCTAssertFalse(copy.cutoutDerivesFromOriginal)
        XCTAssertEqual(copy.bannerBackground, .color("#abcdef"))
        XCTAssertFalse(copy.boardPlaced, "board-lens van de nieuwe map doet z'n eigen layout")
        XCTAssertNil(copy.lastOpenedAt)
        XCTAssertNil(copy.v1ImportID, "dedup-sleutel hoort bij het origineel")
        XCTAssertNil(copy.folder)
    }

    // MARK: - perform + undo/redo

    func testPerformMeldtBonEnUndoVerwijdertKopieRedoMaaktNieuwe() throws {
        let context = try makeContext()
        let s = seed(context)
        let undo = UndoManager()
        undo.groupsByEvent = false
        var receipts: [SetActionReceipt] = []
        var undone: [Folder2] = []
        let reporter = SetActionReporter(busy: { _ in }, done: { receipts.append($0) }, portraitDidChange: { _ in })

        undo.beginUndoGrouping()
        let copy = FolderDuplicator.perform(
            s.folder, existingNames: ["Team"], modelContext: context,
            undoManager: undo, reporter: reporter, onUndo: { undone.append($0) }
        )
        undo.endUndoGrouping()

        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts.first?.title, "Folder duplicated with 2 portraits")
        XCTAssertEqual(receipts.first?.actionName, FolderDuplicator.actionName)
        XCTAssertTrue(receipts.first?.compact == true)
        XCTAssertTrue(undo.canUndo)
        XCTAssertEqual(undo.undoActionName, FolderDuplicator.actionName)

        XCTAssertTrue(receipts.first?.performUndo() == true)
        XCTAssertEqual(undone.map { $0 === copy.folder }, [true], "onUndo krijgt de verwijderde kopie")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Folder2>()).count, 1, "kopie-map weg")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Portrait2>()).count, 3, "gekopieerde portretten weg, origineel blijft")
        XCTAssertEqual(s.folder.portraits.count, 2)

        XCTAssertTrue(undo.canRedo)
        undo.redo()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Folder2>()).count, 2, "redo dupliceert opnieuw")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Portrait2>()).count, 5)
        XCTAssertTrue(undo.canUndo, "en is opnieuw terug te draaien")
    }
}
