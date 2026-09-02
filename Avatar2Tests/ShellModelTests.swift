// E05.3 — canvasstates van de import/isolating-flow. De engine-paden zelf
// zijn in AvatarKit getest (E02.1); hier alleen de state-overgangen die
// zonder echte foto te raken zijn.
// E47.3 — uitgebreid met de drukste ShellModel-paden: import-gate (via de
// E47.1/47.2-stub-sessie), selectie (direct + async canvas-decode),
// effect-apply/re-isolate en de `cutoutSignature`-staleness-stempel.

import AppKit
import AvatarKit
import SwiftData
import XCTest
@testable import Avatar2

@MainActor
final class ShellModelTests: XCTestCase {

    func testStartLeeg() {
        let model = ShellModel(entitlement: EntitlementModel(auth: AuthService()))
        if case .empty = model.canvas {} else {
            XCTFail("verwacht .empty als startstaat")
        }
    }

    func testOnleesbareDataGaatNaarFailed() async {
        let model = ShellModel(entitlement: EntitlementModel(auth: AuthService()))
        await model.importImage(data: Data([0x00, 0x01, 0x02]))
        if case .failed = model.canvas {} else {
            XCTFail("verwacht .failed bij onleesbare data")
        }
    }

    // MARK: - E36.5 (audit-B5): bestandsnaam → default-portretnaam
    // Sinds de naam-extractie (PortraitNameGuess) vult de import alleen een
    // échte persoonsnaam in; camera-/bewerkingsruis levert "" op.

    private func naam(_ file: String) -> String {
        ShellModel.defaultPortraitName(from: URL(fileURLWithPath: "/tmp/\(file)"))
    }

    func testDefaultNaamHaaltPersoonsnaamUitBestandsnaam() {
        XCTAssertEqual(naam("Thierry_Emmery_headshot_2024.jpg"), "Thierry Emmery")
        XCTAssertEqual(naam("anna-de-winter.HEIC"), "Anna de Winter")
        XCTAssertEqual(naam("jan van der berg (1).png"), "Jan van der Berg")
        XCTAssertEqual(naam("Portrait - Sanne Jansen - LinkedIn copy.jpeg"), "Sanne Jansen")
        XCTAssertEqual(naam("ThierryEmmery.png"), "Thierry Emmery")
        XCTAssertEqual(naam("EMMERY_THIERRY.png"), "Emmery Thierry")
        XCTAssertEqual(naam("Anne-Marie O'Neill.png"), "Anne Marie O'Neill")
    }

    func testDefaultNaamIsLeegZonderPersoonsnaam() {
        XCTAssertEqual(naam("IMG_4821.HEIC"), "")
        XCTAssertEqual(naam("DSC00123.jpg"), "")
        XCTAssertEqual(naam("Screenshot 2026-09-02 at 10.12.33.png"), "")
        XCTAssertEqual(naam("headshot-final-v2.png"), "")
        XCTAssertEqual(naam("team.profile.jpeg"), "")
        XCTAssertEqual(naam("p1-man_beard.png"), "Man Beard", "onbekende woorden gelden als naam")
    }

    func testDefaultNaamStriptAlleenBekendeBeeldextensies() {
        XCTAssertEqual(naam("anna.de.winter"), "Anna de Winter")
        XCTAssertEqual(naam("Portrait.png"), "")
    }

    func testDefaultNaamHoudtTussenvoegselsAlleenTussenNaamdelen() {
        XCTAssertEqual(naam("van-anna.png"), "Anna")
        XCTAssertEqual(naam("de_vries_de.png"), "Vries")
        XCTAssertEqual(naam("McDonald_Ronald.png"), "McDonald Ronald")
    }

    // MARK: - E47.3 helpers

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Portrait2.self, configurations: config)
        return ModelContext(container)
    }

    /// RGBA-beeld met transparante hoeken en een opaak middenblok — de vorm
    /// van een echte vrijstaande cutout (passeert `isLikelyCutout`).
    private func cutoutImage(size: Int = 128, shade: UInt8 = 180) -> NSImage {
        rgbaImage(size: size, shade: shade) { x, y in
            let inset = size / 4
            let opaque = x >= inset && x < size - inset && y >= inset && y < size - inset
            return opaque ? 255 : 0
        }
    }

    /// Volledig opaak beeld (onderwerp + achtergrond) — faalt `isLikelyCutout`,
    /// dus het generatieve re-isolate-pad wordt gekozen.
    private func opaqueImage(size: Int = 128, shade: UInt8 = 120) -> NSImage {
        rgbaImage(size: size, shade: shade) { _, _ in 255 }
    }

    private func rgbaImage(size: Int, shade: UInt8, alphaAt: (Int, Int) -> UInt8) -> NSImage {
        let bpr = size * 4
        var buf = [UInt8](repeating: 0, count: bpr * size)
        for y in 0..<size {
            for x in 0..<size {
                let a = alphaAt(x, y)
                let f = Double(a) / 255.0
                let i = y * bpr + x * 4
                buf[i] = UInt8(Double(shade) * f)
                buf[i + 1] = UInt8(Double(shade) * 0.6 * f)
                buf[i + 2] = UInt8(Double(shade) * 0.4 * f)
                buf[i + 3] = a
            }
        }
        let ctx = CGContext(
            data: &buf, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let cg = ctx.makeImage()!
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }

    private func png(_ image: NSImage) throws -> Data {
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
    }

    /// Wacht tot het canvas de async select-decode heeft toegepast (.result).
    private func waitForResultCanvas(_ model: ShellModel, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .result = model.canvas { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("canvas werd niet .result binnen \(timeout)s")
    }

    /// Model + geselecteerd portret op een in-memory store.
    private func makeSelectedModel(
        cutout: NSImage
    ) throws -> (model: ShellModel, portrait: Portrait2, context: ModelContext) {
        let context = try makeContext()
        let portrait = Portrait2(name: "Test", cutoutData: try png(cutout))
        context.insert(portrait)
        let model = ShellModel(entitlement: EntitlementModel(auth: AuthService()))
        model.modelContext = context
        model.select(portrait)
        return (model, portrait, context)
    }

    // MARK: - E47.3: cutoutSignature-staleness (edit-bron-stempel)

    /// De stempel is deterministisch (persisteerbaar over launches, anders dan
    /// `Hasher`) én content-gevoelig — twee even grote maar verschillende
    /// cutouts mogen niet vals matchen (dáárom is het geen count-stempel).
    func testCutoutSignatureDeterministischEnContentGevoelig() {
        let a = Data(repeating: 1, count: 1000)
        let b = Data(repeating: 2, count: 1000)
        XCTAssertEqual(Portrait2.cutoutSignature(a), Portrait2.cutoutSignature(a))
        XCTAssertNotEqual(Portrait2.cutoutSignature(a), Portrait2.cutoutSignature(b),
                          "gelijke grootte, andere inhoud → andere stempel")
        XCTAssertNotEqual(Portrait2.cutoutSignature(a), Portrait2.cutoutSignature(Data()),
                          "lege data krijgt een eigen stempel")
    }

    // MARK: - E47.3: import-gate (E14.2, via de 47.1/47.2-stub-sessie)

    /// Cap bereikt (402 van /v1/import-claim): paywall open, canvas blijft
    /// `.empty` en er komt géén portret in de store — de import is nooit gestart.
    func testImportGeweigerdOpDeCapLaatCanvasEnStoreOngemoeid() async throws {
        EntitlementStubURLProtocol.reset()
        defer { EntitlementStubURLProtocol.reset() }
        EntitlementStubURLProtocol.setStub(.json(402, """
            { "allowed": false, "imports_used": 3, "imports_remaining": 0 }
            """), forPath: "/v1/import-claim")
        let entitlement = EntitlementModel(
            auth: AuthService(), backendSession: EntitlementStubURLProtocol.makeSession()
        )
        let model = ShellModel(entitlement: entitlement)
        let context = try makeContext()
        model.modelContext = context

        await model.importImage(data: try png(opaqueImage()))

        XCTAssertTrue(entitlement.isPaywallPresented, "cap → paywall")
        if case .empty = model.canvas {} else {
            XCTFail("geweigerde import mag het canvas niet wijzigen")
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<Portrait2>()).count, 0,
                       "geweigerde import mag niets persisteren")
    }

    // MARK: - Batch-import (drop van meerdere bestanden blijft in de bibliotheek)

    private func makeLibraryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Portrait2.self, Folder2.self, configurations: config)
        return ModelContext(container)
    }

    private func makeAllowedEntitlement() -> EntitlementModel {
        EntitlementStubURLProtocol.setStub(.json(200, """
            { "allowed": true, "imports_used": 1, "imports_remaining": 2 }
            """), forPath: "/v1/import-claim")
        return EntitlementModel(
            auth: AuthService(), backendSession: EntitlementStubURLProtocol.makeSession()
        )
    }

    /// Meerdere beelden: de studio gaat NIET open — de lens blijft de map, elk
    /// beeld wordt (sequentieel) vrijstaand gemaakt en landt als portret in die
    /// map mét de map-default-achtergrond; de tijdelijke tegels zijn daarna weg
    /// en de verse portretten hebben hun reveal-compositie als placeholder.
    func testBatchImportBlijftInDeMapEnPersisteertAlleBeelden() async throws {
        EntitlementStubURLProtocol.reset()
        defer { EntitlementStubURLProtocol.reset() }
        let model = ShellModel(entitlement: makeAllowedEntitlement())
        let context = try makeLibraryContext()
        model.modelContext = context
        let folder = Folder2(name: "Team")
        context.insert(folder)
        folder.setDefaultBackground(.color("#112233"))
        model.showPortraits(folderID: folder.persistentModelID)
        model.debugCutoutOverride = { $0 }

        await model.importImages([
            .data(try png(opaqueImage(shade: 90))),
            .data(try png(opaqueImage(shade: 200))),
        ])

        XCTAssertEqual(model.section, .portraits, "batch-drop mag de studio niet openen")
        XCTAssertEqual(model.selectedFolderID, folder.persistentModelID)
        XCTAssertNil(model.selectedPortrait, "geen portret op het canvas gezet")
        if case .empty = model.canvas {} else {
            XCTFail("het studio-canvas hoort onaangeraakt (.empty) te blijven")
        }
        let stored = try context.fetch(FetchDescriptor<Portrait2>())
        XCTAssertEqual(stored.count, 2, "élk gedropt beeld wordt een portret")
        XCTAssertTrue(stored.allSatisfy { $0.folder?.persistentModelID == folder.persistentModelID },
                      "landt in de map waarin gedropt is")
        XCTAssertTrue(stored.allSatisfy { $0.backgroundColorHex == "#112233" },
                      "map-default-achtergrond toegepast (zoals het single-pad)")
        XCTAssertTrue(model.libraryImportJobs.isEmpty, "tijdelijke tegels zijn opgeruimd")
        XCTAssertNil(model.libraryImportProgress)
        XCTAssertTrue(stored.allSatisfy { model.freshImportPreview(for: $0) != nil },
                      "verse tegel heeft de reveal-compositie als placeholder")
    }

    /// Tijdens de batch staat er per beeld een tegel in de lens van de map;
    /// Home en "All portraits" tonen ze allemaal, een andere map niets.
    func testBatchImportTegelsVolgenDeLens() async throws {
        EntitlementStubURLProtocol.reset()
        defer { EntitlementStubURLProtocol.reset() }
        let model = ShellModel(entitlement: makeAllowedEntitlement())
        let context = try makeLibraryContext()
        model.modelContext = context
        let folder = Folder2(name: "Team")
        let other = Folder2(name: "Other")
        context.insert(folder)
        context.insert(other)
        model.showPortraits(folderID: folder.persistentModelID)
        var observedJobs: [ShellModel.LibraryImportJob] = []
        model.debugCutoutOverride = { image in
            // Alleen de eerste cutout vastleggen: dan staan beide tegels er nog.
            if observedJobs.isEmpty { observedJobs = await model.libraryImportJobs }
            return image
        }

        await model.importImages([
            .data(try png(opaqueImage(shade: 90))),
            .data(try png(opaqueImage(shade: 200))),
        ])

        XCTAssertEqual(observedJobs.count, 2, "beide beelden hebben een tegel tijdens de eerste cutout")
        XCTAssertTrue(observedJobs.allSatisfy { $0.folderID == folder.persistentModelID })
        // Zichtbaarheid per lens is puur een filter op de jobs.
        model.libraryImportJobsForTesting = observedJobs
        XCTAssertEqual(model.visibleLibraryImportJobs(folderID: nil).count, 2, "Home / All portraits")
        XCTAssertEqual(model.visibleLibraryImportJobs(folderID: folder.persistentModelID).count, 2)
        XCTAssertEqual(model.visibleLibraryImportJobs(folderID: other.persistentModelID).count, 0)
        XCTAssertEqual(model.visibleLibraryImportJobs(folderID: nil).map(\.id),
                       observedJobs.reversed().map(\.id),
                       "omgekeerde drop-volgorde: de kop van de wachtrij grenst aan het grid")
    }

    /// Cap bereikt (402) bij het eerste beeld: paywall open, de hele rest van
    /// de batch vervalt (geen paywall per beeld) en er wordt niets gepersisteerd.
    func testBatchImportStoptOpDeCapZonderRestanten() async throws {
        EntitlementStubURLProtocol.reset()
        defer { EntitlementStubURLProtocol.reset() }
        EntitlementStubURLProtocol.setStub(.json(402, """
            { "allowed": false, "imports_used": 3, "imports_remaining": 0 }
            """), forPath: "/v1/import-claim")
        let entitlement = EntitlementModel(
            auth: AuthService(), backendSession: EntitlementStubURLProtocol.makeSession()
        )
        let model = ShellModel(entitlement: entitlement)
        let context = try makeLibraryContext()
        model.modelContext = context
        model.debugCutoutOverride = { _ in XCTFail("geen cutout na een geweigerde claim"); throw CancellationError() }

        await model.importImages([
            .data(try png(opaqueImage(shade: 90))),
            .data(try png(opaqueImage(shade: 120))),
            .data(try png(opaqueImage(shade: 200))),
        ])

        XCTAssertTrue(entitlement.isPaywallPresented, "cap → paywall")
        XCTAssertEqual(model.section, .home)
        XCTAssertTrue(model.libraryImportJobs.isEmpty, "de rest van de batch vervalt")
        XCTAssertNil(model.libraryImportProgress)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Portrait2>()).count, 0)
    }

    /// Geen persoon gevonden: het beeld wordt niet gepersisteerd, de tegel
    /// blijft even als "failed" staan en ruimt zichzelf op; de batch loopt door.
    func testBatchImportMisluktBeeldRuimtZichzelfOp() async throws {
        EntitlementStubURLProtocol.reset()
        defer { EntitlementStubURLProtocol.reset() }
        let model = ShellModel(entitlement: makeAllowedEntitlement())
        let context = try makeLibraryContext()
        model.modelContext = context
        struct NoPerson: Error {}
        model.debugCutoutOverride = { _ in throw NoPerson() }

        await model.importImages([
            .data(try png(opaqueImage(shade: 90))),
            .data(try png(opaqueImage(shade: 200))),
        ])

        XCTAssertEqual(try context.fetch(FetchDescriptor<Portrait2>()).count, 0)
        XCTAssertEqual(model.libraryImportJobs.count, 2, "mislukte tegels blijven even leesbaar staan")
        XCTAssertTrue(model.libraryImportJobs.allSatisfy {
            if case .failed = $0.phase { return true } else { return false }
        })
        XCTAssertNil(model.libraryImportProgress, "batch is klaar")
        let deadline = Date().addingTimeInterval(5)
        while !model.libraryImportJobs.isEmpty, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.libraryImportJobs.isEmpty, "failed-tegels ruimen zichzelf op")
    }

    /// Eén beeld via `importImages` = het bestaande single-pad: de studio opent
    /// met het nieuwe portret geselecteerd (geen batch-tegel).
    func testEnkelBeeldViaImportImagesOpentDeStudio() async throws {
        EntitlementStubURLProtocol.reset()
        defer { EntitlementStubURLProtocol.reset() }
        let model = ShellModel(entitlement: makeAllowedEntitlement())
        let context = try makeLibraryContext()
        model.modelContext = context
        model.debugCutoutOverride = { $0 }

        await model.importImages([.data(try png(opaqueImage(shade: 90)))])

        XCTAssertEqual(model.section, .editor, "single-pad opent de studio")
        XCTAssertNotNil(model.selectedPortrait)
        XCTAssertTrue(model.libraryImportJobs.isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Portrait2>()).count, 1)
    }

    // MARK: - E47.3: selectie (direct + async canvas-decode, E27.7)

    /// `select()` zet de selectie-state DIRECT (sidebar-highlight, naam/rol);
    /// het canvas volgt async via de off-main decode (generatie-getoetst).
    func testSelectZetSelectieDirectEnCanvasVolgtAsync() async throws {
        let (model, portrait, _) = try makeSelectedModel(cutout: cutoutImage())

        XCTAssertTrue(model.selectedPortrait === portrait, "selectie is meteen gezet")
        XCTAssertEqual(model.portraitName, "Test")
        await waitForResultCanvas(model)
        XCTAssertTrue(model.canExport, "portret op canvas → export beschikbaar")
        XCTAssertTrue(model.canPreview, "zelfde voorwaarde voor de social-preview")
    }

    // MARK: - E47.3: effect-apply / re-isolate (E09.2/E24.30)

    /// Een resultaat dat al een schone cutout is (boost/flip/enhance) wordt
    /// direct opgeslagen: edit-bron gewist (geen stale resurrection-bron), de
    /// origineel-vlag om (generatieve pixels) en het canvas ververst.
    func testApplyEffectResultMetCutoutResultaatWistEditBron() async throws {
        let (model, portrait, _) = try makeSelectedModel(cutout: cutoutImage())
        // Seed een oude (straks stale) edit-bron om het wissen te bewijzen.
        portrait.editSourceData = Data([9, 9, 9])
        portrait.editSourceCutoutSig = 12_345

        await model.applyEffectResult(cutoutImage(shade: 90))

        XCTAssertNil(portrait.editSourceData, "cutout-resultaat heeft geen re-isolate-bron nodig")
        XCTAssertEqual(portrait.editSourceCutoutSig, 0)
        XCTAssertFalse(portrait.cutoutDerivesFromOriginal,
                       "generatief resultaat verving de pixels")
        if case .result = model.canvas {} else {
            XCTFail("effect-apply hoort het canvas op .result te zetten")
        }
    }

    /// E32.3: het on-device Whiten teeth-pad levert per constructie een
    /// resultaat met identieke afmetingen en de bron-alpha (TeethWhitener
    /// verandert alleen RGB binnen het mondgebied). Deze test pint de
    /// apply-invariant waar dat pad op leunt: geen resize, geen
    /// transform-reset, geen formaatsprong.
    func testApplyEffectResultIdentiekeAfmetingenLaatTransformEnFormaatStaan() async throws {
        let (model, portrait, _) = try makeSelectedModel(cutout: cutoutImage())
        portrait.offsetX = 12
        portrait.offsetY = -8
        portrait.scale = 0.8

        await model.applyEffectResult(cutoutImage(shade: 220), preserveSourceAlpha: true)

        XCTAssertEqual(portrait.offsetX, 12, accuracy: 0.001,
                       "0% ratio-drift → geen AutoFramer-reset")
        XCTAssertEqual(portrait.offsetY, -8, accuracy: 0.001)
        XCTAssertEqual(portrait.scale, 0.8, accuracy: 0.001,
                       "gelijke resolutie → schaal ongemoeid")
        let stored = try XCTUnwrap(
            NSImage(data: portrait.cutoutData)?
                .cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        XCTAssertEqual(stored.width, 128, "afmetingen blijven exact behouden")
        XCTAssertEqual(stored.height, 128)
    }

    /// Boost / hogere-res cutout: dezelfde kadrering (offset ongewijzigd,
    /// schaal × oude/nieuwe breedte) zodat het onderwerp niet groter op het
    /// canvas landt. Geen AutoFramer-reset.
    func testApplyEffectResultHogereResolutieBehoudtKadering() async throws {
        let (model, portrait, _) = try makeSelectedModel(cutout: cutoutImage(size: 128))
        portrait.offsetX = 10
        portrait.offsetY = -20
        portrait.scale = 0.8

        await model.applyEffectResult(cutoutImage(size: 256, shade: 90))

        XCTAssertEqual(portrait.offsetX, 10, accuracy: 0.001)
        XCTAssertEqual(portrait.offsetY, -20, accuracy: 0.001)
        XCTAssertEqual(portrait.scale, 0.4, accuracy: 0.001)
        let stored = try XCTUnwrap(
            NSImage(data: portrait.cutoutData)
        )
        XCTAssertEqual(stored.pixelLayoutSize.width, 256)
        XCTAssertEqual(stored.pixelLayoutSize.height, 256)
        let canvasW = stored.pixelLayoutSize.width * portrait.scale
        XCTAssertEqual(canvasW, 128 * 0.8, accuracy: 0.001)
    }

    /// Cloud-PNG's komen vaak binnen op 72 DPI terwijl `NSImage.size` van de
    /// bron 144-DPI-punten was. Layout gebruikt pixels, niet punten.
    func testPixelLayoutSizeIgnoresPointSize() {
        let src = cutoutImage(size: 100)
        let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let retina = NSImage(cgImage: cg, size: NSSize(width: 50, height: 50))
        XCTAssertEqual(retina.size.width, 50)
        XCTAssertEqual(retina.pixelLayoutSize.width, 100)
        XCTAssertEqual(retina.pixelLayoutSize.height, 100)
        let normalized = retina.normalizedToPixelSize()
        XCTAssertEqual(normalized.size.width, 100)
        XCTAssertEqual(normalized.pixelLayoutSize.width, 100)
    }

    /// Een VOL generatief resultaat (onderwerp + achtergrond) bewaart het volle
    /// beeld als edit-bron voor een latere "Remove background", her-isoleert, en
    /// stempelt de bron met de signature van de zojuist opgeslagen cutout —
    /// vers, dus stempel == signature(cutoutData). Draait de gebruiker de cutout
    /// daarna terug (undo), dan wijkt de stempel af → bron is stale.
    func testApplyEffectResultVolResultaatStempeltEditBronEnDetecteertStaleness() async throws {
        let (model, portrait, _) = try makeSelectedModel(cutout: cutoutImage())
        let preEditCutout = portrait.cutoutData

        await model.applyEffectResult(opaqueImage())

        XCTAssertNotNil(portrait.editSourceData, "vol resultaat bewaart de re-isolate-bron")
        XCTAssertFalse(portrait.cutoutDerivesFromOriginal)
        XCTAssertEqual(
            portrait.editSourceCutoutSig, Portrait2.cutoutSignature(portrait.cutoutData),
            "verse stempel hoort exact bij de nu-opgeslagen cutout"
        )

        // Simuleer een undo die de pre-edit-cutout terugzet: de stempel hoort
        // dan niet meer bij de huidige bytes → EditorView's Remove background
        // negeert de bewaarde edit-bron (geen edit-resurrectie).
        portrait.cutoutData = preEditCutout
        XCTAssertNotEqual(
            portrait.editSourceCutoutSig, Portrait2.cutoutSignature(portrait.cutoutData),
            "teruggedraaide cutout → stempel stale"
        )
    }

    /// `applyIsolatedResult` (Remove background/Restore body) slaat een al
    /// geïsoleerd beeld direct op — zonder tweede matting-pass — en laat de
    /// bestaande edit-bron met stempel staan: die wordt door de gewijzigde
    /// cutout-bytes vanzelf stale.
    func testApplyIsolatedResultVervangtCutoutZonderTweedeMattingPass() async throws {
        let (model, portrait, _) = try makeSelectedModel(cutout: cutoutImage())
        // Edit-bron die bij de HUIDIGE cutout hoort (geldige stempel).
        portrait.editSourceData = Data([7, 7, 7])
        portrait.editSourceCutoutSig = Portrait2.cutoutSignature(portrait.cutoutData)
        let before = portrait.cutoutData

        await model.applyIsolatedResult(cutoutImage(shade: 60))

        XCTAssertNotEqual(portrait.cutoutData, before, "cutout is vervangen")
        XCTAssertNotNil(portrait.editSourceData, "applyIsolatedResult wist de bron niet zelf")
        XCTAssertNotEqual(
            portrait.editSourceCutoutSig, Portrait2.cutoutSignature(portrait.cutoutData),
            "nieuwe cutout-bytes → de oude stempel is vanzelf stale"
        )
        if case .result = model.canvas {} else {
            XCTFail("geïsoleerd resultaat hoort direct op het canvas te staan")
        }
    }

    // MARK: - E56: Fill in body mapping + atomaire framing

    func testFillBodyTransformHoudtOriginelePixelsOpDezelfdeCanvaspositie() throws {
        let mapping = BackendClient.FillBodyResult.Mapping(
            canvasWidth: 140,
            canvasHeight: 128,
            originalX: 12,
            originalY: 0,
            originalWidth: 128,
            originalHeight: 128
        )
        let before = TransformUndo.Snapshot(offsetX: 20, offsetY: -5, scale: 0.75)
        let after = ShellModel.compensatedFillBodyTransform(
            oldSize: CGSize(width: 128, height: 128),
            newSize: CGSize(width: 140, height: 128),
            mapping: mapping,
            current: before
        )

        let transform = try XCTUnwrap(after)
        let sourcePoint = CGPoint(x: 80, y: 64)
        let mappedPoint = CGPoint(x: 12 + sourcePoint.x, y: sourcePoint.y)
        XCTAssertEqual(
            sourcePoint.x * before.scale + before.offsetX,
            mappedPoint.x * transform.scale + transform.offsetX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            sourcePoint.y * before.scale + before.offsetY,
            mappedPoint.y * transform.scale + transform.offsetY,
            accuracy: 0.001
        )
    }

    func testFillBodyTransformLostOokOngeinitialiseerdeNulschaalStabielOp() throws {
        let oldSize = CGSize(width: 800, height: 1000)
        let mapping = BackendClient.FillBodyResult.Mapping(
            canvasWidth: 896,
            canvasHeight: 1000,
            originalX: 96,
            originalY: 0,
            originalWidth: 800,
            originalHeight: 1000
        )
        let current = TransformUndo.Snapshot(offsetX: 0, offsetY: 0, scale: 0)
        let resolved = AutoFramer.resolvedTransform(
            offsetX: 0, offsetY: 0, scale: 0, cutoutSize: oldSize
        )
        let after = try XCTUnwrap(ShellModel.compensatedFillBodyTransform(
            oldSize: oldSize,
            newSize: CGSize(width: 896, height: 1000),
            mapping: mapping,
            current: current
        ))
        let point = CGPoint(x: 400, y: 500)
        XCTAssertEqual(
            point.x * resolved.scale + resolved.offsetX,
            (point.x + 96) * after.scale + after.offsetX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            point.y * resolved.scale + resolved.offsetY,
            point.y * after.scale + after.offsetY,
            accuracy: 0.001
        )
    }

    func testApplyFillBodyResultPubliceertPixelsEnTransformSamen() throws {
        let (model, portrait, _) = try makeSelectedModel(cutout: cutoutImage())
        portrait.offsetX = 20
        portrait.offsetY = -5
        portrait.scale = 0.75
        let beforeData = portrait.cutoutData
        let source = try XCTUnwrap(
            NSImage(data: beforeData)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let expanded = try XCTUnwrap(
            ShellModel.resized(source, to: CGSize(width: 140, height: 128))
        )
        let mapping = BackendClient.FillBodyResult.Mapping(
            canvasWidth: 140,
            canvasHeight: 128,
            originalX: 12,
            originalY: 0,
            originalWidth: 128,
            originalHeight: 128
        )

        let states = try XCTUnwrap(model.applyFillBodyResult(
            expanded,
            mapping: mapping,
            to: portrait,
            expectedCutoutSignature: Portrait2.cutoutSignature(beforeData)
        ))

        XCTAssertNotEqual(portrait.cutoutData, beforeData)
        XCTAssertEqual(portrait.scale, 0.75, accuracy: 0.001)
        XCTAssertEqual(portrait.offsetX, 11, accuracy: 0.001)
        XCTAssertEqual(portrait.offsetY, -5, accuracy: 0.001)
        model.applyFillBodyState(states.before, to: portrait)
        XCTAssertEqual(portrait.cutoutData, beforeData)
        XCTAssertEqual(portrait.offsetX, 20, accuracy: 0.001)
        XCTAssertEqual(portrait.offsetY, -5, accuracy: 0.001)
        XCTAssertEqual(portrait.scale, 0.75, accuracy: 0.001)
    }

    func testFillBodyUndoHersteltBeeldEnKadreringAlsEenStap() throws {
        let (model, portrait, _) = try makeSelectedModel(cutout: cutoutImage())
        portrait.offsetX = 20
        portrait.offsetY = -5
        portrait.scale = 0.75
        let originalData = portrait.cutoutData
        let source = try XCTUnwrap(
            NSImage(data: originalData)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let expanded = try XCTUnwrap(
            ShellModel.resized(source, to: CGSize(width: 140, height: 128))
        )
        let mapping = BackendClient.FillBodyResult.Mapping(
            canvasWidth: 140,
            canvasHeight: 128,
            originalX: 12,
            originalY: 0,
            originalWidth: 128,
            originalHeight: 128
        )
        let states = try XCTUnwrap(model.applyFillBodyResult(
            expanded,
            mapping: mapping,
            to: portrait,
            expectedCutoutSignature: Portrait2.cutoutSignature(originalData)
        ))
        let undoManager = UndoManager()
        FillBodyUndo.register(
            undoManager,
            model: model,
            portrait: portrait,
            undoTo: states.before,
            redoTo: states.after
        )

        undoManager.undo()
        XCTAssertEqual(portrait.cutoutData, originalData)
        XCTAssertEqual(portrait.offsetX, 20, accuracy: 0.001)
        XCTAssertEqual(portrait.offsetY, -5, accuracy: 0.001)
        XCTAssertEqual(portrait.scale, 0.75, accuracy: 0.001)

        undoManager.redo()
        XCTAssertEqual(portrait.cutoutData, states.after.cutoutData)
        XCTAssertEqual(portrait.offsetX, states.after.transform.offsetX, accuracy: 0.001)
        XCTAssertEqual(portrait.scale, states.after.transform.scale, accuracy: 0.001)
    }

    func testFillBodyWeigertResultaatAlsBronIntussenGewijzigdIs() throws {
        let (model, portrait, _) = try makeSelectedModel(cutout: cutoutImage())
        let submittedSignature = Portrait2.cutoutSignature(portrait.cutoutData)
        portrait.cutoutData = try png(cutoutImage(shade: 90))
        let currentData = portrait.cutoutData
        let source = try XCTUnwrap(
            NSImage(data: currentData)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let expanded = try XCTUnwrap(
            ShellModel.resized(source, to: CGSize(width: 140, height: 128))
        )
        let mapping = BackendClient.FillBodyResult.Mapping(
            canvasWidth: 140,
            canvasHeight: 128,
            originalX: 12,
            originalY: 0,
            originalWidth: 128,
            originalHeight: 128
        )

        XCTAssertNil(model.applyFillBodyResult(
            expanded,
            mapping: mapping,
            to: portrait,
            expectedCutoutSignature: submittedSignature
        ))
        XCTAssertEqual(portrait.cutoutData, currentData)
    }

    func testFillBodyUndoNaSelectiewisselVervangtCanvasNiet() async throws {
        let (model, first, context) = try makeSelectedModel(cutout: cutoutImage(shade: 180))
        let firstData = first.cutoutData
        let source = try XCTUnwrap(
            NSImage(data: firstData)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let expanded = try XCTUnwrap(
            ShellModel.resized(source, to: CGSize(width: 140, height: 128))
        )
        let mapping = BackendClient.FillBodyResult.Mapping(
            canvasWidth: 140,
            canvasHeight: 128,
            originalX: 12,
            originalY: 0,
            originalWidth: 128,
            originalHeight: 128
        )
        let states = try XCTUnwrap(model.applyFillBodyResult(
            expanded,
            mapping: mapping,
            to: first,
            expectedCutoutSignature: Portrait2.cutoutSignature(firstData)
        ))
        let undoManager = UndoManager()
        FillBodyUndo.register(
            undoManager,
            model: model,
            portrait: first,
            undoTo: states.before,
            redoTo: states.after
        )

        let second = Portrait2(name: "Second", cutoutData: try png(cutoutImage(shade: 70)))
        context.insert(second)
        model.select(second)
        await waitForResultCanvas(model)
        guard case .result(let beforeUndoCanvas) = model.canvas else {
            return XCTFail("tweede portret hoort op canvas te staan")
        }
        let beforeUndoCanvasData = try png(beforeUndoCanvas)

        undoManager.undo()

        XCTAssertTrue(model.selectedPortrait === second)
        guard case .result(let afterUndoCanvas) = model.canvas else {
            return XCTFail("undo van niet-geselecteerd portret mag canvas niet wijzigen")
        }
        XCTAssertEqual(try png(afterUndoCanvas), beforeUndoCanvasData)
        XCTAssertEqual(first.cutoutData, states.before.cutoutData)
    }

    /// Enhance-paneel + Boost-dropdown blijven open bij tab-wissel, maar
    /// library → ander beeld start een nieuwe editorsessie.
    func testLibraryThenOtherImageClosesEnhanceMenu() throws {
        let (model, _, context) = try makeSelectedModel(cutout: cutoutImage())
        model.section = .editor
        model.presentation.editorActiveTool = .edit
        model.presentation.editorChipMenu = .boost

        model.showPortraits()
        XCTAssertEqual(model.section, .portraits)
        XCTAssertNil(model.presentation.editorActiveTool)
        XCTAssertNil(model.presentation.editorChipMenu)

        let other = Portrait2(name: "Other", cutoutData: try png(cutoutImage(shade: 70)))
        context.insert(other)
        model.presentation.editorActiveTool = .edit
        model.presentation.editorChipMenu = .boost
        model.openPortrait(other)

        XCTAssertEqual(model.section, .editor)
        XCTAssertNil(model.presentation.editorActiveTool)
        XCTAssertNil(model.presentation.editorChipMenu)
    }

    /// In de editor een ander beeld kiezen (sidebar) laat Enhance open,
    /// maar sluit de chip-dropdown die aan het vorige beeld hing.
    func testInEditorSelectKeepsEnhancePanelAndClosesChipMenu() throws {
        let (model, _, context) = try makeSelectedModel(cutout: cutoutImage())
        model.section = .editor
        model.presentation.editorActiveTool = .edit
        model.presentation.editorChipMenu = .boost

        let other = Portrait2(name: "Other", cutoutData: try png(cutoutImage(shade: 70)))
        context.insert(other)
        model.select(other)

        XCTAssertEqual(model.presentation.editorActiveTool, .edit)
        XCTAssertNil(model.presentation.editorChipMenu)
    }
}
