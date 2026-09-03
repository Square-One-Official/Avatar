// E41.2 — Toetst de lokale on-device Boost: een PNG van NxM moet er 2N×2M
// uitkomen en een geldige PNG blijven (bewijst dat de Core Image Lanczos+unsharp-
// keten draait en alpha-PNG teruggeeft). Maakt het bron-bitmap op EXACTE pixels
// (niet via NSImage-lockFocus, dat retina-schaalt) zodat de maat-assert klopt.

import AppKit
import XCTest
@testable import Avatar2

final class LocalUpscaleTests: XCTestCase {

    private func makePNG(_ w: Int, _ h: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    func testBoostDoublesDimensions() {
        let png = makePNG(64, 40)
        guard let out = LocalUpscale.boost(pngData: png, scale: 2.0),
              let rep = NSBitmapImageRep(data: out) else {
            return XCTFail("lokale upscale gaf nil")
        }
        XCTAssertEqual(rep.pixelsWide, 128)
        XCTAssertEqual(rep.pixelsHigh, 80)
    }

    func testBoostReturnsValidPNG() {
        let out = LocalUpscale.boost(pngData: makePNG(32, 32))
        XCTAssertNotNil(out)
        XCTAssertNotNil(out.flatMap { NSImage(data: $0) })
    }
}
