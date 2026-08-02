// E55.3 — regressietest voor de style-stacking-bug: met een actief effect is
// de meegegeven cutout het effect-beeld; de stylize-bron voor een NIEUWE
// generatie moet dan de effect-basis (`effectBaseData`) zijn. Vóór de fix
// styleerde effect B — na een tool-wissel die de paneel-identiteit ververst —
// A's output in plaats van het basisportret.

import AppKit
import AvatarKit
import XCTest
@testable import Avatar2

@MainActor
final class EffectsModelSourceTests: XCTestCase {

    private func solidImage(w: Int, h: Int) -> NSImage {
        let bpr = w * 4
        var buf = [UInt8](repeating: 255, count: bpr * h)
        let ctx = CGContext(
            data: &buf, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: w, height: h))
    }

    private func pixelWidth(_ image: NSImage) -> Int {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width ?? -1
    }

    private func makeModel(portrait: Portrait2?, current: NSImage) -> EffectsModel {
        EffectsModel(
            entitlement: EntitlementModel(auth: AuthService()),
            baseImage: current,
            portrait: portrait,
            cutoutImage: current,
            coordinator: nil,
            onApply: { _ in }
        )
    }

    func testCutoutSourceIsEffectBaseWhenEffectActive() {
        let base = solidImage(w: 10, h: 10)
        let styled = solidImage(w: 20, h: 20)
        let portrait = Portrait2(cutoutData: Data([1]))
        portrait.effectActiveRaw = "clay"
        portrait.effectBaseData = base.pngData()

        let model = makeModel(portrait: portrait, current: styled)
        // De bron voor een nieuwe generatie is de basis (10px), niet A's output (20px).
        XCTAssertEqual(pixelWidth(model.stylizeSource(choice: .cutout)), 10)
        // En de None-kaart toont diezelfde basis.
        XCTAssertEqual(pixelWidth(model.base), 10)
    }

    func testCutoutSourceIsCurrentCutoutWithoutActiveEffect() {
        let current = solidImage(w: 20, h: 20)
        let portrait = Portrait2(cutoutData: Data([1]))

        let model = makeModel(portrait: portrait, current: current)
        XCTAssertEqual(pixelWidth(model.stylizeSource(choice: .cutout)), 20)
    }

    func testOriginalSourceUnaffectedByActiveEffect() {
        // Het `.original`-pad leest `originalData` — dat raakt een effect nooit
        // aan, dus dit pad had de bug niet en mag niet van gedrag veranderen.
        let base = solidImage(w: 10, h: 10)
        let styled = solidImage(w: 20, h: 20)
        let original = solidImage(w: 30, h: 30)
        let portrait = Portrait2(cutoutData: Data([1]))
        portrait.effectActiveRaw = "clay"
        portrait.effectBaseData = base.pngData()
        portrait.originalData = original.pngData()

        let model = makeModel(portrait: portrait, current: styled)
        XCTAssertEqual(pixelWidth(model.stylizeSource(choice: .original)), 30)
    }
}
