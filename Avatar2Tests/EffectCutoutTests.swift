// E24.30 — de gating-heuristiek die bepaalt of een styled (vol) beeld opnieuw
// geïsoleerd moet worden. De her-isolatie zelf loopt via de router (Vision/
// ORMBG, in AvatarKit getest); hier toetsen we alleen de pure beslislogica:
// vrijstaand (transparante hoeken) vs vol beeld (opake hoeken).

import AppKit
import XCTest
@testable import Avatar2

final class EffectCutoutTests: XCTestCase {

    /// Bouwt een klein RGBA-beeld met een uniforme alpha (hoeken = die alpha).
    private func image(alpha: UInt8, size: Int = 8) -> NSImage {
        let bpr = size * 4
        var buf = [UInt8](repeating: 0, count: bpr * size)
        for i in stride(from: 0, to: buf.count, by: 4) {
            let a = Double(alpha) / 255.0
            buf[i] = UInt8(200 * a)   // premultiplied RGB
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
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }

    func testVrijstaandBeeldHerkendAlsCutout() {
        // transparante hoeken → vrijstaand
        XCTAssertTrue(ShellModel.hasTransparentCorners(image(alpha: 0)))
    }

    func testVolBeeldNietAlsCutout() {
        // opake hoeken (achtergrond) → NIET vrijstaand
        XCTAssertFalse(ShellModel.hasTransparentCorners(image(alpha: 255)))
    }

    func testNilGeeftFalse() {
        XCTAssertFalse(ShellModel.hasTransparentCorners(nil))
    }
}
