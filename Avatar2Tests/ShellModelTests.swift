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
        let model = ShellModel(entitlement: EntitlementModel(auth: AuthService.isolated()))
        if case .empty = model.canvas {} else {
            XCTFail("verwacht .empty als startstaat")
        }
    }

    func testOnleesbareDataGaatNaarFailed() async {
        let model = ShellModel(entitlement: EntitlementModel(auth: AuthService.isolated()))
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
        XCTAssertEqual(naam("thierry2.jpg"), "Thierry", "aangeplakte cijfers vallen af")
        XCTAssertEqual(naam("JanJansen2.png"), "Jan Jansen")
        XCTAssertEqual(naam("2024_anna01.HEIC"), "Anna")
        XCTAssertEqual(naam("jelle-looijen.74ZFkSVk_Z1GiMhz.webp"), "Jelle Looijen", "CDN-hash valt als geheel af")
        XCTAssertEqual(naam("farzam-madani.CATT_2ZK_jTHvU.webp"), "Farzam Madani", "ook cijfervrije brokjes in een hash-segment")
        XCTAssertEqual(naam("bruna-da-silva-gerage.JYt8bK72_1RDQTt.webp"), "Bruna da Silva Gerage")
        XCTAssertEqual(naam("anna.de.winter.jpg"), "Anna de Winter", "punt-segmenten zonder hash blijven")
        XCTAssertEqual(naam("Name=Ruslan.png"), "Ruslan", "Figma-export: eigenschap=waarde")
        XCTAssertEqual(naam("Type=Photo, Name=Anna de Winter.png"), "Anna de Winter")
        XCTAssertEqual(naam("State=Default, Name=Jelle Looijen.png"), "Jelle Looijen")
        XCTAssertEqual(naam("Name=Fren.png"), "Fren", "waarde van een naamveld wordt vertrouwd, ook buiten lexicon")
        XCTAssertEqual(naam("Name=Fren, Size=Large.png"), "Fren")
    }

    func testDefaultNaamIsLeegZonderPersoonsnaam() {
        XCTAssertEqual(naam("IMG_4821.HEIC"), "")
        XCTAssertEqual(naam("DSC00123.jpg"), "")
        XCTAssertEqual(naam("Screenshot 2026-09-02 at 10.12.33.png"), "")
        XCTAssertEqual(naam("headshot-final-v2.png"), "")
        XCTAssertEqual(naam("team.profile.jpeg"), "")
        XCTAssertEqual(naam("p1-man_beard.png"), "", "geen voornaam + alleen gewone woorden → geen naam")
    }

    func testDefaultNaamGebruiktVoornamenlexicon() {
        XCTAssertEqual(naam("Thierry Emmery - Square One.png"), "Thierry Emmery", "na de achternaam stopt de naam bij ruis")
        XCTAssertEqual(naam("sanne-jansen-presentation.png"), "Sanne Jansen", "gewoon woord na de achternaam valt af")
        XCTAssertEqual(naam("avond-roos-jansen.png"), "Roos Jansen", "wat vóór de voornaam staat is geen naam")
        XCTAssertEqual(naam("EMMERY_THIERRY.png"), "Emmery Thierry", "achternaam-eerst met precies twee delen blijft")
        XCTAssertEqual(naam("looijen.png"), "Looijen", "onbekend woord zonder voornaam blijft achternaam")
        XCTAssertEqual(naam("man-beard.png"), "", "alleen woordenboekwoorden zonder voornaam → geen naam")
        XCTAssertEqual(naam("Zoë_Müller.jpg"), "Zoë Müller", "accenten: lexicon-match gevouwen, weergave intact")
        XCTAssertGreaterThan(FirstNameLexicon.count, 2000)
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
        let model = ShellModel(entitlement: EntitlementModel(auth: AuthService.isolated()))
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
            auth: AuthService.isolated(), backendSession: EntitlementStubURLProtocol.makeSession()
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
            auth: AuthService.isolated(), backendSession: EntitlementStubURLProtocol.makeSession()
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
        // Permanent id vóór de import: met een temporary identifier viel de
        // map-lookup in `folderDefaultBackground` één keer om (SwiftData-fatal
        // "backing data could no longer be found", 2026-09-03) — zie ook
        // testBatchImportTegelsVolgenDeLens.
        try context.save()
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
        // Permanente identifiers: `folderDefaultBackground` lost de map op via
        // `model(for:)`, en een temporary identifier is niet altijd resolvable
        // (eenmalige SwiftData-fatal "cannot fulfill model without a store
        // identifier" in deze test, 2026-09-02).
        try context.save()
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

    // MARK: - E14.10: drop boven de Starter-cap (pre-flight, pending set, hervatten)

    /// Vorm uit backend/api/v1/account.ts (free-tier: `tier: null`).
    private func accountJSON(freeImportsRemaining: Int, tier: String = "free") -> String {
        """
        {
          "tier": \(tier == "pro" ? "\"pro\"" : "null"),
          "credits_remaining": \(tier == "pro" ? 200 : 0),
          "monthly_quota": \(tier == "pro" ? 200 : 0),
          "monthly_reset_at": null,
          "subscription_status": "\(tier == "pro" ? "active" : "none")",
          "subscription_renews_at": null,
          "free_cutouts_used": 0,
          "free_cutouts_remaining": 3,
          "free_imports_used": \(3 - freeImportsRemaining),
          "free_imports_remaining": \(freeImportsRemaining),
          "needs_account_link": false
        }
        """
    }

    private func stubAccount(freeImportsRemaining: Int, tier: String = "free") {
        EntitlementStubURLProtocol.setStub(
            .json(200, accountJSON(freeImportsRemaining: freeImportsRemaining, tier: tier)),
            forPath: "/v1/account"
        )
    }

    private func stubClaim(allowed: Bool) {
        EntitlementStubURLProtocol.setStub(
            allowed
                ? .json(200, """
                    { "allowed": true, "imports_used": 1, "imports_remaining": 2 }
                    """)
                : .json(402, """
                    { "allowed": false, "imports_used": 3, "imports_remaining": 0 }
                    """),
            forPath: "/v1/import-claim"
        )
    }

    private func makeStubbedEntitlement() -> EntitlementModel {
        EntitlementModel(auth: AuthService.isolated(), backendSession: EntitlementStubURLProtocol.makeSession())
    }

    private func threeSources() throws -> [ShellModel.ImportSource] {
        [
            .data(try png(opaqueImage(shade: 90))),
            .data(try png(opaqueImage(shade: 120))),
            .data(try png(opaqueImage(shade: 200))),
        ]
    }

    private func waitForStoredCount(_ expected: Int, in context: ModelContext, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try context.fetch(FetchDescriptor<Portrait2>()).count >= expected { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Cap al vol vóór de drop: er komt géén tegel (voorheen flitsten alle
    /// tegels en veegde de eerste 402 ze stil weg), de paywall opent mét de
    /// reden, en de hele set wacht op een upgrade. Niets gepersisteerd.
    func testBatchImportBovenDeCapZetGeenTegelNeerEnWacht() async throws {
        EntitlementStubURLProtocol.reset()
        defer { EntitlementStubURLProtocol.reset() }
        stubAccount(freeImportsRemaining: 0)
        stubClaim(allowed: false)
        let entitlement = makeStubbedEntitlement()
        let model = ShellModel(entitlement: entitlement)
        let context = try makeLibraryContext()
        model.modelContext = context
        model.debugCutoutOverride = { _ in XCTFail("geen cutout als er niets past"); throw CancellationError() }

        await model.importImages(try threeSources())

        XCTAssertTrue(entitlement.isPaywallPresented, "cap → paywall")
        XCTAssertEqual(entitlement.upgradeReason, .importCapReached(dropped: 3, capacity: FreeTier.maxPortraits))
        XCTAssertEqual(entitlement.upgradeReasonCopy,
                       "You dropped 3 images, but your 3 free images are used up. Upgrade to Pro to import them.")
        XCTAssertTrue(model.libraryImportJobs.isEmpty, "geen tegel vóór de gate")
        XCTAssertNil(model.libraryImportProgress)
        XCTAssertEqual(model.pendingGatedImport?.sources.count, 3, "de hele drop wacht op een upgrade")
        XCTAssertEqual(model.pendingGatedImport?.awaitsPaywall, true)
        XCTAssertNil(entitlement.infoToast, "niets geland → paywall, geen deel-toast")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Portrait2>()).count, 0)
    }

    /// Eén plek over, drie gedropt: het eerste beeld landt, de andere twee
    /// wachten, en de batch eindigt met een toast mét Upgrade-knop — géén
    /// gedwongen paywall (besluit Thierry 2026-09-02). De knop opent de
    /// paywall met de reden en sluit de toast.
    func testBatchImportDeelsPassendLandtDeelEnToontToastMetUpgrade() async throws {
        EntitlementStubURLProtocol.reset()
        defer { EntitlementStubURLProtocol.reset() }
        stubAccount(freeImportsRemaining: 1)
        stubClaim(allowed: true)
        let entitlement = makeStubbedEntitlement()
        let model = ShellModel(entitlement: entitlement)
        let context = try makeLibraryContext()
        model.modelContext = context
        model.debugCutoutOverride = { $0 }

        await model.importImages(try threeSources())

        XCTAssertEqual(try context.fetch(FetchDescriptor<Portrait2>()).count, 1, "alleen wat past landt")
        XCTAssertFalse(entitlement.isPaywallPresented, "deels geland → geen gedwongen paywall")
        XCTAssertEqual(entitlement.infoToast?.title, "1 of 3 images imported")
        XCTAssertEqual(entitlement.infoToast?.description,
                       "Starter includes 3 images. Upgrade to Pro to add the other 2.")
        XCTAssertEqual(entitlement.infoToast?.action?.label, "Upgrade to Pro")
        XCTAssertEqual(model.pendingGatedImport?.sources.count, 2)
        XCTAssertEqual(model.pendingGatedImport?.awaitsPaywall, false)
        XCTAssertTrue(model.libraryImportJobs.isEmpty)

        // Zonder geopende paywall vervalt er niets stilletjes.
        model.discardPendingGatedImport()
        XCTAssertEqual(model.pendingGatedImport?.sources.count, 2, "set blijft staan zolang de paywall niet is afgewezen")

        entitlement.infoToast?.action?.handler()
        XCTAssertNil(entitlement.infoToast, "de actie sluit de toast")
        XCTAssertTrue(entitlement.isPaywallPresented)
        XCTAssertEqual(entitlement.upgradeReason, .importCapReached(dropped: 3, capacity: FreeTier.maxPortraits))
        XCTAssertEqual(model.pendingGatedImport?.awaitsPaywall, true)
    }

    /// Stale teller: het account zegt "2 over", de server weigert toch (ander
    /// apparaat / uitgelogd device-teller). Er is dan wél even een tegel, maar
    /// niets landt → paywall met reden, alle drie de beelden wachten, geen
    /// stille wipe.
    func testBatchImportStaleTellerWeigertAllesEnWacht() async throws {
        EntitlementStubURLProtocol.reset()
        defer { EntitlementStubURLProtocol.reset() }
        stubAccount(freeImportsRemaining: 2)
        stubClaim(allowed: false)
        let entitlement = makeStubbedEntitlement()
        let model = ShellModel(entitlement: entitlement)
        let context = try makeLibraryContext()
        model.modelContext = context
        model.debugCutoutOverride = { _ in XCTFail("geen cutout na een geweigerde claim"); throw CancellationError() }

        await model.importImages(try threeSources())

        XCTAssertTrue(entitlement.isPaywallPresented)
        XCTAssertEqual(entitlement.upgradeReason, .importCapReached(dropped: 3, capacity: FreeTier.maxPortraits))
        XCTAssertNil(entitlement.infoToast)
        XCTAssertTrue(model.libraryImportJobs.isEmpty)
        XCTAssertNil(model.libraryImportProgress)
        XCTAssertEqual(model.pendingGatedImport?.sources.count, 3, "2 uit de wachtrij + 1 overschot")
        XCTAssertEqual(model.pendingGatedImport?.awaitsPaywall, true)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Portrait2>()).count, 0)
    }

    /// Het account wordt Pro terwijl de set wacht → de import gaat alsnog door,
    /// in de map van de oorspronkelijke drop.
    func testPendingGatedImportHervatNaUpgradeInDeOorspronkelijkeMap() async throws {
        EntitlementStubURLProtocol.reset()
        defer { EntitlementStubURLProtocol.reset() }
        stubAccount(freeImportsRemaining: 0)
        stubClaim(allowed: false)
        let entitlement = makeStubbedEntitlement()
        let model = ShellModel(entitlement: entitlement)
        let context = try makeLibraryContext()
        model.modelContext = context
        let folder = Folder2(name: "Team")
        context.insert(folder)
        try context.save()
        model.showPortraits(folderID: folder.persistentModelID)
        model.debugCutoutOverride = { $0 }

        await model.importImages(try threeSources())
        XCTAssertEqual(model.pendingGatedImport?.sources.count, 3)

        // Upgrade: account Pro, claim short-circuit. De gebruiker staat
        // inmiddels op Home — de set moet tóch in "Team" landen.
        stubAccount(freeImportsRemaining: 0, tier: "pro")
        stubClaim(allowed: true)
        await entitlement.refresh()
        XCTAssertTrue(entitlement.isProActive)
        model.showHome()
        model.resumePendingGatedImport()

        try await waitForStoredCount(3, in: context)
        let stored = try context.fetch(FetchDescriptor<Portrait2>())
        XCTAssertEqual(stored.count, 3, "de wachtende set landt volledig")
        XCTAssertTrue(stored.allSatisfy { $0.folder?.persistentModelID == folder.persistentModelID },
                      "in de map van de oorspronkelijke drop")
        XCTAssertNil(model.pendingGatedImport)
    }

    /// Paywall gesloten zonder upgrade → de set vervalt met een toast die dat
    /// zegt (voorheen: beelden weg zonder één woord).
    func testPendingGatedImportVervaltMetToastNaAfgewezenPaywall() async throws {
        EntitlementStubURLProtocol.reset()
        defer { EntitlementStubURLProtocol.reset() }
        stubAccount(freeImportsRemaining: 0)
        stubClaim(allowed: false)
        let entitlement = makeStubbedEntitlement()
        let model = ShellModel(entitlement: entitlement)
        model.modelContext = try makeLibraryContext()

        await model.importImages(try threeSources())
        XCTAssertEqual(model.pendingGatedImport?.awaitsPaywall, true)

        entitlement.isPaywallPresented = false
        model.discardPendingGatedImport()

        XCTAssertNil(model.pendingGatedImport)
        XCTAssertEqual(entitlement.infoToast?.title, "3 images weren't imported")
        XCTAssertEqual(entitlement.infoToast?.description, "Upgrade to Pro any time to import them.")
        XCTAssertNil(entitlement.upgradeReason, "reden hoort bij één presentatie")
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

    /// Eén foto in een map droppen opent de studio; wie tijdens de cutout
    /// teruggaat naar de map moet het beeld daar al zien staan (tijdelijke
    /// tegel in de map-lens, ook zichtbaar op Home) — niet een lege map met
    /// alleen de "Removing background…"-pill (Thierry, 2026-09-03). Na afloop
    /// is de tegel weg, staat het portret in de map en heeft het z'n
    /// tegel-compositie als placeholder.
    func testEnkelBeeldToontTegelInDeMapTijdensDeCutout() async throws {
        EntitlementStubURLProtocol.reset()
        defer { EntitlementStubURLProtocol.reset() }
        let model = ShellModel(entitlement: makeAllowedEntitlement())
        let context = try makeLibraryContext()
        model.modelContext = context
        let folder = Folder2(name: "Acme")
        let other = Folder2(name: "Other")
        context.insert(folder)
        context.insert(other)
        try context.save()
        model.showPortraits(folderID: folder.persistentModelID)
        var observedJobs: [ShellModel.LibraryImportJob] = []
        var studioOpenDuringCutout = false
        model.debugCutoutOverride = { image in
            observedJobs = await model.libraryImportJobs
            studioOpenDuringCutout = await model.section == .editor
            return image
        }

        await model.importImage(data: try png(opaqueImage(shade: 90)))

        XCTAssertTrue(studioOpenDuringCutout, "de studio staat open tijdens de cutout")
        XCTAssertEqual(observedJobs.count, 1, "de map heeft tijdens de cutout al een tegel")
        XCTAssertEqual(observedJobs.first?.folderID, folder.persistentModelID)
        if case .isolating = observedJobs.first?.phase {} else { XCTFail("tegel toont 'Removing background…'") }
        model.libraryImportJobsForTesting = observedJobs
        XCTAssertEqual(model.visibleLibraryImportJobs(folderID: folder.persistentModelID).count, 1)
        XCTAssertEqual(model.visibleLibraryImportJobs(folderID: nil).count, 1, "Home / All portraits")
        XCTAssertEqual(model.visibleLibraryImportJobs(folderID: other.persistentModelID).count, 0)
        model.libraryImportJobsForTesting = []

        let stored = try context.fetch(FetchDescriptor<Portrait2>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.folder?.persistentModelID, folder.persistentModelID, "landt in de map")
        XCTAssertTrue(model.libraryImportJobs.isEmpty, "tegel is vervangen door het portret")
        XCTAssertNil(model.libraryImportProgress, "single-import telt niet als batch")
        XCTAssertNotNil(stored.first.flatMap { model.freshImportPreview(for: $0) },
                        "verse tegel krijgt de compositie als placeholder")
        XCTAssertNotNil(model.selectedPortrait)
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

// MARK: - Crash-flow 2026-09-03: effect bezig → bibliotheek → drop in een
// verse map → nóg een drop tijdens het vrijstaand maken → crash.

extension ShellModelTests {
    /// Teller voor de cutout-haak: hoeveel cutouts er tegelijk lopen.
    @MainActor private final class CutoutGauge {
        var inFlight = 0
        var peak = 0
    }

    /// Een tweede losse drop tijdens een lopende cutout wacht op de eerste:
    /// nooit twee single-imports door elkaar (canvas, selectie, persist).
    func testTweedeDropTijdensCutoutWachtOpDeEerste() async throws {
        EntitlementStubURLProtocol.reset()
        defer { EntitlementStubURLProtocol.reset() }
        let model = ShellModel(entitlement: makeAllowedEntitlement())
        let context = try makeContext()
        model.modelContext = context
        let gauge = CutoutGauge()
        model.debugCutoutOverride = { image in
            gauge.inFlight += 1
            gauge.peak = max(gauge.peak, gauge.inFlight)
            try? await Task.sleep(for: .milliseconds(200))
            gauge.inFlight -= 1
            return image
        }
        let png1 = try png(opaqueImage(shade: 90))
        let png2 = try png(opaqueImage(shade: 160))
        async let first: () = model.importImage(data: png1)
        try await Task.sleep(for: .milliseconds(50))
        async let second: () = model.importImage(data: png2)
        _ = await (first, second)

        XCTAssertEqual(gauge.peak, 1, "single-imports lopen sequentieel")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Portrait2>()).count, 2, "beide drops zijn geland")
        XCTAssertNotNil(model.selectedPortrait, "de laatste import is de selectie")
        if case .result = model.canvas {} else { XCTFail("canvas eindigt op het resultaat van de laatste import") }
    }

    /// De map komt uit de naam-prompt (`insert` + `save` → permanent id in de
    /// lens). Het effect is gestart voor het geopende portret; het resultaat
    /// komt binnen terwijl er (na navigatie) al twee drops in de map lopen en
    /// hoort op dát portret te landen — niet op de verse import, niet op het
    /// canvas van de import.
    func testEffectLandtOpHetOorspronkelijkePortretNaNavigatieEnDrops() async throws {
        EntitlementStubURLProtocol.reset()
        defer { EntitlementStubURLProtocol.reset() }
        let model = ShellModel(entitlement: makeAllowedEntitlement())
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Portrait2.self, Folder2.self, configurations: config)
        let context = container.mainContext // autosave aan, zoals de app
        model.modelContext = context

        let existingPNG = try png(opaqueImage(shade: 40))
        let existing = Portrait2(name: "Thierry", cutoutData: existingPNG)
        context.insert(existing)
        try context.save()
        model.openPortrait(existing)
        // Zoals ShellView: het doel reist mee in de closure bij het openen.
        let target = model.selectedPortrait
        XCTAssertTrue(target === existing)

        let folder = Folder2(name: "Acme")
        context.insert(folder)
        try context.save()
        model.showPortraits(folderID: folder.persistentModelID)

        model.debugCutoutOverride = { image in
            try? await Task.sleep(for: .milliseconds(200))
            return image
        }
        let styled = opaqueImage(shade: 220)
        let png1 = try png(opaqueImage(shade: 90))
        let png2 = try png(opaqueImage(shade: 160))
        async let first: () = model.importImage(data: png1)
        try await Task.sleep(for: .milliseconds(60))
        async let second: () = model.importImage(data: png2)
        try await Task.sleep(for: .milliseconds(60))
        // Effect landt terwijl de cutouts lopen (selectie = nil) …
        await model.applyEffectResult(styled, to: target, framing: .keep)
        _ = await (first, second)
        // … en nog eens nadat de imports gepersisteerd zijn (selectie = verse import).
        await model.applyEffectResult(styled, to: target, framing: .keep)

        let stored = try context.fetch(FetchDescriptor<Portrait2>())
        XCTAssertEqual(stored.count, 3, "bestaand portret + twee imports")
        XCTAssertNotEqual(existing.cutoutData, existingPNG, "het effect is op het oorspronkelijke portret toegepast")
        XCTAssertNotNil(existing.editSourceData, "vol AI-resultaat bewaard voor Remove background")
        let imported = stored.filter { $0.persistentModelID != existing.persistentModelID }
        XCTAssertEqual(imported.count, 2)
        XCTAssertTrue(imported.allSatisfy { $0.editSourceData == nil && $0.cutoutDerivesFromOriginal },
                      "de verse imports zijn onaangeraakt door het effect")
        XCTAssertTrue(imported.allSatisfy { $0.folder?.persistentModelID == folder.persistentModelID },
                      "beide drops landen in de verse map")
        XCTAssertTrue(model.selectedPortrait !== existing, "de studio toont de laatste import")
    }
}
