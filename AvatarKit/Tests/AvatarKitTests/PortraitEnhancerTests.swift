import CoreGraphics
import XCTest
@testable import AvatarKit

/// E12.1: de lokale Core Image-retouch. Bewijst dat beide niveaus een beeld
/// teruggeven met dezelfde afmetingen (de auto-adjust-extent wordt netjes
/// terug-gecropt) en dat de pixels daadwerkelijk veranderen.
final class PortraitEnhancerTests: XCTestCase {
    /// Een 8×8-testbeeld met een kleurverloop zodat de filters iets te doen
    /// hebben (een vlak beeld zou door sommige auto-adjusts ongemoeid blijven).
    private func sampleImage(width: Int = 8, height: Int = 8) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for y in 0..<height {
            for x in 0..<width {
                let r = CGFloat(x) / CGFloat(width)
                let g = CGFloat(y) / CGFloat(height)
                ctx.setFillColor(red: r, green: g, blue: 0.4, alpha: 1)
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return ctx.makeImage()!
    }

    func testMagicRetouchPreservesDimensions() throws {
        let input = sampleImage()
        let out = try XCTUnwrap(PortraitEnhancer.magicRetouch(input))
        XCTAssertEqual(out.width, input.width)
        XCTAssertEqual(out.height, input.height)
    }

    func testImproveLightingPreservesDimensions() throws {
        let input = sampleImage()
        let out = try XCTUnwrap(PortraitEnhancer.improveLighting(input))
        XCTAssertEqual(out.width, input.width)
        XCTAssertEqual(out.height, input.height)
    }

    func testRetouchChangesPixels() throws {
        let input = sampleImage(width: 16, height: 16)
        let out = try XCTUnwrap(PortraitEnhancer.magicRetouch(input))
        XCTAssertEqual(out.width, 16)
        // Vergelijk de ruwe bytes: de retouch moet iets wijzigen.
        XCTAssertNotEqual(pixelBytes(of: out), pixelBytes(of: input))
    }

    private func pixelBytes(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return buffer
    }
}
