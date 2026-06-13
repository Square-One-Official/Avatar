import CoreGraphics
import XCTest
@testable import AvatarKit

/// E12.2: set-brede lichtnormalisatie. Bewijst dat het gemiddelde van een
/// donker beeld naar een lichte referentie schuift (en niet voorbijschiet),
/// en dat de afmetingen behouden blijven.
final class SetLightingNormalizerTests: XCTestCase {
    private func solid(_ value: CGFloat, size: Int = 8) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: value, green: value, blue: value, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }

    func testDarkImageMovesTowardBrightReference() throws {
        let dark = solid(0.2)
        let bright = solid(0.8)
        let ref = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: bright))
        let darkStats = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: dark))

        let matched = try XCTUnwrap(SetLightingNormalizer.match(dark, to: ref))
        let matchedStats = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: matched))

        // Lichter dan voorheen…
        XCTAssertGreaterThan(matchedStats.luma, darkStats.luma)
        // …en niet voorbij de referentie geschoten (gain is geklemd op 1.6,
        // 0.2 → max 0.32, dus zeker onder 0.8).
        XCTAssertLessThanOrEqual(matchedStats.luma, ref.luma + 0.01)
    }

    func testDimensionsPreserved() throws {
        let img = solid(0.5, size: 12)
        let ref = try XCTUnwrap(SetLightingNormalizer.referenceStats(of: solid(0.6)))
        let out = try XCTUnwrap(SetLightingNormalizer.match(img, to: ref))
        XCTAssertEqual(out.width, 12)
        XCTAssertEqual(out.height, 12)
    }
}
