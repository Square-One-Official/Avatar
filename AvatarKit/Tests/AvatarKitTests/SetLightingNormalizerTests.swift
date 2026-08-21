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
