import CoreGraphics
import CoreImage
import XCTest
@testable import AvatarKit

/// Vision herkent synthetische beelden niet als gezicht, dus de geometrie-
/// en kleurwiskunde van TeethWhitener wordt hier deterministisch getest via
/// de interne pure functies (per-pixel probes, vaste fixtures); end-to-end
/// dekt het noFaceFound-pad. Zelfde strategie als ClothesMaskGeneratorTests.
final class TeethWhitenerTests: XCTestCase {

    /// Leest het rood-kanaal [0,1] op (x, y) — BOTTOM-LEFT origin, de
    /// CI-ruimte waarin TeethWhitener alle geometrie voert (bewust anders
    /// dan de top-left probe van ClothesMaskGeneratorTests).
    private func value(at x: CGFloat, _ y: CGFloat, in image: CIImage) -> Double {
        let rect = CGRect(x: x, y: y, width: 1, height: 1)
        var pixel = [UInt8](repeating: 0, count: 4)
        EngineRendering.standardContext.render(
            image, toBitmap: &pixel, rowBytes: 4, bounds: rect,
            format: .RGBA8, colorSpace: nil
        )
        return Double(pixel[0]) / 255.0
    }

    private let extent = CGRect(x: 0, y: 0, width: 200, height: 200)

    // MARK: - Landmark → pixel-mapping

    func testPixelPointsMapsThroughFaceBox() {
        // Face-bbox: kwart van een 800×1000-beeld, genormaliseerd bottom-left.
        let bb = CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let size = CGSize(width: 800, height: 1000)
        let mapped = TeethWhitener.pixelPoints(
            normalized: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0.5, y: 0.5)],
            boundingBox: bb, imageSize: size
        )
        XCTAssertEqual(mapped[0], CGPoint(x: 200, y: 500))
        XCTAssertEqual(mapped[1], CGPoint(x: 600, y: 750))
        XCTAssertEqual(mapped[2], CGPoint(x: 400, y: 625))
    }

    // MARK: - Polygon-oppervlakte (mond-dicht-detectie)

    func testPolygonAreaSquareAndSliver() {
        let square = [
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10),
        ]
        XCTAssertEqual(TeethWhitener.polygonArea(square), 100, accuracy: 0.001)

        // Gesloten mond: innerLips wordt een sliver — oppervlakte onder de
        // aperture-drempel voor een 160×200-face-rect.
        let sliver = [
            CGPoint(x: 0, y: 0), CGPoint(x: 60, y: 0),
            CGPoint(x: 60, y: 0.8), CGPoint(x: 0, y: 0.8),
        ]
        let faceArea: CGFloat = 160 * 200
        XCTAssertLessThan(
            TeethWhitener.polygonArea(sliver),
            TeethWhitener.minApertureAreaFraction * faceArea
        )
        XCTAssertEqual(TeethWhitener.polygonArea([CGPoint(x: 1, y: 1)]), 0)
    }

    // MARK: - Polygon-masker

    func testPolygonMaskFillsInsideAndFeathersEdge() {
        // Ruit rond (100,100), straal 50.
        let diamond = [
            CGPoint(x: 100, y: 50), CGPoint(x: 150, y: 100),
            CGPoint(x: 100, y: 150), CGPoint(x: 50, y: 100),
        ]
        let hard = TeethWhitener.polygonMask(points: diamond, extent: extent, feather: 0)
        XCTAssertGreaterThan(value(at: 100, 100, in: hard), 0.95)   // centrum
        XCTAssertLessThan(value(at: 10, 10, in: hard), 0.05)        // ver erbuiten

        let soft = TeethWhitener.polygonMask(points: diamond, extent: extent, feather: 6)
        let edge = value(at: 125, 125, in: soft)                    // op de ruitrand
        XCTAssertGreaterThan(edge, 0.1)
        XCTAssertLessThan(edge, 0.9)
        XCTAssertGreaterThan(value(at: 100, 100, in: soft), 0.9)    // centrum blijft vol
    }

    // MARK: - Emaille-poort

    func testIsEnamelClassifies() {
        let floor = 0.40
        // Ivoor en gelig emaille: door de poort.
        XCTAssertTrue(TeethWhitener.isEnamel(r: 0.85, g: 0.82, b: 0.70, luminanceFloor: floor))
        XCTAssertTrue(TeethWhitener.isEnamel(r: 0.75, g: 0.70, b: 0.45, luminanceFloor: floor))
        // Rode lip: licht genoeg voor de vloer, maar rood domineert.
        XCTAssertFalse(TeethWhitener.isEnamel(r: 0.75, g: 0.35, b: 0.40, luminanceFloor: floor))
        // Donkere mondholte: onder de luminantievloer.
        XCTAssertFalse(TeethWhitener.isEnamel(r: 0.15, g: 0.10, b: 0.10, luminanceFloor: floor))
        // Blauw-dominant: geen emaille.
        XCTAssertFalse(TeethWhitener.isEnamel(r: 0.55, g: 0.55, b: 0.80, luminanceFloor: floor))
    }

    func testEnamelGateCubeDataLayout() {
        // Cube-layout: r snelst, dan g, dan b; RGBA floats. Een pass-kleur
        // moet op zijn eigen index wit staan, een fail-kleur zwart.
        let n = 8
        let floor = 0.40
        let data = TeethWhitener.enamelGateCubeData(dimension: n, luminanceFloor: floor)
        XCTAssertEqual(data.count, n * n * n * 4 * MemoryLayout<Float>.size)

        func entry(r: Int, g: Int, b: Int) -> Float {
            let index = ((b * n + g) * n + r) * 4
            return data.withUnsafeBytes { buffer in
                buffer.bindMemory(to: Float.self)[index]
            }
        }
        // (7,7,6)/7 ≈ (1, 1, 0.857): licht ivoor → pass.
        XCTAssertEqual(entry(r: 7, g: 7, b: 6), 1)
        // (1,1,1)/7 ≈ donkergrijs → onder de vloer.
        XCTAssertEqual(entry(r: 1, g: 1, b: 1), 0)
        // (6,2,2)/7: verzadigd rood → reject.
        XCTAssertEqual(entry(r: 6, g: 2, b: 2), 0)
    }

    // MARK: - Masker-gewogen gemiddelde

    func testMaskedAverageOnSyntheticImage() {
        // Links rood, rechts wit; masker = rechterhelft → gemiddelde is
        // wit, dekking 0.5.
        let rightHalf = CGRect(x: 100, y: 0, width: 100, height: 200)
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
        let image = white.cropped(to: rightHalf)
            .applyingFilter("CISourceOverCompositing", parameters: [
                kCIInputBackgroundImageKey: red
            ])
        let mask = white.cropped(to: rightHalf)

        let result = TeethWhitener.maskedAverage(image, mask: mask, in: extent)
        XCTAssertEqual(result.coverage, 0.5, accuracy: 0.03)
        XCTAssertEqual(result.r, 1.0, accuracy: 0.05)
        XCTAssertEqual(result.g, 1.0, accuracy: 0.05)
        XCTAssertEqual(result.b, 1.0, accuracy: 0.05)

        // Leeg masker → dekking 0 (voedt de mouthNotVisible-guard).
        let empty = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        XCTAssertEqual(TeethWhitener.maskedAverage(image, mask: empty, in: extent).coverage,
                       0, accuracy: 0.01)
    }

    // MARK: - Adaptieve sterkte

    func testWhiteningParamsClamps() {
        // Extreem geel: desaturatie klemt op het maximum.
        let yellow = TeethWhitener.whiteningParams(r: 0.8, g: 0.75, b: 0.2)
        XCTAssertEqual(yellow.desaturation, TeethWhitener.desaturationRange.upperBound,
                       accuracy: 0.001)

        // Bijna-witte tanden: minimale desaturatie, gamma ≈ no-op.
        let white = TeethWhitener.whiteningParams(r: 0.95, g: 0.95, b: 0.93)
        XCTAssertEqual(white.desaturation, TeethWhitener.desaturationRange.lowerBound,
                       accuracy: 0.001)
        XCTAssertEqual(white.gammaPower, 1.0, accuracy: 0.001)

        // Donker geel: gamma klemt op het minimum (geen overlift).
        let dark = TeethWhitener.whiteningParams(r: 0.4, g: 0.35, b: 0.2)
        XCTAssertEqual(dark.gammaPower, TeethWhitener.minGammaPower, accuracy: 0.001)

        // Middenlicht (luma ≈ 0.78): gamma tussen de klemmen, macht < 1.
        let mid = TeethWhitener.whiteningParams(r: 0.80, g: 0.78, b: 0.72)
        XCTAssertGreaterThan(mid.gammaPower, TeethWhitener.minGammaPower)
        XCTAssertLessThan(mid.gammaPower, 1.0)
    }

    // MARK: - Composiet raakt alleen het masker

    func testCompositeOnlyChangesMaskedRegion() {
        let rightHalf = CGRect(x: 100, y: 0, width: 100, height: 200)
        let source = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            .cropped(to: extent)
        let whitened = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: extent)
        let mask = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: rightHalf)

        let out = TeethWhitener.composite(source: source, whitened: whitened, mask: mask)
        XCTAssertGreaterThan(value(at: 150, 100, in: out), 0.95)            // binnen masker: wit
        XCTAssertEqual(value(at: 50, 100, in: out), value(at: 50, 100, in: source),
                       accuracy: 0.02)                                       // erbuiten: bron
    }

    // MARK: - End-to-end foutpad

    func testWhitenFlatImageThrowsNoFace() async {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: 400, height: 400, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        let flat = ctx.makeImage()!

        do {
            _ = try await TeethWhitener().whiten(flat)
            XCTFail("Verwachtte noFaceFound op vlak beeld")
        } catch let failure as TeethWhitener.Failure {
            XCTAssertEqual(failure, .noFaceFound)
        } catch {
            XCTFail("Onverwachte fout: \(error)")
        }
    }
}
