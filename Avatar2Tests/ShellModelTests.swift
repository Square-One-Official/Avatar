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

    func testDefaultNaamHumaniseertKoppeltekensEnUnderscores() {
        let url = URL(fileURLWithPath: "/tmp/p1-man_beard.png")
        XCTAssertEqual(ShellModel.defaultPortraitName(from: url), "p1 man beard")
    }

    func testDefaultNaamStriptAlleenDeLaatsteExtensie() {
        let url = URL(fileURLWithPath: "/Users/x/Photos/team.profile.jpeg")
        XCTAssertEqual(ShellModel.defaultPortraitName(from: url), "team.profile")
    }

    func testDefaultNaamVouwtDubbeleSeparatorsSamen() {
        let url = URL(fileURLWithPath: "/tmp/anna--de_-winter.HEIC")
        XCTAssertEqual(ShellModel.defaultPortraitName(from: url), "anna de winter")
    }

    func testDefaultNaamBlijftIntactZonderSeparators() {
        let url = URL(fileURLWithPath: "/tmp/Portrait.png")
        XCTAssertEqual(ShellModel.defaultPortraitName(from: url), "Portrait")
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
}
