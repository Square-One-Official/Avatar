// Mesh-gradient-presets voor het Background-paneel: 10 uiGradients-paletten
// als overlapping radials, plus een renderbare PNG voor apply.

import XCTest
@testable import Avatar2

final class BackgroundKitGradientTests: XCTestCase {

    func testTenNamedMeshPresets() {
        let presets = BackgroundKit.gradientPresets
        XCTAssertEqual(presets.count, 10, "Gallery-Gradient-rij toont 10 presets")
        XCTAssertEqual(Set(presets.map(\.id)).count, 10, "preset-ids moeten uniek zijn")
        XCTAssertTrue(presets.allSatisfy { $0.blobs.count >= 4 }, "elke preset is een mesh (4 blobs)")
        XCTAssertTrue(presets.allSatisfy { !$0.name.isEmpty })
    }

    func testMeshPresetRendersOpaquePNG() {
        guard let png = BackgroundKit.renderGradientPNG(BackgroundKit.gradientPresets[0], side: 64),
              let image = NSImage(data: png),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return XCTFail("mesh-preset leverde geen PNG")
        }
        XCTAssertEqual(cg.width, 64)
        XCTAssertEqual(cg.height, 64)
        XCTAssertGreaterThan(png.count, 100)
    }

    func testMeshCornersDifferForPeach() {
        // Peach: warm rood linksboven, crème rechtsonder — geen vlakke fill.
        let peach = BackgroundKit.gradientPresets[0]
        XCTAssertEqual(peach.id, "peach")
        guard let cg = BackgroundKit.renderMeshImage(
            blobs: peach.blobs,
            size: CGSize(width: 32, height: 32)
        ) else {
            return XCTFail("mesh render nil")
        }
        let topLeft = pixel(cg, x: 2, y: 2)
        let bottomRight = pixel(cg, x: 29, y: 29)
        let dr = Double(topLeft.0) - Double(bottomRight.0)
        let dg = Double(topLeft.1) - Double(bottomRight.1)
        let db = Double(topLeft.2) - Double(bottomRight.2)
        let distance = (dr * dr + dg * dg + db * db).squareRoot()
        XCTAssertGreaterThan(distance, 40, "mesh-hoekpunten moeten duidelijk andere tinten zijn")
    }

    @MainActor
    func testLinearCMSPathStillRenders() {
        let png = BackgroundKit.renderGradientPNG(
            [BackgroundKit.rgb(0x6EC6FF), BackgroundKit.rgb(0xE3F2FF)],
            side: 32
        )
        XCTAssertNotNil(png)
        XCTAssertGreaterThan(png?.count ?? 0, 50)
    }

    private func pixel(_ cg: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        // CGImage is top-down na draw in this context.
        let i = (y * w + x) * 4
        return (buf[i], buf[i + 1], buf[i + 2])
    }
}
