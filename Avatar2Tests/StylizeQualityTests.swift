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

    func testLowResolutionLongEdgeBelow1024() {
        XCTAssertTrue(StylizeQuality.isLowResolution(solidImage(w: 800, h: 600)))
    }

    func testSharp2048NotLowResolution() {
        XCTAssertFalse(StylizeQuality.isLowResolution(solidImage(w: 1536, h: 2048)))
    }

    func testPostBoostOfferedWhenResultSmallerThanCutout() {
        let cutout = solidImage(w: 1600, h: 2400)
        let result = solidImage(w: 832, h: 1248)
        XCTAssertTrue(StylizeQuality.shouldOfferPostBoost(result: result, cutoutBefore: cutout))
    }

    func testPostBoostNotOfferedWhenResultMatchesCutout() {
        let cutout = solidImage(w: 832, h: 1248)
        XCTAssertFalse(StylizeQuality.shouldOfferPostBoost(result: cutout, cutoutBefore: cutout))
    }

    func testBlurDetectionDisabledByDefault() {
        XCTAssertFalse(StylizeQuality.blurDetectionEnabled)
    }

    func testCutoutDimensions() {
        let (w, h) = StylizeQuality.cutoutDimensions(for: solidImage(w: 640, h: 480))
        XCTAssertEqual(w, 640)
        XCTAssertEqual(h, 480)
    }
}
