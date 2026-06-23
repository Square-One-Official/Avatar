// E27.8 — de alpha-bewuste canvas-hit-test (`isOpaqueAtNormalizedPoint`) bepaalt
// of een tik op het frame het ONDERWERP (opaque persoon-pixel) of enkel het FRAME
// (transparante pixel) selecteert. De full-bitmap `colorAt` is vervangen door een
// 1×1-context-sample; deze toetst dat de genormaliseerde-punt-geometrie (incl. de
// y-oriëntatie: v=0 = BOVEN) intact bleef — een verkeerde flip zou de selectie
// verticaal spiegelen.

import AppKit
import XCTest
@testable import Avatar2

final class AlphaHitTestTests: XCTestCase {

    /// Bouwt een top-down (rij 0 = BOVEN) grijswaarde-NSImage; `alpha(x,y)` met
    /// y=0 = bovenste rij, premultiplied.
    private func image(w: Int, h: Int, alpha: (Int, Int) -> UInt8) -> NSImage {
        let bpr = w * 4
        var buf = [UInt8](repeating: 0, count: bpr * h)
        for y in 0..<h {
            for x in 0..<w {
                let a = alpha(x, y)
                let i = y * bpr + x * 4
                buf[i] = a; buf[i + 1] = a; buf[i + 2] = a; buf[i + 3] = a
            }
        }
        let provider = CGDataProvider(data: Data(buf) as CFData)!
        let cg = CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }

    func testVerticalOrientation() {
        // Bovenste helft opaque, onderste transparant (y=0 = boven).
        let img = image(w: 8, h: 8) { _, y in y < 4 ? 255 : 0 }
        XCTAssertTrue(img.isOpaqueAtNormalizedPoint(u: 0.5, v: 0.1))   // boven → onderwerp
        XCTAssertFalse(img.isOpaqueAtNormalizedPoint(u: 0.5, v: 0.9))  // onder → frame
    }

    func testHorizontalOrientation() {
        let img = image(w: 8, h: 8) { x, _ in x < 4 ? 255 : 0 }
        XCTAssertTrue(img.isOpaqueAtNormalizedPoint(u: 0.1, v: 0.5))   // links → onderwerp
        XCTAssertFalse(img.isOpaqueAtNormalizedPoint(u: 0.9, v: 0.5))  // rechts → frame
    }

    func testCornersDistinct() {
        // Alleen de linksboven-kwadrant opaque → toetst x én y tegelijk.
        let img = image(w: 8, h: 8) { x, y in (x < 4 && y < 4) ? 255 : 0 }
        XCTAssertTrue(img.isOpaqueAtNormalizedPoint(u: 0.1, v: 0.1))   // linksboven
        XCTAssertFalse(img.isOpaqueAtNormalizedPoint(u: 0.9, v: 0.1))  // rechtsboven
        XCTAssertFalse(img.isOpaqueAtNormalizedPoint(u: 0.1, v: 0.9))  // linksonder
    }

    func testOutOfRangeIsSafeOpaque() {
        // Buiten [0,1] → veilig `true` (behoud "klik = onderwerp").
        let img = image(w: 4, h: 4) { _, _ in 0 }
        XCTAssertTrue(img.isOpaqueAtNormalizedPoint(u: -0.1, v: 0.5))
        XCTAssertTrue(img.isOpaqueAtNormalizedPoint(u: 0.5, v: 1.5))
    }
}
