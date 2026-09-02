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

    // E24.36 — resize-naar-origineel houdt een generatief resultaat (gelijke
    // ratio, andere pixelmaat) op de oude afmetingen zodat de opgeslagen
    // canvas-transform geldig blijft (geen positie-sprong na clothes/hair/effects).

    private func cgImage(w: Int, h: Int) -> CGImage {
        let bpr = w * 4
        var buf = [UInt8](repeating: 255, count: bpr * h)
        let ctx = CGContext(
            data: &buf, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    func testResizedNaarExacteAfmetingen() {
        // Een 832×1248-resultaat (Gemini ~1 MP) terug naar de cutout-maat 800×1200.
        let result = cgImage(w: 832, h: 1248)
        let resized = ShellModel.resized(result, to: CGSize(width: 800, height: 1200))
        XCTAssertNotNil(resized)
        // De pixelmaat moet exact gelijk zijn aan de oude cutout.
        XCTAssertEqual(resized?.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width, 800)
        XCTAssertEqual(resized?.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height, 1200)
    }

    func testResizedNulMaatGeeftNil() {
        XCTAssertNil(ShellModel.resized(cgImage(w: 10, h: 10), to: .zero))
    }

    // Quality rev2 — transform scale adjustment when keeping a higher-res cutout.

    func testAdjustedScalePreservesCanvasWidth() {
        let newScale = ShellModel.adjustedScaleForResolutionChange(
            oldWidth: 800, newWidth: 832, currentScale: 0.5
        )
        let oldImgW = 800.0 * 0.5
        let newImgW = 832.0 * newScale
        XCTAssertEqual(oldImgW, newImgW, accuracy: 0.001)
    }

    func testAdjustedScaleZeroScaleUnchanged() {
        XCTAssertEqual(
            ShellModel.adjustedScaleForResolutionChange(oldWidth: 800, newWidth: 832, currentScale: 0),
            0
        )
    }

    func testAdjustedScaleDoublingHalvesScale() {
        XCTAssertEqual(
            ShellModel.adjustedScaleForResolutionChange(oldWidth: 1024, newWidth: 2048, currentScale: 0.6),
            0.3,
            accuracy: 0.0001
        )
    }

    func testApplyAlphaMaskKeepsHigherResRGB() {
        let cutout = image(alpha: 255, size: 100)
        let styled = image(alpha: 255, size: 200)
        let masked = ShellModel.applyAlphaMask(from: cutout, to: styled)
        XCTAssertEqual(masked?.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width, 200)
        XCTAssertEqual(masked?.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height, 200)
    }

    func testAlphaCentroidFindsOpaqueRegion() {
        let bpr = 40 * 4
        var buf = [UInt8](repeating: 0, count: bpr * 40)
        // 10×10 opaque block centered at ~(20,20)
        for y in 15..<25 {
            for x in 15..<25 {
                let i = y * bpr + x * 4
                buf[i] = 200; buf[i + 1] = 100; buf[i + 2] = 50; buf[i + 3] = 255
            }
        }
        let ctx = CGContext(
            data: &buf, width: 40, height: 40, bitsPerComponent: 8,
            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let cg = ctx.makeImage()!
        let c = ShellModel.alphaCentroid(of: cg)!
        XCTAssertEqual(c.x, 19.5, accuracy: 0.6)
        XCTAssertEqual(c.y, 19.5, accuracy: 0.6)
    }

    func testPlacementOffsetCompensationScalesDrift() {
        let delta = ShellModel.placementOffsetCompensation(
            oldCentroid: CGPoint(x: 100, y: 200),
            newCentroid: CGPoint(x: 90, y: 190),
            scale: 0.5
        )
        XCTAssertNotNil(delta)
        XCTAssertEqual(delta!.dx, 5, accuracy: 0.001)
        XCTAssertEqual(delta!.dy, 5, accuracy: 0.001)
    }

    func testLikelyCutoutRequiresTransparentBorder() {
        // Vol opake beeld → geen cutout.
        XCTAssertFalse(ShellModel.isLikelyCutout(image(alpha: 255)))
    }

    func testLikelyCutoutAcceptsTransparentCutout() {
        // Uniform transparant → hoeken + rand transparant.
        XCTAssertTrue(ShellModel.isLikelyCutout(image(alpha: 0)))
    }

    /// Grijs matte rond onderwerp: transparante hoeken maar opake rand → geen cutout.
    func testLikelyCutoutRejectsGreyMatteWithTransparentCorners() {
        let size = 40
        let bpr = size * 4
        var buf = [UInt8](repeating: 0, count: bpr * size)
        for y in 0..<size {
            for x in 0..<size {
                let i = y * bpr + x * 4
                let isCorner = (x < 2 || x >= size - 2) && (y < 2 || y >= size - 2)
                let onGreyBand = !isCorner && (x < 6 || x >= size - 6 || y < 6 || y >= size - 6)
                let alpha: UInt8 = isCorner ? 0 : (onGreyBand ? 255 : 0)
                let a = Double(alpha) / 255.0
                buf[i] = UInt8(200 * a)
                buf[i + 1] = UInt8(200 * a)
                buf[i + 2] = UInt8(200 * a)
                buf[i + 3] = alpha
            }
        }
        let ctx = CGContext(
            data: &buf, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let img = NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: size, height: size))
        XCTAssertTrue(ShellModel.hasTransparentCorners(img))
        XCTAssertFalse(ShellModel.isLikelyCutout(img))
    }

    func testFillBodyFaceBoxNormaliseertVisionPixelRect() throws {
        let box = try XCTUnwrap(EditorView.normalizedFillBodyFaceBox(
            faceRect: CGRect(x: 200, y: 100, width: 300, height: 250),
            imageSize: CGSize(width: 1000, height: 1000)
        ))
        XCTAssertEqual(box.x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(box.y, 0.1, accuracy: 0.0001)
        XCTAssertEqual(box.width, 0.3, accuracy: 0.0001)
        XCTAssertEqual(box.height, 0.25, accuracy: 0.0001)
    }
}
