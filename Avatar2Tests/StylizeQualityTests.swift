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

    func testBlurDetectionDisabledByDefault() {
        XCTAssertFalse(StylizeQuality.blurDetectionEnabled)
    }

    func testCutoutDimensions() {
        let (w, h) = StylizeQuality.cutoutDimensions(for: solidImage(w: 640, h: 480))
        XCTAssertEqual(w, 640)
        XCTAssertEqual(h, 480)
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
