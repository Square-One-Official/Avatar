import CoreGraphics
import XCTest
@testable import AvatarKit

/// Belichting herkennen + kleurcorrectie (geen huidtint-transfer).
final class SetLightingNormalizerTests: XCTestCase {
    private func solid(_ value: CGFloat, size: Int = 8) -> CGImage {
        rgb(value, value, value, size: size)
    }

    private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, size: Int = 16) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }

    private func image(
        size: Int, fill: (CGFloat, CGFloat, CGFloat),
        region: CGRect, regionRGB: (CGFloat, CGFloat, CGFloat)
    ) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: fill.0, green: fill.1, blue: fill.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setFillColor(red: regionRGB.0, green: regionRGB.1, blue: regionRGB.2, alpha: 1)
        ctx.fill(region)
        return ctx.makeImage()!
    }

    func testDarkImageMovesTowardBrightReference() throws {
        let dark = solid(0.2)
        let bright = solid(0.8)
        let ref = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: bright))
        let darkStats = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: dark))

        let matched = try XCTUnwrap(SetLightingNormalizer.match(dark, to: ref))
        let matchedStats = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: matched))

        XCTAssertGreaterThan(matchedStats.luma, darkStats.luma)
        XCTAssertLessThan(matchedStats.luma, ref.luma + 0.05)
    }

    func testDimensionsPreserved() throws {
        let img = solid(0.5, size: 12)
        let ref = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: solid(0.6)))
        let out = try XCTUnwrap(SetLightingNormalizer.match(img, to: ref))
        XCTAssertEqual(out.width, 12)
        XCTAssertEqual(out.height, 12)
    }

    func testFaceRegionLumaMovesTowardReference() throws {
        let face = CGRect(x: 4, y: 16, width: 12, height: 12)
        let darkFace = image(size: 32, fill: (0.75, 0.75, 0.75), region: face, regionRGB: (0.2, 0.2, 0.2))
        let brightFace = image(size: 32, fill: (0.25, 0.25, 0.25), region: face, regionRGB: (0.85, 0.85, 0.85))
        let ref = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: brightFace, in: face))
        let before = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: darkFace, in: face))

        let matched = try XCTUnwrap(
            SetLightingNormalizer.match(darkFace, to: ref, sourceRegion: face)
        )
        let after = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: matched, in: face))

        XCTAssertGreaterThan(after.luma, before.luma)
    }

    func testDoesNotCopySkinHueOntoDifferentComplexion() throws {
        let face = CGRect(x: 4, y: 16, width: 16, height: 16)
        let brown = image(
            size: 32, fill: (0.2, 0.2, 0.2), region: face,
            regionRGB: (0.42, 0.28, 0.18)
        )
        let pink = image(
            size: 32, fill: (0.2, 0.2, 0.2), region: face,
            regionRGB: (0.86, 0.68, 0.62)
        )
        let ref = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: pink, in: face))
        let matched = try XCTUnwrap(
            SetLightingNormalizer.match(brown, to: ref, sourceRegion: face)
        )
        let beforeHue = sampleOpaqueMean(brown, in: face)
        let afterHue = sampleOpaqueMean(matched, in: face)

        let beforeRG = beforeHue.r / max(beforeHue.g, 0.04)
        let afterRG = afterHue.r / max(afterHue.g, 0.04)
        XCTAssertEqual(afterRG, beforeRG, accuracy: 0.25, "huidtint mag niet naar de referentie-huid schuiven")
        XCTAssertLessThan(afterHue.r, 0.75, "geen zware rood-cast")
    }

    func testAlphaPreservedOnTransparentPixel() throws {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.clear(CGRect(x: 0, y: 0, width: 4, height: 4))
        ctx.setFillColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 4))
        let cutout = ctx.makeImage()!

        let ref = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: solid(0.7)))
        let out = try XCTUnwrap(SetLightingNormalizer.match(cutout, to: ref))
        XCTAssertEqual(out.width, 4)
        XCTAssertEqual(out.height, 4)
    }

    private func sampleOpaqueMean(_ image: CGImage, in region: CGRect) -> (r: Double, g: Double, b: Double) {
        let w = image.width
        let h = image.height
        let bpr = w * 4
        var pixels = [UInt8](repeating: 0, count: h * bpr)
        let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bpr, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        let minX = max(0, Int(region.minX))
        let maxX = min(w, Int(region.maxX))
        let minY = max(0, Int(region.minY))
        let maxY = min(h, Int(region.maxY))
        for y in minY..<maxY {
            for x in minX..<maxX {
                let i = y * bpr + x * 4
                guard pixels[i + 3] > 80 else { continue }
                r += Double(pixels[i]) / 255
                g += Double(pixels[i + 1]) / 255
                b += Double(pixels[i + 2]) / 255
                n += 1
            }
        }
        n = max(n, 1)
        return (r / n, g / n, b / n)
    }
}

// MARK: - E50.3: Adjust-suggestie + doelkeuze

extension SetLightingNormalizerTests {
    private func stats(
        exposure: Double = 0.65, kelvin: Double = 5800, tint: Double = 0, contrast: Double = 0.35
    ) -> SetLightingNormalizer.Stats {
        SetLightingNormalizer.Stats(exposure: exposure, kelvin: kelvin, tint: tint, contrast: contrast)
    }

    func testSuggestionIsNeutralForIdenticalStats() {
        let s = stats()
        XCTAssertEqual(SetLightingNormalizer.adjustSuggestion(from: s, to: s), .neutral)
    }

    func testSuggestionIsNeutralWithinTolerance() {
        let a = stats()
        let b = stats(exposure: 0.67, kelvin: 5900, contrast: 0.37)
        XCTAssertTrue(SetLightingNormalizer.isWithinTolerance(a, b))
        XCTAssertEqual(SetLightingNormalizer.adjustSuggestion(from: a, to: b), .neutral)
    }

    func testDarkSourceGetsPositiveBrightnessClamped() {
        let s = SetLightingNormalizer.adjustSuggestion(from: stats(exposure: 0.2), to: stats(exposure: 0.8))
        XCTAssertEqual(s.brightness, SetLightingNormalizer.brightnessRange.upperBound, accuracy: 1e-9)
        XCTAssertEqual(s.contrast, 1, "belichting loopt tegen de klem → geen contrast erbovenop")
        XCTAssertEqual(s.temperature, 0)
        let mild = SetLightingNormalizer.adjustSuggestion(from: stats(exposure: 0.5), to: stats(exposure: 0.6))
        XCTAssertGreaterThan(mild.brightness, 0)
        XCTAssertLessThan(mild.brightness, 0.35)
    }

    func testBrightSourceGetsNegativeBrightness() {
        let s = SetLightingNormalizer.adjustSuggestion(from: stats(exposure: 0.8), to: stats(exposure: 0.6))
        XCTAssertLessThan(s.brightness, 0)
    }

    func testFlatSourceGetsMoreContrastClamped() {
        let s = SetLightingNormalizer.adjustSuggestion(from: stats(contrast: 0.15), to: stats(contrast: 0.35))
        XCTAssertEqual(s.contrast, SetLightingNormalizer.contrastRange.upperBound, accuracy: 1e-9)
        let mild = SetLightingNormalizer.adjustSuggestion(from: stats(contrast: 0.30), to: stats(contrast: 0.36))
        XCTAssertGreaterThan(mild.contrast, 1)
        XCTAssertLessThanOrEqual(mild.contrast, SetLightingNormalizer.contrastRange.upperBound)
    }

    func testContrastySourceGetsLessContrastClamped() {
        let s = SetLightingNormalizer.adjustSuggestion(from: stats(contrast: 0.45), to: stats(contrast: 0.20))
        XCTAssertEqual(s.contrast, SetLightingNormalizer.contrastRange.lowerBound, accuracy: 1e-9)
    }

    func testTemperatureIsClampedToSliderRange() {
        let s = SetLightingNormalizer.adjustSuggestion(from: stats(kelvin: 3500), to: stats(kelvin: 8000))
        XCTAssertEqual(abs(s.temperature), SetLightingNormalizer.temperatureRange.upperBound, accuracy: 1e-9)
    }

    func testSuggestionModelIsExactInLinearLight() {
        // Model: out = (lin(in) − 0.5)·c + 0.5 + b. Los op voor p80 én p20 van de
        // referentie en controleer dat beide precies landen (klein verschil,
        // zodat geen klem meespeelt).
        let src = stats(exposure: 0.55, contrast: 0.32)
        let ref = stats(exposure: 0.60, contrast: 0.30)
        let s = SetLightingNormalizer.adjustSuggestion(from: src, to: ref)
        XCTAssertNotEqual(s, .neutral, "buiten de exposure-tolerantie")
        XCTAssertLessThan(s.contrast, SetLightingNormalizer.contrastRange.upperBound, "geen klem in het spel")
        func model(_ v: Double) -> Double { (SetLightingNormalizer.linear(v) - 0.5) * s.contrast + 0.5 + s.brightness }
        XCTAssertEqual(model(0.55), SetLightingNormalizer.linear(0.60), accuracy: 1e-6)
        XCTAssertEqual(model(0.23), SetLightingNormalizer.linear(0.30), accuracy: 1e-6)
    }

    func testRefineLandsOnTargetExposure() throws {
        let dark = solid(0.5, size: 64)
        let ref = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: solid(0.6, size: 64)))
        let src = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: dark))
        let suggestion = SetLightingNormalizer.adjustSuggestion(from: src, to: ref)
        XCTAssertGreaterThan(suggestion.brightness, 0)
        let refined = SetLightingNormalizer.refine(suggestion, raw: dark, to: ref)
        let rendered = try XCTUnwrap(PortraitEnhancer.colorAdjust(
            dark, brightness: refined.brightness, contrast: refined.contrast,
            saturation: 1, temperatureShift: refined.temperature
        ))
        let after = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: rendered))
        XCTAssertEqual(after.exposure, ref.exposure, accuracy: 0.03, "verfijnde brightness landt op de referentie-exposure")
    }

    func testRefineDoesNotTouchNeutralComponents() throws {
        let img = solid(0.5, size: 32)
        let ref = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: solid(0.5, size: 32)))
        XCTAssertEqual(SetLightingNormalizer.refine(.neutral, raw: img, to: ref), .neutral)
    }

    func testQualityScorePrefersWellLit() {
        let good = SetLightingNormalizer.qualityScore(stats(exposure: 0.65))
        XCTAssertEqual(good, 0)
        XCTAssertEqual(SetLightingNormalizer.qualityScore(stats(exposure: 0.68, contrast: 0.56)), 0, "studiolicht telt als goed belicht")
        XCTAssertLessThan(good, SetLightingNormalizer.qualityScore(stats(exposure: 0.2)))
        XCTAssertLessThan(good, SetLightingNormalizer.qualityScore(stats(exposure: 0.95)))
        XCTAssertLessThan(good, SetLightingNormalizer.qualityScore(stats(kelvin: 3200)))
    }

    func testBestLitTieBreaksOnCrispestLight() throws {
        // Beide goed belicht, duidelijk anders (kelvin 700 uiteen); de contrastrijkste wint.
        let flat = stats(kelvin: 5100, contrast: 0.32)
        let studio = stats(kelvin: 5800, contrast: 0.56)
        XCTAssertEqual(try XCTUnwrap(SetLightingNormalizer.chooseTarget([flat, studio])).target, .portrait(1))
        XCTAssertEqual(try XCTUnwrap(SetLightingNormalizer.chooseTarget([studio, flat])).target, .portrait(0))
        XCTAssertEqual(try XCTUnwrap(SetLightingNormalizer.chooseTarget([flat, studio], preferred: 0)).target, .portrait(0), "expliciete voorkeur gaat vóór")
    }

    func testChooseTargetPrefersMajorityPattern() throws {
        let set = [stats(), stats(exposure: 0.66), stats(exposure: 0.25), stats(kelvin: 5850)]
        let choice = try XCTUnwrap(SetLightingNormalizer.chooseTarget(set))
        guard case .centroid(let centroid) = choice.target else { return XCTFail("verwacht het patroon van de set") }
        XCTAssertEqual(choice.adjust, [2], "alleen de buitenstaander wordt aangepast")
        XCTAssertEqual(centroid.exposure, 0.65, accuracy: 0.02)
    }

    func testChooseTargetTwoDifferentPicksBestLit() throws {
        let choice = try XCTUnwrap(SetLightingNormalizer.chooseTarget([stats(exposure: 0.2), stats(exposure: 0.65)]))
        XCTAssertEqual(choice.target, .portrait(1))
        XCTAssertEqual(choice.adjust, [0])
    }

    func testChooseTargetTwoIdenticalAdjustsNothing() throws {
        let choice = try XCTUnwrap(SetLightingNormalizer.chooseTarget([stats(), stats()]))
        guard case .centroid = choice.target else { return XCTFail("twee gelijke = één patroon") }
        XCTAssertEqual(choice.adjust, [])
    }

    func testChooseTargetAllDifferentPicksBestLit() throws {
        let set = [
            stats(exposure: 0.15, kelvin: 3500),
            stats(exposure: 0.65, kelvin: 5800),
            stats(exposure: 0.95, kelvin: 8500),
            stats(exposure: 0.40, kelvin: 4200),
        ]
        let choice = try XCTUnwrap(SetLightingNormalizer.chooseTarget(set))
        XCTAssertEqual(choice.target, .portrait(1))
        XCTAssertEqual(choice.adjust, [0, 2, 3])
    }

    func testChooseTargetPreferredBreaksTies() throws {
        // Beide ideaal belicht (score 0) maar duidelijk anders (kelvin 600 uiteen).
        let set = [stats(kelvin: 5200), stats(kelvin: 5800)]
        XCTAssertEqual(try XCTUnwrap(SetLightingNormalizer.chooseTarget(set, preferred: 1)).target, .portrait(1))
        XCTAssertEqual(try XCTUnwrap(SetLightingNormalizer.chooseTarget(set, preferred: 0)).target, .portrait(0))
        XCTAssertEqual(try XCTUnwrap(SetLightingNormalizer.chooseTarget(set)).target, .portrait(0), "zonder voorkeur: laagste index")
    }

    func testChooseTargetEdgeCases() throws {
        XCTAssertNil(SetLightingNormalizer.chooseTarget([]))
        let single = try XCTUnwrap(SetLightingNormalizer.chooseTarget([stats()]))
        XCTAssertEqual(single.target, .portrait(0))
        XCTAssertEqual(single.adjust, [])
    }
}
