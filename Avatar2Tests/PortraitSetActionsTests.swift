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
        XCTAssertEqual(receipts.first?.compact, true, "Set background bevestigt compact (pill), niet als toastkaart")
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
        XCTAssertEqual(receipts.first?.compact, true)
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

    // MARK: - Fill in body (E57.3)

    private func fillMapping(canvasW: Int, canvasH: Int, x: Int, y: Int, w: Int, h: Int) -> BackendClient.FillBodyResult.Mapping {
        BackendClient.FillBodyResult.Mapping(
            canvasWidth: canvasW, canvasHeight: canvasH,
            originalX: x, originalY: y, originalWidth: w, originalHeight: h
        )
    }

    func testFillBodySnapshotsCompensateTransformAndKeepSignatureGuard() throws {
        let context = try makeContext()
        let ps = seed(context)
        let old = png(w: 8, h: 8)
        ps[0].cutoutData = old
        ps[0].offsetX = 20
        ps[0].offsetY = -5
        ps[0].scale = 0.75
        // Links 4 px aangevuld: het origineel zit op x = 4 in een 12×8-canvas.
        let result = NSImage(data: png(w: 12, h: 8))!
        let mapping = fillMapping(canvasW: 12, canvasH: 8, x: 4, y: 0, w: 8, h: 8)
        let signature = Portrait2.cutoutSignature(old)

        let snapshots = try XCTUnwrap(PortraitSetActions.fillBodySnapshots(
            applying: result, mapping: mapping, to: ps[0], expectedCutoutSignature: signature
        ))
        XCTAssertEqual(snapshots.before.cutoutData, old)
        XCTAssertEqual(snapshots.before.transform, TransformUndo.Snapshot(offsetX: 20, offsetY: -5, scale: 0.75))
        XCTAssertTrue(snapshots.before.derivesFromOriginal)
        XCTAssertFalse(snapshots.after.derivesFromOriginal, "een gevuld lichaam is geen schone isolatie meer")
        XCTAssertEqual(PortraitSetActions.pngPixelWidth(snapshots.after.cutoutData), 12)
        // Zelfde geometrie als de editor: bestaande pixels blijven op hun plek.
        let expected = try XCTUnwrap(ShellModel.compensatedFillBodyTransform(
            oldSize: CGSize(width: 8, height: 8), newSize: CGSize(width: 12, height: 8),
            mapping: mapping, current: snapshots.before.transform
        ))
        XCTAssertEqual(snapshots.after.transform, expected)
        XCTAssertEqual(ps[0].cutoutData, old, "de pure stap past niets toe")

        // Tussentijds bewerkt portret (andere signature) → nil, niets gokken.
        XCTAssertNil(PortraitSetActions.fillBodySnapshots(
            applying: result, mapping: mapping, to: ps[0], expectedCutoutSignature: signature &+ 1
        ))
        // Mapping die niet op het resultaat past → nil.
        XCTAssertNil(PortraitSetActions.fillBodySnapshots(
            applying: result, mapping: fillMapping(canvasW: 20, canvasH: 8, x: 4, y: 0, w: 8, h: 8),
            to: ps[0], expectedCutoutSignature: signature
        ))
    }

    func testApplyFilledBodiesIsOneUndoGroupWithoutReshuffle() throws {
        let context = try makeContext()
        let ps = seed(context)
        let old = png(w: 8, h: 8), filled = png(w: 12, h: 8)
        for p in ps { p.cutoutData = old; p.scale = 0.75 }
        let stamps = ps.map(\.updatedAt)
        let um = UndoManager()
        var changed: [String] = []
        let reporter = SetActionReporter(busy: { _ in }, done: { _ in }, portraitDidChange: { changed.append($0.name) })
        let before = PortraitSetActions.FillBodySnapshot(of: ps[0])
        let after = PortraitSetActions.FillBodySnapshot(
            cutoutData: filled,
            transform: TransformUndo.Snapshot(offsetX: 1, offsetY: 2, scale: 0.5),
            derivesFromOriginal: false
        )

        let n = PortraitSetActions.applyFilledBodies(
            [(ps[0], before, after), (ps[2], before, after), (ps[1], before, before)],
            undoManager: um, reporter: reporter
        )
        XCTAssertEqual(n, 2, "ongewijzigde snapshot telt niet")
        XCTAssertEqual(ps[0].cutoutData, filled)
        XCTAssertEqual(ps[0].scale, 0.5)
        XCTAssertEqual(ps[0].offsetX, 1)
        XCTAssertEqual(ps[2].offsetY, 2)
        XCTAssertFalse(ps[0].cutoutDerivesFromOriginal)
        XCTAssertEqual(ps[1].cutoutData, old)
        XCTAssertEqual(ps.map(\.updatedAt), stamps, "Fill in body herschudt het raster niet")
        XCTAssertEqual(order(ps), ["Anna", "Bob", "Cas"])
        XCTAssertEqual(changed, ["Anna", "Cas"])
        XCTAssertEqual(um.undoActionName, "Fill in body")

        um.undo()
        XCTAssertEqual(ps[0].cutoutData, old, "⌘Z draait de hele batch terug")
        XCTAssertEqual(ps[2].cutoutData, old)
        XCTAssertEqual(ps[0].scale, 0.75)
        XCTAssertTrue(ps[0].cutoutDerivesFromOriginal)
        XCTAssertEqual(ps.map(\.updatedAt), stamps)
        um.redo()
        XCTAssertEqual(ps[2].cutoutData, filled)
        XCTAssertEqual(
            PortraitSetActions.applyFilledBodies([], undoManager: um, reporter: .silent), 0
        )
    }

    func testFillBodyReceiptCopy() {
        let um = UndoManager()
        let one = PortraitSetActions.fillBodyReceipt(applied: 1, total: 1, nothingToFill: 0, failed: 0, outOfCredits: false, undoManager: um)
        XCTAssertEqual(one.title, "Body completed", "één portret: zelfde copy als de editor")
        XCTAssertEqual(one.detail, "Only the cropped edge was filled.")
        XCTAssertEqual(one.actionName, "Fill in body")

        let all = PortraitSetActions.fillBodyReceipt(applied: 3, total: 3, nothingToFill: 0, failed: 0, outOfCredits: false, undoManager: um)
        XCTAssertEqual(all.title, "Filled in body on 3 portraits")
        XCTAssertNil(all.detail)

        let partial = PortraitSetActions.fillBodyReceipt(applied: 1, total: 4, nothingToFill: 2, failed: 1, outOfCredits: false, undoManager: um)
        XCTAssertEqual(partial.title, "Filled in body on 1 of 4 portraits")
        XCTAssertEqual(partial.detail, "2 had nothing to fill. 1 couldn't be filled.")
        XCTAssertTrue(partial.canUndo)

        let credits = PortraitSetActions.fillBodyReceipt(applied: 2, total: 3, nothingToFill: 0, failed: 0, outOfCredits: true, undoManager: um)
        XCTAssertEqual(credits.detail, "Ran out of credits for the rest.")

        let nothingOne = PortraitSetActions.fillBodyReceipt(applied: 0, total: 1, nothingToFill: 1, failed: 0, outOfCredits: false, undoManager: um)
        XCTAssertEqual(nothingOne.title, "Nothing to fill")
        XCTAssertEqual(nothingOne.detail, "No cropped body edge was found. Try Auto-frame & center instead.")
        XCTAssertFalse(nothingOne.canUndo)
        let nothingAll = PortraitSetActions.fillBodyReceipt(applied: 0, total: 3, nothingToFill: 3, failed: 0, outOfCredits: false, undoManager: um)
        XCTAssertEqual(nothingAll.title, "Nothing to fill on 3 portraits")

        let none = PortraitSetActions.fillBodyReceipt(applied: 0, total: 2, nothingToFill: 1, failed: 1, outOfCredits: false, undoManager: um)
        XCTAssertEqual(none.title, "Couldn't fill in the body")
        XCTAssertEqual(none.detail, "Please try again.")
        let broke = PortraitSetActions.fillBodyReceipt(applied: 0, total: 2, nothingToFill: 0, failed: 0, outOfCredits: true, undoManager: um)
        XCTAssertEqual(broke.title, "Out of credits — nothing filled in")
        XCTAssertFalse(broke.canUndo)
    }

    // MARK: - Apply effect (E57.4)

    private var watercolor: RemoteEffect {
        RemoteEffect(key: "watercolor", label: "Watercolor", thumbnailUrl: nil, order: 1, composition: .portrait)
    }

    func testEffectStepDistinguishesActiveCachedAndGenerate() throws {
        let context = try makeContext()
        let ps = seed(context)
        let choice = PortraitSetActions.EffectChoice.builtin(watercolor)
        XCTAssertEqual(PortraitSetActions.effectStep(for: ps[0], choice: choice), .generate)
        ps[1].effectCache = ["watercolor": Data([9])]
        XCTAssertEqual(PortraitSetActions.effectStep(for: ps[1], choice: choice), .cached, "in de cache = gratis")
        ps[2].effectActiveRaw = "watercolor"
        XCTAssertEqual(PortraitSetActions.effectStep(for: ps[2], choice: choice), .alreadyActive)
        XCTAssertEqual(PortraitSetActions.effectGenerationCount(ps, choice: choice), 1, "alleen wie écht genereert telt")
        // None: altijd lokaal; al None = niets te doen.
        XCTAssertEqual(PortraitSetActions.effectStep(for: ps[2], choice: .none), .cached)
        XCTAssertEqual(PortraitSetActions.effectStep(for: ps[0], choice: .none), .alreadyActive)
        XCTAssertEqual(PortraitSetActions.effectGenerationCount(ps, choice: .none), 0)
    }

    func testEffectChoiceKeyLabelAndDieCut() {
        let sticker = RemoteEffect(key: "sticker", label: "Sticker", thumbnailUrl: nil, order: 2, composition: .dieCut)
        let custom = RemoteCustomEffect(id: "abc", label: "My style", thumbnailUrl: nil, order: 0)
        XCTAssertNil(PortraitSetActions.EffectChoice.none.key)
        XCTAssertEqual(PortraitSetActions.EffectChoice.none.label, "None")
        XCTAssertEqual(PortraitSetActions.EffectChoice.builtin(sticker).key, "sticker")
        XCTAssertTrue(PortraitSetActions.EffectChoice.builtin(sticker).isDieCut)
        XCTAssertFalse(PortraitSetActions.EffectChoice.builtin(watercolor).isDieCut)
        XCTAssertEqual(PortraitSetActions.EffectChoice.custom(custom).key, "custom:abc")
        XCTAssertFalse(PortraitSetActions.EffectChoice.custom(custom).isDieCut)
    }

    func testRegisterEffectUndoRestoresCompleteSnapshotInOneGroup() throws {
        let context = try makeContext()
        let ps = seed(context)
        let base = png(w: 4, h: 4), styled = png(w: 8, h: 8)
        ps[0].cutoutData = base
        ps[0].scale = 1.2
        let before = PortraitSetActions.EffectSnapshot(of: ps[0])
        // Simuleer de toepassing (zoals applyEffectImage + ShellModel dat doen).
        ps[0].effectBaseData = base
        ps[0].cutoutData = styled
        ps[0].scale = 0.6
        ps[0].effectActiveRaw = "watercolor"
        ps[0].effectCache = ["watercolor": styled]
        ps[0].editSourceData = styled
        ps[0].editSourceCutoutSig = Portrait2.cutoutSignature(styled)
        ps[0].cutoutDerivesFromOriginal = false
        let after = PortraitSetActions.EffectSnapshot(of: ps[0])
        let stamp = ps[0].updatedAt
        let um = UndoManager()
        var changed: [String] = []
        let reporter = SetActionReporter(busy: { _ in }, done: { _ in }, portraitDidChange: { changed.append($0.name) })

        let n = PortraitSetActions.registerEffectUndo(
            [(ps[0], before, after), (ps[1], before, before)], undoManager: um, reporter: reporter
        )
        XCTAssertEqual(n, 1, "ongewijzigde snapshot telt niet")
        XCTAssertEqual(um.undoActionName, "Apply effect")
        XCTAssertTrue(changed.isEmpty, "registratie past niets toe")

        um.undo()
        XCTAssertEqual(ps[0].cutoutData, base)
        XCTAssertEqual(ps[0].scale, 1.2)
        XCTAssertNil(ps[0].effectActiveRaw)
        XCTAssertNil(ps[0].effectBaseData)
        XCTAssertTrue(ps[0].effectCache.isEmpty)
        XCTAssertNil(ps[0].editSourceData)
        XCTAssertEqual(ps[0].editSourceCutoutSig, 0)
        XCTAssertTrue(ps[0].cutoutDerivesFromOriginal)
        XCTAssertEqual(ps[0].updatedAt, stamp, "undo herschudt het raster niet")
        XCTAssertEqual(changed, ["Anna"])
        um.redo()
        XCTAssertEqual(ps[0].cutoutData, styled)
        XCTAssertEqual(ps[0].effectActiveRaw, "watercolor")
        XCTAssertEqual(ps[0].effectCache["watercolor"], styled)
        XCTAssertEqual(order(ps), ["Anna", "Bob", "Cas"])
        XCTAssertEqual(
            PortraitSetActions.registerEffectUndo([], undoManager: um, reporter: .silent), 0
        )
    }

    func testEffectReceiptCopy() {
        let um = UndoManager()
        let wc = PortraitSetActions.EffectChoice.builtin(watercolor)
        let one = PortraitSetActions.effectReceipt(choice: wc, applied: 1, total: 1, skipped: 0, failed: 0, refused: 0, outOfCredits: false, undoManager: um)
        XCTAssertEqual(one.title, "Applied Watercolor to 1 portrait")
        XCTAssertNil(one.detail)
        XCTAssertEqual(one.actionName, "Apply effect")

        let partial = PortraitSetActions.effectReceipt(choice: wc, applied: 2, total: 5, skipped: 1, failed: 1, refused: 1, outOfCredits: false, undoManager: um)
        XCTAssertEqual(partial.title, "Applied Watercolor to 2 of 5 portraits")
        XCTAssertEqual(partial.detail, "1 already had it. 1 couldn't be styled. 1 declined by the safety filter.")

        let credits = PortraitSetActions.effectReceipt(choice: wc, applied: 1, total: 3, skipped: 0, failed: 0, refused: 0, outOfCredits: true, undoManager: um)
        XCTAssertEqual(credits.detail, "Ran out of credits for the rest.")
        XCTAssertTrue(credits.canUndo)

        let already = PortraitSetActions.effectReceipt(choice: wc, applied: 0, total: 2, skipped: 2, failed: 0, refused: 0, outOfCredits: false, undoManager: um)
        XCTAssertEqual(already.title, "Watercolor is already applied")
        XCTAssertFalse(already.canUndo)
        let refused = PortraitSetActions.effectReceipt(choice: wc, applied: 0, total: 2, skipped: 0, failed: 0, refused: 2, outOfCredits: false, undoManager: um)
        XCTAssertEqual(refused.title, "Declined by the safety filter")
        XCTAssertEqual(refused.detail, "Try a different photo. No credits were used.")
        let failed = PortraitSetActions.effectReceipt(choice: wc, applied: 0, total: 2, skipped: 0, failed: 2, refused: 0, outOfCredits: false, undoManager: um)
        XCTAssertEqual(failed.title, "Couldn't apply Watercolor")
        let broke = PortraitSetActions.effectReceipt(choice: wc, applied: 0, total: 2, skipped: 0, failed: 0, refused: 0, outOfCredits: true, undoManager: um)
        XCTAssertEqual(broke.title, "Out of credits — nothing applied")

        let removed = PortraitSetActions.effectReceipt(choice: .none, applied: 3, total: 3, skipped: 0, failed: 0, refused: 0, outOfCredits: false, undoManager: um)
        XCTAssertEqual(removed.title, "Removed effect on 3 portraits")
        let nothing = PortraitSetActions.effectReceipt(choice: .none, applied: 0, total: 2, skipped: 2, failed: 0, refused: 0, outOfCredits: false, undoManager: um)
        XCTAssertEqual(nothing.title, "No effect to remove")
    }

    // MARK: - Stop tussen twee portretten (E57.5)

    func testStoppedBatchesKeepWhatIsDoneAndSaySo() {
        let um = UndoManager()
        let boost = PortraitSetActions.boostReceipt(applied: 2, total: 5, failed: 0, outOfCredits: false, cancelled: true, undoManager: um)
        XCTAssertEqual(boost.title, "Boosted resolution on 2 of 5 portraits")
        XCTAssertEqual(boost.detail, "Stopped. The rest is unchanged.")
        XCTAssertTrue(boost.canUndo, "wat klaar is blijft — en is terug te draaien")
        let boostNothing = PortraitSetActions.boostReceipt(applied: 0, total: 3, failed: 0, outOfCredits: false, cancelled: true, undoManager: um)
        XCTAssertEqual(boostNothing.title, "Stopped — nothing boosted yet")
        XCTAssertFalse(boostNothing.canUndo)

        let fill = PortraitSetActions.fillBodyReceipt(applied: 1, total: 4, nothingToFill: 1, failed: 0, outOfCredits: false, cancelled: true, undoManager: um)
        XCTAssertEqual(fill.detail, "1 had nothing to fill. Stopped. The rest is unchanged.")
        let fillNothing = PortraitSetActions.fillBodyReceipt(applied: 0, total: 4, nothingToFill: 0, failed: 0, outOfCredits: false, cancelled: true, undoManager: um)
        XCTAssertEqual(fillNothing.title, "Stopped — nothing filled in yet")

        let effect = PortraitSetActions.effectReceipt(choice: .builtin(watercolor), applied: 1, total: 3, skipped: 0, failed: 0, refused: 0, outOfCredits: false, cancelled: true, undoManager: um)
        XCTAssertEqual(effect.title, "Applied Watercolor to 1 of 3 portraits")
        XCTAssertEqual(effect.detail, "Stopped. The rest is unchanged.")
        let effectNothing = PortraitSetActions.effectReceipt(choice: .builtin(watercolor), applied: 0, total: 3, skipped: 0, failed: 0, refused: 0, outOfCredits: false, cancelled: true, undoManager: um)
        XCTAssertEqual(effectNothing.title, "Stopped — nothing applied yet")
    }

    func testReporterCancelHookDefaultsToNoop() {
        // Bestaande call sites zonder `cancel:` blijven compileren en werken.
        let reporter = SetActionReporter(busy: { _ in }, done: { _ in }, portraitDidChange: { _ in })
        reporter.cancel { }
        reporter.cancel(nil)
    }
}
