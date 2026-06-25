import CoreGraphics
import XCTest
@testable import AvatarKit

/// E34.1: BannerCompositor (wijde, ondoorzichtige cover) + DominantColor
/// (rand-bemonstering voor de "Match avatar"-modus).
final class BannerCompositorTests: XCTestCase {

    /// Leest pixel (x,y) met top-left origin (zelfde helper-patroon als
    /// BackgroundCompositorTests).
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let w = image.width, h = image.height
        let bpr = w * 4
        var buf = [UInt8](repeating: 0, count: h * bpr)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: bpr, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let row = h - 1 - y
        let i = row * bpr + x * 4
        return (Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2]), Int(buf[i + 3]))
    }

    private func makeSolid(red: CGFloat, green: CGFloat, blue: CGFloat, size: Int = 64) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }

    func testColorFillIsWideAndOpaque() throws {
        let out = try BannerCompositor.composite(
            fill: .color(red: 0, green: 0, blue: 1),
            size: CGSize(width: 1584, height: 396)
        )
        XCTAssertEqual(out.width, 1584)
        XCTAssertEqual(out.height, 396)
        let center = pixel(out, x: 792, y: 198)
        XCTAssertGreaterThan(center.b, 200)
        XCTAssertLessThan(center.r, 60)
        XCTAssertEqual(center.a, 255)
    }

    func testImageBackgroundAspectFillsWideRect() throws {
        let out = try BannerCompositor.composite(
            fill: .image(makeSolid(red: 0, green: 0, blue: 1)),
            size: CGSize(width: 1500, height: 500)
        )
        XCTAssertEqual(out.width, 1500)
        XCTAssertEqual(out.height, 500)
        let center = pixel(out, x: 750, y: 250)
        XCTAssertGreaterThan(center.b, 200)
        XCTAssertEqual(center.a, 255)
    }

    /// Beeld met rode kern + groene rand: `edge()` levert (bijna) groen op,
    /// terwijl `average()` duidelijk roder is — bewijst dat de rand-bemonstering
    /// het onderwerp in het midden negeert.
    func testDominantColorEdgeSamplesBorderNotCentre() throws {
        let size = 100
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))   // groene rand
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))   // rode kern
        ctx.fill(CGRect(x: 30, y: 30, width: 40, height: 40))
        let image = ctx.makeImage()!

        let edge = try XCTUnwrap(DominantColor.edge(image, inset: 0.05))
        XCTAssertGreaterThan(edge.g, 0.8)
        XCTAssertLessThan(edge.r, 0.2)

        let avg = try XCTUnwrap(DominantColor.average(image))
        // De kern trekt het gemiddelde merkbaar naar rood — duidelijk hoger
        // dan de (vrijwel rode-loze) rand.
        XCTAssertGreaterThan(avg.r, edge.r + 0.05)
    }
}
