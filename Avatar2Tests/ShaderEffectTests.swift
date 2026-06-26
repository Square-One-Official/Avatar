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
}
