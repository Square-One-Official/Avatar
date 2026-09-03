import AppKit
import XCTest
@testable import Avatar2

final class StylizeQualityTests: XCTestCase {

    private func solidImage(w: Int, h: Int) -> NSImage {
        let bpr = w * 4
        var buf = [UInt8](repeating: 255, count: bpr * h)
        let ctx = CGContext(
            data: &buf, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let cg = ctx.makeImage()!
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }

    // Sticker-fix: kadrering per effect-wissel.
    func testEffectFramingForSwitch() {
        XCTAssertEqual(EffectFraming.forSwitch(toDieCut: true, fromDieCut: false), .fitContent)
        XCTAssertEqual(EffectFraming.forSwitch(toDieCut: true, fromDieCut: true), .fitContent)
        XCTAssertEqual(EffectFraming.forSwitch(toDieCut: false, fromDieCut: true), .autoFrame)
        XCTAssertEqual(EffectFraming.forSwitch(toDieCut: false, fromDieCut: false), .keep)
    }

    func testEffectFramingInverseUndoesTheSwitch() {
        XCTAssertEqual(EffectFraming.fitContent.inverse, .autoFrame)
        XCTAssertEqual(EffectFraming.autoFrame.inverse, .fitContent)
        XCTAssertEqual(EffectFraming.keep.inverse, .keep)
    }

    func testLowResolutionLongEdgeBelow1024() {
        XCTAssertTrue(StylizeQuality.isLowResolution(solidImage(w: 800, h: 600)))
    }

    func testSharp2048NotLowResolution() {
        XCTAssertFalse(StylizeQuality.isLowResolution(solidImage(w: 1536, h: 2048)))
    }

    func testSoftSourcePromptRequestedForLowResSource() {
        XCTAssertTrue(StylizeQuality.requestsSoftSourcePrompt(for: solidImage(w: 800, h: 600)))
    }

    func testSoftSourcePromptNotRequestedForSharpSource() {
        XCTAssertFalse(StylizeQuality.requestsSoftSourcePrompt(for: solidImage(w: 1536, h: 2048)))
    }

    func testDefaultEffectsSourceCutoutWithoutOriginalBackground() {
        let portrait = Portrait2(cutoutData: Data([1]))
        portrait.useOriginalBackground = false
        XCTAssertEqual(StylizeQuality.defaultEffectsSourceChoice(portrait: portrait), .cutout)
    }

    func testDefaultEffectsSourceOriginalWhenOriginalBackground() {
        let portrait = Portrait2(cutoutData: Data([1]))
        portrait.useOriginalBackground = true
        XCTAssertEqual(StylizeQuality.defaultEffectsSourceChoice(portrait: portrait), .original)
    }

    // MARK: - Al geboost → Effects vraagt niet nóg eens (repro: Boost → effect)

    private func portrait(originalW: Int, originalH: Int) -> Portrait2 {
        let p = Portrait2(cutoutData: Data([1]))
        p.originalData = solidImage(w: originalW, h: originalH).pngData()
        return p
    }

    func testBoostedCutoutOutranksLowResOriginal() {
        let p = portrait(originalW: 700, originalH: 900)
        XCTAssertTrue(StylizeQuality.cutoutOutranksLowResOriginal(
            portrait: p, cutout: solidImage(w: 2800, h: 3600)
        ))
    }

    func testUnboostedLowResCutoutDoesNotOutrankOriginal() {
        let p = portrait(originalW: 700, originalH: 900)
        XCTAssertFalse(StylizeQuality.cutoutOutranksLowResOriginal(
            portrait: p, cutout: solidImage(w: 700, h: 900)
        ))
    }

    func testSharpOriginalNeverCountsAsBoosted() {
        // Origineel is al scherp: geen low-res-vraag, dus ook geen boost-bypass.
        let p = portrait(originalW: 1600, originalH: 2000)
        XCTAssertFalse(StylizeQuality.cutoutOutranksLowResOriginal(
            portrait: p, cutout: solidImage(w: 3200, h: 4000)
        ))
    }

    func testWithoutOriginalNothingOutranks() {
        XCTAssertFalse(StylizeQuality.cutoutOutranksLowResOriginal(
            portrait: Portrait2(cutoutData: Data([1])), cutout: solidImage(w: 2800, h: 3600)
        ))
    }

    @MainActor
    func testEffectsGateSkipsSheetAfterBoostAndUsesCutout() async {
        let coordinator = StylizeQualityCoordinator()
        let p = portrait(originalW: 700, originalH: 900)
        let boosted = solidImage(w: 2800, h: 3600)
        let result = await coordinator.gateBeforeStylize(
            source: boosted, portrait: p, cutout: boosted, isEffects: true
        )
        XCTAssertEqual(result.decision, .proceed)
        XCTAssertEqual(result.effectsSource, .cutout)
        XCTAssertNil(coordinator.preGate, "na een Boost mag er geen kwaliteitssheet meer komen")
    }

    @MainActor
    func testEffectsGateStillAsksWhenNotBoosted() async {
        let coordinator = StylizeQualityCoordinator()
        let p = portrait(originalW: 700, originalH: 900)
        let small = solidImage(w: 700, h: 900)
        async let result = coordinator.gateBeforeStylize(
            source: small, portrait: p, cutout: small, isEffects: true
        )
        // De sheet staat open tot de gebruiker beslist.
        while coordinator.preGate == nil { await Task.yield() }
        XCTAssertEqual(coordinator.preGate?.kind, .lowResolution)
        coordinator.resolvePreGate(.proceed)
        let r = await result
        XCTAssertEqual(r.decision, .proceed)
        XCTAssertEqual(r.effectsSource, .original)
    }

    // MARK: - Boost vanuit de sheet → Effects gebruikt het verse cutout

    func testFreshlyBoostedCutoutReturnedWhenBoostLanded() {
        let p = portrait(originalW: 700, originalH: 900)
        p.cutoutData = solidImage(w: 2800, h: 3600).pngData()!
        XCTAssertNotNil(StylizeQuality.freshlyBoostedCutout(portrait: p))
    }

    func testFreshlyBoostedCutoutNilWhenBoostDidNotLand() {
        let p = portrait(originalW: 700, originalH: 900)
        p.cutoutData = solidImage(w: 700, h: 900).pngData()!
        XCTAssertNil(StylizeQuality.freshlyBoostedCutout(portrait: p))
    }

    func testFreshlyBoostedCutoutNilWithActiveEffect() {
        // Met een actief effect boostte Boost het gestylede beeld; de basis bleef klein.
        let p = portrait(originalW: 700, originalH: 900)
        p.cutoutData = solidImage(w: 2800, h: 3600).pngData()!
        p.effectActiveRaw = "windy"
        XCTAssertNil(StylizeQuality.freshlyBoostedCutout(portrait: p))
    }

    func testEffectsStylizeSourceUsesFreshCutout() {
        let fresh = solidImage(w: 1600, h: 2000)
        let source = StylizeQuality.effectsStylizeSource(
            portrait: portrait(originalW: 700, originalH: 900),
            cutout: solidImage(w: 700, h: 900),
            choice: .freshCutout(fresh)
        )
        XCTAssertTrue(source === fresh)
    }

    @MainActor
    func testEffectsGateBoostFirstProceedsWithFreshCutout() async {
        let coordinator = StylizeQualityCoordinator()
        let p = portrait(originalW: 700, originalH: 900)
        let small = solidImage(w: 700, h: 900)
        p.cutoutData = small.pngData()!
        let boosted = solidImage(w: 2800, h: 3600).pngData()!
        coordinator.onBoostCutout = { p.cutoutData = boosted }

        async let result = coordinator.gateBeforeStylize(
            source: small, portrait: p, cutout: small, isEffects: true
        )
        while coordinator.preGate == nil { await Task.yield() }
        coordinator.resolvePreGate(.boostFirst)
        let r = await result
        XCTAssertEqual(r.decision, .proceed)
        guard case .freshCutout(let fresh) = r.effectsSource else {
            return XCTFail("verwacht het verse cutout als bron, kreeg \(r.effectsSource)")
        }
        XCTAssertEqual(StylizeQuality.pixelSize(of: fresh)?.longEdge, 3600)
    }

    @MainActor
    func testEffectsGateBoostFirstFallsBackToOriginalWhenBoostFailed() async {
        let coordinator = StylizeQualityCoordinator()
        let p = portrait(originalW: 700, originalH: 900)
        let small = solidImage(w: 700, h: 900)
        p.cutoutData = small.pngData()!
        coordinator.onBoostCutout = { /* credits op: cutout blijft klein */ }

        async let result = coordinator.gateBeforeStylize(
            source: small, portrait: p, cutout: small, isEffects: true
        )
        while coordinator.preGate == nil { await Task.yield() }
        coordinator.resolvePreGate(.boostFirst)
        let r = await result
        XCTAssertEqual(r.effectsSource, .original)
    }

    func testBlurDetectionDisabledByDefault() {
        XCTAssertFalse(StylizeQuality.blurDetectionEnabled)
    }

    func testCutoutDimensions() {
        let (w, h) = StylizeQuality.cutoutDimensions(for: solidImage(w: 640, h: 480))
        XCTAssertEqual(w, 640)
        XCTAssertEqual(h, 480)
    }

    // MARK: - Reframe-guard na effect (E55-delivery-fix)

    func testReframeWhenNewTopOverflowsAndOldFit() {
        // Oud onderwerp: top op pixel 40, schaal 0.5, offset 0 → canvas-top 20 (past).
        // Nieuw onderwerp (windy-haar): top op pixel 5, offset -30 → canvas-top -27.5.
        XCTAssertTrue(ShellModel.effectNeedsReframe(
            oldTopPx: 40, oldScale: 0.5, oldOffsetY: 0,
            newTopPx: 5, newScale: 0.5, newOffsetY: -30
        ))
    }

    func testNoReframeWhenBothFit() {
        XCTAssertFalse(ShellModel.effectNeedsReframe(
            oldTopPx: 40, oldScale: 0.5, oldOffsetY: 0,
            newTopPx: 10, newScale: 0.5, newOffsetY: 0
        ))
    }

    func testNoReframeWhenUserCroppedDeliberately() {
        // Oude top stak al boven het canvas uit (bewuste krappe kadrering) —
        // ook al steekt de nieuwe verder uit: van de gebruiker afblijven.
        XCTAssertFalse(ShellModel.effectNeedsReframe(
            oldTopPx: 0, oldScale: 1.0, oldOffsetY: -50,
            newTopPx: 0, newScale: 1.0, newOffsetY: -120
        ))
    }

    func testAlphaTopFindsFirstOpaqueRow() {
        // 10×10 transparant met een opake band vanaf y=6.
        let size = 10, bpr = size * 4
        var buf = [UInt8](repeating: 0, count: bpr * size)
        for y in 6..<size { for x in 0..<size {
            let i = (y * size + x) * 4
            buf[i] = 255; buf[i + 3] = 255
        } }
        let ctx = CGContext(
            data: &buf, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        XCTAssertEqual(ShellModel.alphaTop(of: ctx.makeImage()!), 6)
    }

    // MARK: - Upload-cap (E55.2)

    func testCappedForUploadShrinksLargeImage() {
        let capped = StylizeQuality.cappedForUpload(solidImage(w: 4096, h: 2048))
        let cg = capped.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        XCTAssertEqual(cg.width, 2048)
        XCTAssertEqual(cg.height, 1024)
        // Alpha-kanaal moet de resize overleven (cutout-bronnen zijn RGBA).
        XCTAssertNotEqual(cg.alphaInfo, .none)
    }

    func testCappedForUploadKeepsSmallImageIdentity() {
        let source = solidImage(w: 640, h: 480)
        XCTAssertTrue(StylizeQuality.cappedForUpload(source) === source, "onder de cap hoort exact dezelfde instance terug")
    }

    func testEffectsStylizeSourceAppliesCap() {
        let big = solidImage(w: 3000, h: 4500)
        let source = StylizeQuality.effectsStylizeSource(portrait: nil, cutout: big, choice: .cutout)
        let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        XCTAssertEqual(max(cg.width, cg.height), StylizeQuality.uploadMaxLongEdge)
        // Ratio blijft behouden (3000:4500 = 2:3 → 1365×2048, ±1px afronding).
        let ratio = Double(cg.width) / Double(cg.height)
        XCTAssertEqual(ratio, 2.0 / 3.0, accuracy: 0.002)
    }
}
