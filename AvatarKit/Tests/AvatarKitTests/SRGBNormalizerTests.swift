import CoreGraphics
import XCTest
@testable import AvatarKit

/// E02.5 (audit-B1): de importnormalisatie naar sRGB-RGBA8 — de éne plek
/// (ShellModel.runCutout) waar grayscale/CMYK-imports RGB worden vóór de
/// engines draaien. Plus de engine-guard `EngineRendering.outputColorSpace`,
/// de verdedigingslinie voor callers die níét door de normalisatie komen.
final class SRGBNormalizerTests: XCTestCase {

    private func assertSRGBRGBA8(_ image: CGImage, file: StaticString = #filePath,
                                 line: UInt = #line) {
        XCTAssertEqual(image.colorSpace?.name as String?,
                       CGColorSpace.sRGB as String, file: file, line: line)
        XCTAssertEqual(image.bitsPerComponent, 8, file: file, line: line)
        XCTAssertEqual(image.bitsPerPixel, 32, file: file, line: line)
    }

    /// RGBA-componenten (0–255) op pixel (x, y), y vanaf de bovenrand.
    private func rgba(at x: Int, _ y: Int, in image: CGImage) -> [UInt8] {
        let data = image.dataProvider!.data! as Data
        let offset = y * image.bytesPerRow + x * (image.bitsPerPixel / 8)
        return [data[offset], data[offset + 1], data[offset + 2], data[offset + 3]]
    }

    // MARK: - Normalisatie

    func testGrayscaleBecomesSRGBRGBA8() {
        let source = ColorSpaceFixtures.grayFlat(width: 12, height: 10, white: 0.5)
        XCTAssertEqual(source.colorSpace?.model, .monochrome) // premisse

        let out = SRGBNormalizer.normalized(source)
        assertSRGBRGBA8(out)
        XCTAssertEqual(out.width, 12)
        XCTAssertEqual(out.height, 10)
        // Mid-gray blijft neutraal (r=g=b) en opaak na de conversie.
        let px = rgba(at: 6, 5, in: out)
        XCTAssertEqual(px[0], px[1])
        XCTAssertEqual(px[1], px[2])
        XCTAssertEqual(px[3], 255)
        XCTAssertGreaterThan(px[0], 90)
        XCTAssertLessThan(px[0], 165)
    }

    func testCMYKBecomesSRGBRGBA8() {
        let source = ColorSpaceFixtures.cmykPortrait(width: 64, height: 80)
        XCTAssertEqual(source.colorSpace?.model, .cmyk) // premisse

        let out = SRGBNormalizer.normalized(source)
        assertSRGBRGBA8(out)
        XCTAssertEqual(out.width, 64)
        XCTAssertEqual(out.height, 80)
        // Lichte achtergrond-hoek vs. donker silhouet-centrum: het
        // contrast van de fixture overleeft de conversie.
        let corner = rgba(at: 1, 1, in: out)
        let center = rgba(at: 32, 40, in: out)
        XCTAssertGreaterThan(corner[0], 170)
        XCTAssertLessThan(center[0], 110)
    }

    func testWideGamutRGBIsConvertedToSRGB() {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let source = ColorSpaceFixtures.rgbFlat(width: 8, height: 8, space: p3)
        let out = SRGBNormalizer.normalized(source)
        XCTAssertFalse(out === source)
        assertSRGBRGBA8(out)
    }

    func testAlreadyNormalizedImagePassesThroughUntouched() {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let source = ColorSpaceFixtures.rgbFlat(width: 8, height: 8, space: srgb)
        XCTAssertTrue(SRGBNormalizer.isNormalized(source)) // premisse
        let out = SRGBNormalizer.normalized(source)
        XCTAssertTrue(out === source)
    }

    func testNormalizationPreservesAlpha() {
        // sRGB-canvas met transparante linkerhelft, maar in BGRA-bytevolgorde
        // (byteOrder32Little + premultipliedFirst) → telt níét als
        // genormaliseerd; de alpha moet de hertekening wél overleven.
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: 10, height: 10,
                            bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(CGColor(colorSpace: srgb, components: [1, 0, 0, 1])!)
        ctx.fill(CGRect(x: 5, y: 0, width: 5, height: 10))
        let source = ctx.makeImage()!
        XCTAssertFalse(SRGBNormalizer.isNormalized(source)) // premisse

        let out = SRGBNormalizer.normalized(source)
        assertSRGBRGBA8(out)
        XCTAssertEqual(rgba(at: 2, 5, in: out)[3], 0)   // transparant gebleven
        XCTAssertEqual(rgba(at: 7, 5, in: out)[3], 255) // opaak gebleven
    }

    // MARK: - Engine-guard (EngineRendering.outputColorSpace)

    func testOutputColorSpaceFallsBackToSRGBForNonRGB() {
        let gray = ColorSpaceFixtures.grayFlat(width: 4, height: 4, white: 0.5)
        XCTAssertEqual(EngineRendering.outputColorSpace(for: gray).name as String?,
                       CGColorSpace.sRGB as String)

        let cmyk = ColorSpaceFixtures.cmykPortrait(width: 8, height: 8)
        XCTAssertEqual(EngineRendering.outputColorSpace(for: cmyk).name as String?,
                       CGColorSpace.sRGB as String)
    }

    func testOutputColorSpaceKeepsRGBSourceSpace() {
        // sRGB blijft sRGB; wide-gamut RGB (P3) blijft P3 — de guard
        // corrigeert alléén niet-RGB-bronnen, hij knijpt geen gamut af.
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let sRGBImage = ColorSpaceFixtures.rgbFlat(width: 4, height: 4, space: srgb)
        XCTAssertEqual(EngineRendering.outputColorSpace(for: sRGBImage).name as String?,
                       CGColorSpace.sRGB as String)

        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let p3Image = ColorSpaceFixtures.rgbFlat(width: 4, height: 4, space: p3)
        XCTAssertEqual(EngineRendering.outputColorSpace(for: p3Image).name as String?,
                       CGColorSpace.displayP3 as String)
    }
}
