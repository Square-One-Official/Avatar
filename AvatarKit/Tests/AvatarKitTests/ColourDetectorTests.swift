import CoreGraphics
import XCTest
@testable import AvatarKit

final class ColourDetectorTests: XCTestCase {
    func testGreyscaleIsNotColour() {
        XCTAssertFalse(ColourDetector.isLikelyColour(solid(0.5, 0.5, 0.5)))
        XCTAssertFalse(ColourDetector.isLikelyColour(solid(0.1, 0.1, 0.1)))
        XCTAssertFalse(ColourDetector.isLikelyColour(solid(0.95, 0.95, 0.95)))
    }

    func testStrongColourIsDetected() {
        XCTAssertTrue(ColourDetector.isLikelyColour(solid(0.9, 0.15, 0.1)))
        XCTAssertTrue(ColourDetector.isLikelyColour(solid(0.1, 0.6, 0.9)))
    }

    func testFaintSepiaTintIsNotColour() {
        // Channel spread ≈ 10/255 — under the chroma threshold of 25.
        XCTAssertFalse(ColourDetector.isLikelyColour(solid(0.52, 0.50, 0.48)))
    }

    func testTransparentImageIsNotColour() {
        XCTAssertFalse(ColourDetector.isLikelyColour(solid(0.9, 0.1, 0.1, alpha: 0)))
    }

    func testColourSubjectOnTransparentBackgroundIsDetected() {
        let image = band(
            size: 64,
            fill: (0, 0, 0, 0),
            bandY: 0, bandHeight: 64,
            bandRGB: (0.9, 0.1, 0.15),
            bandAlpha: 1
        )
        XCTAssertTrue(ColourDetector.isLikelyColour(image))
    }

    func testSmallColourSpeckDoesNotTrip() {
        // ~8% of samples are strongly coloured — under the 0.15 fraction.
        let image = band(
            size: 64,
            fill: (0.5, 0.5, 0.5, 1),
            bandY: 0, bandHeight: 5,
            bandRGB: (0.95, 0.1, 0.1)
        )
        XCTAssertFalse(ColourDetector.isLikelyColour(image))
    }

    func testColourRegionAboveFractionTrips() {
        // ~25% of samples are strongly coloured — above the 0.15 fraction.
        let image = band(
            size: 64,
            fill: (0.5, 0.5, 0.5, 1),
            bandY: 0, bandHeight: 16,
            bandRGB: (0.95, 0.1, 0.1)
        )
        XCTAssertTrue(ColourDetector.isLikelyColour(image))
    }

    // MARK: - Fixtures

    private func solid(
        _ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
        alpha: CGFloat = 1, size: Int = 32
    ) -> CGImage {
        rgb(r, g, b, alpha: alpha, size: size)
    }

    private func rgb(
        _ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
        alpha: CGFloat, size: Int
    ) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: r, green: g, blue: b, alpha: alpha)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }

    private func band(
        size: Int,
        fill: (CGFloat, CGFloat, CGFloat, CGFloat),
        bandY: Int, bandHeight: Int,
        bandRGB: (CGFloat, CGFloat, CGFloat),
        bandAlpha: CGFloat = 1
    ) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: fill.0, green: fill.1, blue: fill.2, alpha: fill.3)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setFillColor(red: bandRGB.0, green: bandRGB.1, blue: bandRGB.2, alpha: bandAlpha)
        ctx.fill(CGRect(x: 0, y: bandY, width: size, height: bandHeight))
        return ctx.makeImage()!
    }
}
