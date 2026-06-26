// E37.1 — BannerDocRenderer-fundament: een laag-stack (fill + tekstlaag) moet een
// ondoorzichtige wijde PNG van de JUISTE maat opleveren, de canvas-maat moet
// overschrijfbaar zijn (export-maat), en het Banner2→BannerDoc-migratiepad moet
// de bron-bytes als image-fill behouden. Toetst het render-contract waar de
// Studio (E37.2+) en de social-preview-compat (E37.6) op leunen.

import AppKit
import XCTest
@testable import Avatar2

final class BannerDocRenderTests: XCTestCase {

    /// Hoeveel pixels op (x,y) ondoorzichtig zijn (alpha == 255), top-down.
    private func opaqueRatio(_ cg: CGImage) -> Double {
        let w = cg.width, h = cg.height
        let bpr = w * 4
        var buf = [UInt8](repeating: 0, count: bpr * h)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var opaque = 0
        for i in stride(from: 3, to: buf.count, by: 4) where buf[i] == 255 { opaque += 1 }
        return Double(opaque) / Double(w * h)
    }

    func testFillPlusTextRendersOpaquePNGAtCanvasSize() {
        let layers = BannerLayers(
            fill: .solid(hex: "#2C3E50"),
            texts: [BannerTextLayer(string: "Aaavatar", fontSize: 96, colorHex: "#FFFFFF")]
        )
        let doc = BannerDoc(canvasSize: CGSize(width: 1500, height: 500), layers: layers)

        let cg = BannerDocRenderer.render(doc)
        XCTAssertNotNil(cg)
        guard let cg else { return }
        XCTAssertEqual(cg.width, 1500)
        XCTAssertEqual(cg.height, 500)
        // Solide fill → volledig ondoorzichtig (tekst tekent erbovenop, verlaagt het niet).
        XCTAssertEqual(opaqueRatio(cg), 1.0, accuracy: 0.001)
    }

    /// Telt (ongeveer) witte pixels — om te bewijzen dat een witte tekstlaag
    /// daadwerkelijk OP de donkere fill wordt getekend (de opacity-test hierboven
    /// zou ook zonder tekst slagen).
    private func nearWhiteRatio(_ cg: CGImage) -> Double {
        let w = cg.width, h = cg.height
        let bpr = w * 4
        var buf = [UInt8](repeating: 0, count: bpr * h)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var light = 0
        for i in stride(from: 0, to: buf.count, by: 4) where buf[i] > 200 && buf[i + 1] > 200 && buf[i + 2] > 200 {
            light += 1
        }
        return Double(light) / Double(w * h)
    }

    func testTextLayerActuallyDrawsPixels() {
        let dark = BannerDoc(canvasSize: CGSize(width: 1500, height: 500),
                             layers: BannerLayers(fill: .solid(hex: "#101010")))
        let withText = BannerDoc(canvasSize: CGSize(width: 1500, height: 500),
                                 layers: BannerLayers(fill: .solid(hex: "#101010"),
                                                      texts: [BannerTextLayer(string: "Aaavatar", fontSize: 120, colorHex: "#FFFFFF")]))
        guard let bare = BannerDocRenderer.render(dark), let texted = BannerDocRenderer.render(withText) else {
            return XCTFail("render gaf nil")
        }
        // De kale donkere fill heeft ~0 witte pixels; mét witte tekst méér.
        XCTAssertEqual(nearWhiteRatio(bare), 0, accuracy: 0.0005)
        XCTAssertGreaterThan(nearWhiteRatio(texted), 0.001, "witte tekstlaag tekende geen zichtbare pixels")
    }

    func testExportSizeOverridesCanvas() {
        let doc = BannerDoc(canvasSize: CGSize(width: 1500, height: 500), layers: BannerLayers(fill: .solid(hex: "#000000")))
        let cg = BannerDocRenderer.render(doc, size: CGSize(width: 1584, height: 396))
        XCTAssertNotNil(cg)
        XCTAssertEqual(cg?.width, 1584)
        XCTAssertEqual(cg?.height, 396)
    }

    func testBanner2MigrationKeepsImageBytes() {
        // 4×4 rode PNG als "platte" Banner2.
        let img = NSImage(size: NSSize(width: 4, height: 4))
        img.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 4, height: 4).fill(); img.unlockFocus()
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("kon test-PNG niet maken")
        }
        let banner2 = Banner2(name: "Legacy", imageData: png)
        let doc = BannerDoc.from(banner2: banner2)

        XCTAssertEqual(doc.name, "Legacy")
        XCTAssertEqual(doc.fillImageData, png)
        XCTAssertEqual(doc.layers.fill, .image)
        XCTAssertNotNil(BannerDocRenderer.render(doc, size: CGSize(width: 100, height: 100)))
    }
}
