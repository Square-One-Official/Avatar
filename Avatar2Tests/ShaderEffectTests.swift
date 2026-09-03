// E38.1 — Toetst het shader-fundament: (1) de catalogus/laag-model is consistent
// (elke shader levert een default-laag met al z'n params), en (2) élke shader uit
// de catalogus laat zich via de SwiftUI-haak op een view toepassen en met
// `ImageRenderer` naar een beeld van de JUISTE maat rasteren (bewijst dat de
// Metal-functies linken en de modifier-keten niet crasht). Dit is het contract
// waar de live-canvas-render (E38.2) en het shaders-paneel (E37.7) op leunen.

import SwiftUI
import XCTest
@testable import Avatar2

@MainActor
final class ShaderEffectTests: XCTestCase {

    func testCatalogProducesConsistentDefaultLayers() {
        XCTAssertFalse(ShaderCatalog.all.isEmpty)
        for effect in ShaderCatalog.all {
            XCTAssertEqual(ShaderCatalog.effect(for: effect.key), effect)
            let layer = effect.makeLayer()
            XCTAssertEqual(layer.key, effect.key)
            XCTAssertTrue(layer.enabled)
            // Elke slider-param zit met z'n default in de laag.
            for p in effect.params {
                XCTAssertEqual(layer.params[p.key], p.defaultValue, "param \(p.key) van \(effect.key)")
            }
        }
    }

    func testEachShaderRendersImageAtCorrectSize() {
        for effect in ShaderCatalog.all {
            let view = Rectangle()
                .fill(Color.blue)
                .frame(width: 80, height: 40)
                .bannerShaders([effect.makeLayer()])
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let cg = renderer.cgImage
            XCTAssertNotNil(cg, "shader \(effect.key) renderde geen beeld")
            XCTAssertEqual(cg?.width, 80, "shader \(effect.key) breedte")
            XCTAssertEqual(cg?.height, 40, "shader \(effect.key) hoogte")
        }
    }

    func testDisabledLayerIsSkipped() {
        var layer = ShaderCatalog.all[0].makeLayer()
        layer.enabled = false
        let view = Rectangle().fill(Color.red).frame(width: 40, height: 20).bannerShaders([layer])
        let cg = ImageRenderer(content: view).cgImage
        XCTAssertNotNil(cg)
    }

    // MARK: E37.19 (audit-B6) — Halftone blendt i.p.v. de bron weg te gooien

    func testHalftoneHasIntensityParamWithReadableDefault() throws {
        let effect = try XCTUnwrap(ShaderCatalog.effect(for: "halftone"))
        let intensity = try XCTUnwrap(effect.params.first { $0.key == "intensity" })
        XCTAssertEqual(intensity.range, 0...1)
        XCTAssertEqual(intensity.defaultValue, 0.6, accuracy: 0.0001,
                       "default hoort de achtergrond/tekst herkenbaar te laten (±0,6)")
        // Arg-volgorde moet de Metal-signatuur spiegelen: (scale, intensity).
        XCTAssertEqual(effect.params.map(\.key), ["scale", "intensity"])
    }

    /// intensity 0 → bron ongemoeid; default (0.6) → bronkleur blijft dominant
    /// zichtbaar; intensity 1 → puur zwart/wit (geen kleurzweem meer).
    func testHalftoneIntensityBlendsSourceColour() throws {
        let effect = try XCTUnwrap(ShaderCatalog.effect(for: "halftone"))

        func render(intensity: Double?) throws -> CGImage {
            var layer = effect.makeLayer()
            if let intensity { layer.params["intensity"] = intensity }
            let view = Rectangle()
                .fill(Color(red: 0, green: 0, blue: 1))
                .frame(width: 80, height: 40)
                .bannerShaders([layer])
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            return try XCTUnwrap(renderer.cgImage)
        }

        let untouched = try render(intensity: 0)
        XCTAssertGreaterThan(meanChannel(untouched, channel: 2), 180, "intensity 0 hoort de bron ongemoeid te laten")
        XCTAssertLessThan(meanChannel(untouched, channel: 0), 80)

        let defaulted = try render(intensity: nil) // catalogus-default (0.6)
        XCTAssertGreaterThan(
            meanChannel(defaulted, channel: 2), meanChannel(defaulted, channel: 0) + 20,
            "op default-instellingen hoort de bronkleur herkenbaar te blijven"
        )

        let full = try render(intensity: 1)
        XCTAssertEqual(
            meanChannel(full, channel: 0), meanChannel(full, channel: 2), accuracy: 14,
            "intensity 1 = puur zwart/wit-stippen (kanaal-neutraal)"
        )
    }

    /// Oudere persistente lagen (alleen `scale` in params, van vóór 37.19)
    /// moeten blijven werken en op de intensity-default terugvallen.
    func testLegacyHalftoneLayerWithoutIntensityStillRenders() throws {
        let legacy = BannerShaderLayer(key: "halftone", params: ["scale": 12], enabled: true)
        let view = Rectangle().fill(Color.blue).frame(width: 80, height: 40).bannerShaders([legacy])
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let cg = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(cg.width, 80)
        XCTAssertEqual(cg.height, 40)
    }

    /// Gemiddelde waarde (0…255) van één kanaal (0=R, 1=G, 2=B) in sRGB.
    private func meanChannel(_ cg: CGImage, channel: Int) -> Double {
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
        for i in stride(from: channel, to: buf.count, by: 4) { sum += Double(buf[i]) }
        return sum / Double(w * h)
    }
}
