// E27.6 (Tier 3) — de off-main thumbnail-decoder. Toetst de pure ImageIO-pass:
// downscale-naar-doelmaat, alpha-behoud (cutout-transparantie) en de neutrale/
// niet-neutrale Adjust-tak. De async store eromheen (ThumbnailStore) is dunne
// orkestratie; de zwaarte zit hier en is hier headless te verifiëren.

import AppKit
import XCTest
@testable import Avatar2

final class ThumbnailRendererTests: XCTestCase {

    /// Maakt een `size`×`size` RGBA-PNG met een uniforme alpha (premultiplied).
    private func pngData(alpha: UInt8, size: Int = 100) -> Data {
        let bpr = size * 4
        var buf = [UInt8](repeating: 0, count: bpr * size)
        for i in stride(from: 0, to: buf.count, by: 4) {
            let a = Double(alpha) / 255.0
            buf[i] = UInt8(200 * a)
            buf[i + 1] = UInt8(100 * a)
            buf[i + 2] = UInt8(50 * a)
            buf[i + 3] = alpha
        }
        let ctx = CGContext(
            data: &buf, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let cg = ctx.makeImage()!
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
    }

    /// Leest de alpha van pixel (0,0) uit een CGImage.
    private func cornerAlpha(_ cg: CGImage) -> UInt8 {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(
            data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Teken alléén de hoek-pixel (bron-rect 1×1 linksboven).
        ctx.draw(cg, in: CGRect(x: 0, y: CGFloat(1 - cg.height), width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return px[3]
    }

    func testDownscalesToMaxPixelSize() {
        let data = pngData(alpha: 255, size: 100)
        let out = ThumbnailRenderer.render(data: data, maxPixelSize: 40, adjust: .neutral)
        XCTAssertNotNil(out)
        // ImageIO schaalt de langste zijde naar maxPixelSize.
        XCTAssertEqual(max(out!.width, out!.height), 40)
        XCTAssertLessThanOrEqual(out!.width, 40)
        XCTAssertLessThanOrEqual(out!.height, 40)
    }

    func testPreservesTransparency() {
        // Volledig transparante bron → de gedownscalede thumb blijft transparant
        // (cutout-alpha mag niet wegvallen in de ImageIO-pass).
        let out = ThumbnailRenderer.render(data: pngData(alpha: 0), maxPixelSize: 40, adjust: .neutral)
        XCTAssertNotNil(out)
        XCTAssertLessThan(cornerAlpha(out!), 16)
    }

    func testPreservesOpacity() {
        let out = ThumbnailRenderer.render(data: pngData(alpha: 255), maxPixelSize: 40, adjust: .neutral)
        XCTAssertNotNil(out)
        XCTAssertGreaterThan(cornerAlpha(out!), 240)
    }

    func testNonNeutralAdjustStillRenders() {
        let adjust = PortraitAdjust(exposure: 0.2, contrast: 1.1, saturation: 1.2, temperature: 0.3)
        let out = ThumbnailRenderer.render(data: pngData(alpha: 255), maxPixelSize: 40, adjust: adjust)
        XCTAssertNotNil(out)
        XCTAssertEqual(max(out!.width, out!.height), 40)
    }

    func testInvalidDataReturnsNil() {
        XCTAssertNil(ThumbnailRenderer.render(data: Data([0, 1, 2, 3]), maxPixelSize: 40, adjust: .neutral))
    }
}
