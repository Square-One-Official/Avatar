import CoreGraphics
import XCTest
@testable import AvatarKit

/// E07.2: BackgroundCompositor — vierkante, ondoorzichtige export op volle
/// resolutie; cutout-transform mapt van canvas-units naar exportpixels.
final class BackgroundCompositorTests: XCTestCase {

    /// Halftransparante cutout (links rood-opaak, rechts transparant) zodat
    /// de achtergrond door de transparante helft zichtbaar moet zijn.
    private func makeCutout(width: Int = 64, height: Int = 64) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        return ctx.makeImage()!
    }

    /// Leest pixel (x,y) met top-left origin door het hele beeld één keer
    /// in een bekend RGBA-buffer te renderen en te indexeren.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let w = image.width, h = image.height
        let bpr = w * 4
        var buf = [UInt8](repeating: 0, count: h * bpr)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: bpr, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // CGContext is bottom-left origin; teken normaal en flip de y bij index.
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let row = h - 1 - y
        let i = row * bpr + x * 4
        return (Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2]), Int(buf[i + 3]))
    }

    func testOutputIsSquareAndOpaque() throws {
        // Kleine, gecentreerde plaatsing (0,5× in 64-units canvas) zodat de
        // hoeken pure achtergrond zijn.
        let out = try BackgroundCompositor.composite(
            cutout: makeCutout(),
            over: .color(red: 0, green: 0, blue: 1),
            placement: .init(offsetX: 16, offsetY: 16, scale: 0.5, canvasUnit: 64),
            outputSize: 256
        )
        XCTAssertEqual(out.width, 256)
        XCTAssertEqual(out.height, 256)
        // Hoekpixel valt buiten de cutout → pure blauwe achtergrond, opaak.
        let corner = pixel(out, x: 4, y: 4)
        XCTAssertGreaterThan(corner.b, 200)
        XCTAssertLessThan(corner.r, 60)
        XCTAssertEqual(corner.a, 255)
    }

    func testTransparentRegionShowsBackground() throws {
        // Volledige canvas-dekkende plaatsing (scale zo dat 64-units cutout
        // het 64-unit canvas vult), rechterhelft transparant → achtergrond.
        let out = try BackgroundCompositor.composite(
            cutout: makeCutout(width: 64, height: 64),
            over: .color(red: 0, green: 1, blue: 0),
            placement: .init(offsetX: 0, offsetY: 0, scale: 1, canvasUnit: 64),
            outputSize: 128
        )
        // Rechterkant (transparante helft van de cutout) → groene achtergrond.
        let right = pixel(out, x: 100, y: 64)
        XCTAssertGreaterThan(right.g, 200)
        XCTAssertLessThan(right.r, 60)
        // Linkerkant (opake rode helft) → rood.
        let left = pixel(out, x: 20, y: 64)
        XCTAssertGreaterThan(left.r, 200)
        XCTAssertLessThan(left.g, 80)
    }

    func testImageBackgroundFillsCanvas() throws {
        // Effen blauwe achtergrondafbeelding + fully transparante cutout →
        // export is overal blauw.
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let bgCtx = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bgCtx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        bgCtx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let bg = bgCtx.makeImage()!

        let clear = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        clear.clear(CGRect(x: 0, y: 0, width: 16, height: 16))
        let transparent = clear.makeImage()!

        let out = try BackgroundCompositor.composite(
            cutout: transparent,
            over: .image(bg),
            placement: .init(offsetX: 0, offsetY: 0, scale: 1, canvasUnit: 16),
            outputSize: 128
        )
        let center = pixel(out, x: 64, y: 64)
        XCTAssertGreaterThan(center.b, 200)
        XCTAssertEqual(center.a, 255)
    }
}
