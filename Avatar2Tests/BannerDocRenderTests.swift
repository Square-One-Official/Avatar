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

    func testTextAlignmentLeftDrawsLeftOfCenter() {
        let center = BannerTextLayer(string: "Hi", fontSize: 48, colorHex: "#FFFFFF", alignRaw: 1, x: 0.5, y: 0.5)
        let left = BannerTextLayer(string: "Hi", fontSize: 48, colorHex: "#FFFFFF", alignRaw: 0, x: 0.5, y: 0.5)
        let right = BannerTextLayer(string: "Hi", fontSize: 48, colorHex: "#FFFFFF", alignRaw: 2, x: 0.5, y: 0.5)
        let base = BannerLayers(fill: .solid(hex: "#000000"))
        guard let centerImg = BannerDocRenderer.render(BannerDoc(layers: BannerLayers(fill: base.fill, texts: [center]))),
              let leftImg = BannerDocRenderer.render(BannerDoc(layers: BannerLayers(fill: base.fill, texts: [left]))),
              let rightImg = BannerDocRenderer.render(BannerDoc(layers: BannerLayers(fill: base.fill, texts: [right])))
        else {
            return XCTFail("render gaf nil")
        }
        let centerWhiteX = whiteCentroidX(centerImg)
        let leftWhiteX = whiteCentroidX(leftImg)
        let rightWhiteX = whiteCentroidX(rightImg)
        XCTAssertGreaterThan(leftWhiteX, centerWhiteX)
        XCTAssertLessThan(rightWhiteX, centerWhiteX)
    }

    private func whiteCentroidX(_ cg: CGImage) -> Double {
        let w = cg.width, h = cg.height
        let bpr = w * 4
        var buf = [UInt8](repeating: 0, count: bpr * h)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sumX = 0.0, count = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let i = y * bpr + x * 4
                if buf[i] > 200 && buf[i + 1] > 200 && buf[i + 2] > 200 {
                    sumX += Double(x)
                    count += 1
                }
            }
        }
        return count > 0 ? sumX / count : 0
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

    func testExcludingTextIDOmitsThatLayer() {
        let layer = BannerTextLayer(string: "Aaavatar", fontSize: 120, colorHex: "#FFFFFF")
        let doc = BannerDoc(canvasSize: CGSize(width: 1500, height: 500),
                            layers: BannerLayers(fill: .solid(hex: "#101010"), texts: [layer]))
        guard let withText = BannerDocRenderer.render(doc),
              let excluded = BannerDocRenderer.render(doc, excludingTextIDs: [layer.id]) else {
            return XCTFail("render gaf nil")
        }
        // De bewerkte laag weglaten → (vrijwel) geen witte tekstpixels meer.
        XCTAssertGreaterThan(nearWhiteRatio(withText), 0.001)
        XCTAssertEqual(nearWhiteRatio(excluded), 0, accuracy: 0.0005,
                       "uitgesloten tekstlaag werd toch gebakken")
    }

    func testPlaceholderStringIsNotRendered() {
        let layer = BannerTextLayer(string: BannerTextPresets.placeholder, fontSize: 120, colorHex: "#FFFFFF")
        let doc = BannerDoc(canvasSize: CGSize(width: 1500, height: 500),
                            layers: BannerLayers(fill: .solid(hex: "#101010"), texts: [layer]))
        guard let cg = BannerDocRenderer.render(doc) else { return XCTFail("render gaf nil") }
        XCTAssertEqual(nearWhiteRatio(cg), 0, accuracy: 0.0005,
                       "placeholder-tekst mag niet meegebakken worden")
    }

    func testLogoLayerDrawsVisiblePixels() {
        guard let logoPNG = solidPNG(width: 32, height: 32, color: .systemBlue) else {
            return XCTFail("kon logo-PNG niet maken")
        }
        let doc = BannerDoc(canvasSize: CGSize(width: 400, height: 200),
                            layers: BannerLayers(fill: .solid(hex: "#101010")))
        doc.logoImageData = logoPNG
        doc.layers.logo = BannerLogoLayer(x: 0.5, y: 0.5, scale: 0.3)
        guard let cg = BannerDocRenderer.render(doc) else { return XCTFail("render gaf nil") }
        XCTAssertGreaterThan(blueishRatio(cg), 0.001, "logo tekende geen zichtbare pixels")
    }

    func testBackgroundFocalShiftsImageContent() {
        guard let wide = gradientPNG(width: 200, height: 20) else {
            return XCTFail("kon gradient-PNG niet maken")
        }
        func render(focalX: Double) -> CGImage? {
            let doc = BannerDoc(canvasSize: CGSize(width: 200, height: 100),
                                layers: BannerLayers(fill: .image))
            doc.applyFillImage(wide, resetFraming: false)
            doc.fillImageFocalX = focalX
            doc.fillImageFocalY = 0.5
            return BannerDocRenderer.render(doc)
        }
        guard let left = render(focalX: 0.1), let right = render(focalX: 0.9) else {
            return XCTFail("render gaf nil")
        }
        let leftMean = meanRed(left)
        let rightMean = meanRed(right)
        XCTAssertNotEqual(leftMean, rightMean, accuracy: 1.0, "focal shift veranderde de zichtbare crop niet")
    }

    func testImageFillCodableBackwardCompat() throws {
        let json = """
        {"fill":"image","texts":[],"shaders":[]}
        """.data(using: .utf8)!
        let layers = try JSONDecoder().decode(BannerLayers.self, from: json)
        XCTAssertEqual(layers.fill, .image)
    }

    func testImageFillZoomProducesOpaqueOutput() {
        guard let png = solidPNG(width: 80, height: 80, color: .systemGreen) else {
            return XCTFail("kon PNG niet maken")
        }
        let doc = BannerDoc(canvasSize: CGSize(width: 200, height: 100),
                            layers: BannerLayers(fill: .image))
        doc.applyFillImage(png)
        doc.fillImageZoom = 2.0
        guard let cg = BannerDocRenderer.render(doc) else { return XCTFail("render gaf nil") }
        XCTAssertEqual(opaqueRatio(cg), 1.0, accuracy: 0.001)
    }

    private func solidPNG(width: Int, height: Int, color: NSColor) -> Data? {
        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func gradientPNG(width: Int, height: Int) -> Data? {
        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        for x in 0..<width {
            let t = CGFloat(x) / CGFloat(max(width - 1, 1))
            NSColor(calibratedRed: t, green: 0, blue: 1 - t, alpha: 1).setFill()
            NSRect(x: x, y: 0, width: 1, height: height).fill()
        }
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func blueishRatio(_ cg: CGImage) -> Double {
        let w = cg.width, h = cg.height
        let bpr = w * 4
        var buf = [UInt8](repeating: 0, count: bpr * h)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var hits = 0
        for i in stride(from: 0, to: buf.count, by: 4) where buf[i + 2] > buf[i] && buf[i + 2] > 150 {
            hits += 1
        }
        return Double(hits) / Double(w * h)
    }

    private func meanRed(_ cg: CGImage) -> Double {
        let w = cg.width, h = cg.height
        let bpr = w * 4
        var buf = [UInt8](repeating: 0, count: bpr * h)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        for i in stride(from: 0, to: buf.count, by: 4) { sum += Double(buf[i]) }
        return sum / Double(buf.count / 4)
    }
}
