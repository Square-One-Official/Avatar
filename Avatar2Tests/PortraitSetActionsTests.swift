// E50.3 — set-brede acties herschudden het raster niet (revision i.p.v.
// updatedAt), Match lighting leeft in de Adjust-laag (undo zonder PNG's),
// Reset adjustments is de terugweg, en de bon draait alleen terug wat nog
// bovenop de undo-stack ligt.

import AppKit
import AvatarKit
import SwiftData
import XCTest
@testable import Avatar2

@MainActor
final class PortraitSetActionsTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Portrait2.self, Folder2.self, configurations: config)
        return ModelContext(container)
    }

    /// Drie portretten met bewust verschillende `updatedAt`, zodat de
    /// lens-volgorde iets te bewijzen heeft.
    private func seed(_ context: ModelContext) -> [Portrait2] {
        let a = Portrait2(name: "Anna", cutoutData: Data([1]))
        let b = Portrait2(name: "Bob", cutoutData: Data([2]))
        let c = Portrait2(name: "Cas", cutoutData: Data([3]))
        for p in [a, b, c] { context.insert(p) }
        a.updatedAt = Date(timeIntervalSince1970: 300)
        b.updatedAt = Date(timeIntervalSince1970: 200)
        c.updatedAt = Date(timeIntervalSince1970: 100)
        return [a, b, c]
    }

    private let sample = PortraitAdjust(brightness: 0.2, contrast: 1.1, saturation: 1, temperature: -0.3)

    private func order(_ ps: [Portrait2]) -> [String] {
        FolderSetScope.items(in: ps, folderID: nil).map(\.name)
    }

    // MARK: - Portrait2.revision

    func testTouchBumpsBothButBumpRevisionOnlyRevision() {
        let p = Portrait2(cutoutData: Data([1]))
        p.updatedAt = Date(timeIntervalSince1970: 100)
        p.touch()
        XCTAssertGreaterThan(p.updatedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(p.revision, 1)
        let stamp = p.updatedAt
        p.bumpRevision()
        XCTAssertEqual(p.revision, 2)
        XCTAssertEqual(p.updatedAt, stamp)
        p.setBackground(.color("#112233"), recordsEdit: false)
        XCTAssertEqual(p.revision, 3)
        XCTAssertEqual(p.updatedAt, stamp, "set-brede achtergrond herschudt niet")
        p.updatedAt = Date(timeIntervalSince1970: 100)
        p.setBackground(.transparent)
        XCTAssertEqual(p.revision, 4)
        XCTAssertGreaterThan(p.updatedAt, Date(timeIntervalSince1970: 100), "enkelvoudige edit telt wél als bewerking")
    }

    func testAdjustApplyingSuggestionKeepsSaturation() {
        let current = PortraitAdjust(brightness: 0, contrast: 1, saturation: 1.4, temperature: 0)
        let suggestion = SetLightingNormalizer.AdjustSuggestion(brightness: 0.1, contrast: 1.2, temperature: 0.3)
        let next = PortraitAdjust(applying: suggestion, keepingSaturationOf: current)
        XCTAssertEqual(next, PortraitAdjust(brightness: 0.1, contrast: 1.2, saturation: 1.4, temperature: 0.3))
    }

    // MARK: - Match lighting (Adjust-laag)

    func testMatchedLightingKeepsOrderAndPixels() throws {
        let context = try makeContext()
        let ps = seed(context)
        let before = order(ps)
        let stamps = ps.map(\.updatedAt)
        let um = UndoManager()

        let n = PortraitSetActions.applyMatchedLighting([(ps[2], sample)], undoManager: um, reporter: .silent)

        XCTAssertEqual(n, 1)
        XCTAssertEqual(order(ps), before, "de gematchte tegel springt niet naar boven")
        XCTAssertEqual(ps.map(\.updatedAt), stamps)
        XCTAssertEqual(ps[2].revision, 1)
        XCTAssertEqual(ps[2].adjust, sample)
        XCTAssertEqual(ps[2].cutoutData, Data([3]), "pixels blijven rauw")
        XCTAssertTrue(ps[2].cutoutDerivesFromOriginal)
        XCTAssertEqual(ps[2].editSourceCutoutSig, 0)
        XCTAssertTrue(um.canUndo)
        XCTAssertEqual(um.undoActionName, "Match Lighting")
    }

    func testMatchedLightingUndoRedoWithoutTouching() throws {
        let context = try makeContext()
        let ps = seed(context)
        let stamps = ps.map(\.updatedAt)
        let um = UndoManager()
        PortraitSetActions.applyMatchedLighting([(ps[0], sample), (ps[1], sample)], undoManager: um, reporter: .silent)

        um.undo()
        XCTAssertEqual(ps[0].adjust, .neutral)
        XCTAssertEqual(ps[1].adjust, .neutral)
        XCTAssertEqual(ps.map(\.updatedAt), stamps, "undo herschudt evenmin")
        XCTAssertEqual(ps[0].revision, 2)
        XCTAssertTrue(um.canRedo)

        um.redo()
        XCTAssertEqual(ps[0].adjust, sample)
        XCTAssertEqual(ps[1].adjust, sample)
        XCTAssertEqual(ps[0].revision, 3)
        XCTAssertEqual(ps.map(\.updatedAt), stamps)
    }

    func testApplyMatchedLightingSkipsUnchanged() throws {
        let context = try makeContext()
        let ps = seed(context)
        let um = UndoManager()
        XCTAssertEqual(PortraitSetActions.applyMatchedLighting([(ps[0], .neutral)], undoManager: um, reporter: .silent), 0)
        XCTAssertFalse(um.canUndo)
        XCTAssertEqual(ps[0].revision, 0)
    }

    func testPortraitDidChangeFiresPerAdjustedPortrait() throws {
        let context = try makeContext()
        let ps = seed(context)
        var changed: [String] = []
        let reporter = SetActionReporter(busy: { _ in }, done: { _ in }, portraitDidChange: { changed.append($0.name) })
        let um = UndoManager()

        PortraitSetActions.applyMatchedLighting(
            [(ps[0], sample), (ps[1], .neutral), (ps[2], sample)], undoManager: um, reporter: reporter
        )
        XCTAssertEqual(changed, ["Anna", "Cas"])
        um.undo()
        XCTAssertEqual(changed.count, 4, "undo meldt de portretten opnieuw (canvas-refresh)")
    }

    // MARK: - Reset adjustments

    func testResetAdjustSkipsNeutralAndIsUndoable() throws {
        let context = try makeContext()
        let ps = seed(context)
        let stamps = ps.map(\.updatedAt)
        ps[0].adjust = sample
        var receipts: [SetActionReceipt] = []
        let reporter = SetActionReporter(busy: { _ in }, done: { receipts.append($0) }, portraitDidChange: { _ in })
        let um = UndoManager()

        PortraitSetActions.resetAdjust([ps[0], ps[1]], undoManager: um, reporter: reporter)

        XCTAssertEqual(ps[0].adjust, .neutral)
        XCTAssertEqual(ps[1].revision, 0, "al-neutraal blijft ongemoeid")
        XCTAssertEqual(ps.map(\.updatedAt), stamps)
        XCTAssertEqual(receipts.map(\.title), ["Reset adjustments on 1 portrait"])
        XCTAssertEqual(receipts.first?.actionName, "Reset Adjustments")
        um.undo()
        XCTAssertEqual(ps[0].adjust, sample)
    }

    func testResetAdjustOnAllNeutralIsNoOp() throws {
        let context = try makeContext()
        let ps = seed(context)
        var receipts: [SetActionReceipt] = []
        let reporter = SetActionReporter(busy: { _ in }, done: { receipts.append($0) }, portraitDidChange: { _ in })
        let um = UndoManager()
        PortraitSetActions.resetAdjust(ps, undoManager: um, reporter: reporter)
        XCTAssertTrue(receipts.isEmpty)
        XCTAssertFalse(um.canUndo)
    }

    // MARK: - Match framing

    func testMatchedFramingKeepsOrder() throws {
        let context = try makeContext()
        let ps = seed(context)
        let before = order(ps)
        let stamps = ps.map(\.updatedAt)
        let um = UndoManager()
        let transforms = [
            AutoFramer.Transform(scale: 1.2, offset: CGSize(width: 10, height: -5)),
            AutoFramer.Transform(scale: 0, offset: .zero),
        ]

        let n = PortraitSetActions.applyMatchedFraming([ps[0], ps[1]], transforms: transforms, undoManager: um, reporter: .silent)

        XCTAssertEqual(n, 1, "identieke transform = geen wijziging")
        XCTAssertEqual(ps[0].scale, 1.2)
        XCTAssertEqual(ps[0].offsetX, 10)
        XCTAssertEqual(ps[0].offsetY, -5)
        XCTAssertEqual(order(ps), before)
        XCTAssertEqual(ps.map(\.updatedAt), stamps)
        XCTAssertEqual(ps[0].revision, 1)
        XCTAssertEqual(um.undoActionName, "Match Framing")
        um.undo()
        XCTAssertEqual(ps[0].scale, 0)
        XCTAssertEqual(ps.map(\.updatedAt), stamps)
    }

    // MARK: - Set background

    func testSetBackgroundKeepsOrderAndReports() throws {
        let context = try makeContext()
        let ps = seed(context)
        let before = order(ps)
        let stamps = ps.map(\.updatedAt)
        var receipts: [SetActionReceipt] = []
        let reporter = SetActionReporter(busy: { _ in }, done: { receipts.append($0) }, portraitDidChange: { _ in })
        let um = UndoManager()

        PortraitSetActions.setBackground(ps, .color("#FF0000"), undoManager: um, reporter: reporter)

        XCTAssertEqual(ps.map(\.background), Array(repeating: PortraitBackground.color("#FF0000"), count: 3))
        XCTAssertEqual(order(ps), before)
        XCTAssertEqual(ps.map(\.updatedAt), stamps)
        XCTAssertEqual(receipts.map(\.title), ["Set background on 3 portraits"])
        XCTAssertEqual(receipts.first?.actionName, "Background")
        um.undo()
        XCTAssertEqual(ps[0].background, .transparent)
        XCTAssertEqual(ps.map(\.updatedAt), stamps)
    }

    func testUseFolderBackgroundAppliesOnlyWhereItDiffers() throws {
        let context = try makeContext()
        let ps = seed(context)
        let folder = Folder2(name: "Team")
        context.insert(folder)
        folder.setDefaultBackground(.color("#ABCDEF"))
        ps[0].folder = folder
        ps[1].folder = folder
        ps[1].setBackground(.color("#ABCDEF")) // heeft 'm al
        // ps[2] blijft unfiled → geen map-default.
        let stamps = ps.map(\.updatedAt)
        let before = order(ps)
        var receipts: [SetActionReceipt] = []
        let reporter = SetActionReporter(busy: { _ in }, done: { receipts.append($0) }, portraitDidChange: { _ in })
        let um = UndoManager()

        XCTAssertTrue(PortraitSetActions.canUseFolderBackground(ps[0]))
        XCTAssertFalse(PortraitSetActions.canUseFolderBackground(ps[1]))
        XCTAssertFalse(PortraitSetActions.canUseFolderBackground(ps[2]))

        PortraitSetActions.useFolderBackground(ps, undoManager: um, reporter: reporter)

        XCTAssertEqual(ps[0].background, .color("#ABCDEF"))
        XCTAssertEqual(ps[2].background, .transparent, "zonder map-default ongemoeid")
        XCTAssertEqual(ps.map(\.updatedAt), stamps)
        XCTAssertEqual(order(ps), before)
        XCTAssertEqual(receipts.map(\.title), ["Set folder background on 1 portrait"])
        um.undo()
        XCTAssertEqual(ps[0].background, .transparent)
        XCTAssertFalse(PortraitSetActions.canUseFolderBackground(ps[1]))
    }

    func testUseFolderBackgroundWithNothingToDoReportsWithoutUndo() throws {
        let context = try makeContext()
        let ps = seed(context)
        var receipts: [SetActionReceipt] = []
        let reporter = SetActionReporter(busy: { _ in }, done: { receipts.append($0) }, portraitDidChange: { _ in })
        let um = UndoManager()
        PortraitSetActions.useFolderBackground(ps, undoManager: um, reporter: reporter)
        XCTAssertEqual(receipts.map(\.title), ["Folder background already set"])
        XCTAssertNil(receipts.first?.actionName)
        XCTAssertFalse(um.canUndo)
    }

    // MARK: - Receipt

    func testReceiptUndoesOnlyWhenOnTop() throws {
        let context = try makeContext()
        let ps = seed(context)
        let um = UndoManager()
        PortraitSetActions.applyMatchedLighting([(ps[0], sample)], undoManager: um, reporter: .silent)
        let receipt = SetActionReceipt(title: "x", actionName: "Match Lighting", undoManager: um)

        XCTAssertTrue(receipt.canUndo)
        XCTAssertTrue(receipt.performUndo())
        XCTAssertEqual(ps[0].adjust, .neutral)
        XCTAssertFalse(receipt.performUndo(), "niets meer bovenop")

        // Een andere stap erbovenop → de bon laat de stack met rust.
        PortraitSetActions.applyMatchedLighting([(ps[0], sample)], undoManager: um, reporter: .silent)
        um.beginUndoGrouping()
        um.setActionName("Rename")
        um.registerUndo(withTarget: ps[1]) { _ in }
        um.endUndoGrouping()
        XCTAssertFalse(receipt.performUndo())
        XCTAssertEqual(ps[0].adjust, sample)

        XCTAssertNil(SetActionReceipt(title: "x", actionName: nil, undoManager: um).toastDescription)
        XCTAssertEqual(
            SetActionReceipt(title: "x", detail: "D.", actionName: "A", undoManager: um).toastDescription,
            "D. ⌘Z also undoes this."
        )
    }

    // MARK: - Reporter (ShellModel)

    func testReporterBusyNilKeepsDoneReceipt() {
        let model = ShellModel(entitlement: EntitlementModel(auth: AuthService.isolated()))
        let reporter = model.setActionReporter

        reporter.busy("Matching lighting…")
        XCTAssertTrue(model.isSetActionBusy)
        let receipt = SetActionReceipt(title: "Matched 1 portrait to Bob", actionName: "Match Lighting", undoManager: nil)
        reporter.done(receipt)
        reporter.busy(nil) // de `defer` van de actie
        XCTAssertEqual(model.setActionToast, .done(receipt))
        XCTAssertFalse(model.isSetActionBusy)

        reporter.busy("Exporting…")
        reporter.busy(nil)
        XCTAssertNil(model.setActionToast)
    }

    func testCopyHelpers() {
        XCTAssertEqual(PortraitSetActions.plural(1), "1 portrait")
        XCTAssertEqual(PortraitSetActions.plural(3), "3 portraits")
        XCTAssertEqual(PortraitSetActions.displayName("  "), "Untitled")
        XCTAssertEqual(PortraitSetActions.displayName(" Joline "), "Joline")
    }

    // MARK: - Boost resolution (bulk)

    /// Vaste PNG-bytes op een gegeven pixelmaat (dekkend, alpha aan).
    private func png(w: Int, h: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        for x in 0..<w { for y in 0..<h { rep.setColor(.red, atX: x, y: y) } }
        return rep.representation(using: .png, properties: [:])!
    }

    func testPngPixelWidthReadsHeaderOnly() {
        XCTAssertEqual(PortraitSetActions.pngPixelWidth(png(w: 6, h: 3)), 6)
        XCTAssertNil(PortraitSetActions.pngPixelWidth(Data([1, 2, 3])))
    }

    func testApplyBoostedReplacesCutoutAdjustsScaleAndKeepsOrder() throws {
        let context = try makeContext()
        let ps = seed(context)
        let small = png(w: 4, h: 4), big = png(w: 8, h: 8)
        ps[2].cutoutData = small
        ps[2].scale = 1.5
        let stamp = ps[2].updatedAt
        let um = UndoManager()
        var changed: [String] = []
        let reporter = SetActionReporter(busy: { _ in }, done: { _ in }, portraitDidChange: { changed.append($0.name) })

        let n = PortraitSetActions.applyBoosted([(ps[2], big)], undoManager: um, reporter: reporter)
        XCTAssertEqual(n, 1)
        XCTAssertEqual(ps[2].cutoutData, big)
        XCTAssertEqual(ps[2].scale, 0.75, accuracy: 0.0001, "handmatige schaal volgt de breedte-verhouding")
        XCTAssertFalse(ps[2].cutoutDerivesFromOriginal)
        XCTAssertEqual(ps[2].revision, 1)
        XCTAssertEqual(ps[2].updatedAt, stamp, "Boost herschudt het raster niet")
        XCTAssertEqual(order(ps), ["Anna", "Bob", "Cas"])
        XCTAssertEqual(changed, ["Cas"])
        XCTAssertEqual(um.undoActionName, "Boost Resolution")

        um.undo()
        XCTAssertEqual(ps[2].cutoutData, small)
        XCTAssertEqual(ps[2].scale, 1.5, accuracy: 0.0001)
        XCTAssertTrue(ps[2].cutoutDerivesFromOriginal)
        XCTAssertEqual(ps[2].updatedAt, stamp)
        XCTAssertEqual(ps[2].revision, 2)
        um.redo()
        XCTAssertEqual(ps[2].cutoutData, big)
        XCTAssertEqual(ps[2].scale, 0.75, accuracy: 0.0001)
        XCTAssertEqual(changed, ["Cas", "Cas", "Cas"])
    }

    func testApplyBoostedKeepsAutoScaleAndSkipsUnchanged() throws {
        let context = try makeContext()
        let ps = seed(context)
        let big = png(w: 8, h: 8)
        ps[0].cutoutData = png(w: 4, h: 4)
        ps[1].cutoutData = big
        let um = UndoManager()
        let n = PortraitSetActions.applyBoosted(
            [(ps[0], big), (ps[1], big)], undoManager: um, reporter: .silent
        )
        XCTAssertEqual(n, 1, "identieke bytes tellen niet")
        XCTAssertEqual(ps[0].scale, 0, "auto-fit (0) blijft auto-fit")
        XCTAssertEqual(ps[1].revision, 0)
        XCTAssertEqual(
            PortraitSetActions.applyBoosted([], undoManager: um, reporter: .silent), 0
        )
    }

    func testBoostReceiptCopy() {
        let um = UndoManager()
        let full = PortraitSetActions.boostReceipt(applied: 3, total: 3, failed: 0, outOfCredits: false, undoManager: um)
        XCTAssertEqual(full.title, "Boosted resolution on 3 portraits")
        XCTAssertNil(full.detail)
        XCTAssertEqual(full.actionName, "Boost Resolution")

        let partial = PortraitSetActions.boostReceipt(applied: 1, total: 3, failed: 2, outOfCredits: false, undoManager: um)
        XCTAssertEqual(partial.title, "Boosted resolution on 1 of 3 portraits")
        XCTAssertEqual(partial.detail, "2 portraits couldn't be boosted.")

        let credits = PortraitSetActions.boostReceipt(applied: 2, total: 3, failed: 0, outOfCredits: true, undoManager: um)
        XCTAssertEqual(credits.detail, "Ran out of credits for the rest.")
        XCTAssertTrue(credits.canUndo)

        let none = PortraitSetActions.boostReceipt(applied: 0, total: 2, failed: 2, outOfCredits: false, undoManager: um)
        XCTAssertEqual(none.title, "Couldn't boost the resolution")
        XCTAssertFalse(none.canUndo)
        let broke = PortraitSetActions.boostReceipt(applied: 0, total: 2, failed: 0, outOfCredits: true, undoManager: um)
        XCTAssertEqual(broke.title, "Out of credits — nothing boosted")
    }
}
