import CoreGraphics
import XCTest
@testable import AvatarKit

/// Fixture-foto's zijn privé en zitten bewust niet in git (zie
/// Avatar/Debug/Fixtures/README.md), dus deze tests draaien op
/// deterministisch gegenereerde synthetische fixtures: een
/// hoofd+schouders-silhouet dat Vision aantoonbaar als voorgrond-instantie
/// herkent, en een vlak beeld voor het no-subject-pad.
final class VisionCutoutEngineTests: XCTestCase {

    // MARK: - Synthetische fixtures

    /// Donker hoofd+schouders-silhouet op een licht verlopende achtergrond.
    private func portraitFixture(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let w = CGFloat(width), h = CGFloat(height)
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [CGColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1),
                     CGColor(red: 0.80, green: 0.82, blue: 0.86, alpha: 1)] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        ctx.setFillColor(CGColor(red: 0.18, green: 0.12, blue: 0.10, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: w * 0.15, y: -h * 0.25, width: w * 0.7, height: h * 0.55))
        ctx.fillEllipse(in: CGRect(x: w * 0.32, y: h * 0.30, width: w * 0.36, height: h * 0.42))
        return ctx.makeImage()!
    }

    private func flatFixture(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// Alpha (0–255) op pixel (x, y), met y vanaf de bovenrand.
    private func alpha(at x: Int, _ y: Int, in image: CGImage) -> UInt8 {
        let data = image.dataProvider!.data! as Data
        let bytesPerPixel = image.bitsPerPixel / 8
        let offset = y * image.bytesPerRow + x * bytesPerPixel
        // RGBA8 — alpha is de vierde component.
        return data[offset + 3]
    }

    // MARK: - Cutout op fixture

    func testCutoutKeepsSubjectAndClearsBackground() async throws {
        let fixture = portraitFixture(width: 800, height: 1000)
        let engine = VisionCutoutEngine()
        let cutout = try await engine.cutout(fixture)

        XCTAssertEqual(cutout.width, 800)
        XCTAssertEqual(cutout.height, 1000)

        // Midden van het hoofd: opaak.
        XCTAssertGreaterThan(alpha(at: 400, 500, in: cutout), 230)
        // Midden van de schouders (onderrand): opaak.
        XCTAssertGreaterThan(alpha(at: 400, 980, in: cutout), 230)
        // Hoeken bovenin: achtergrond, transparant.
        XCTAssertLessThan(alpha(at: 10, 10, in: cutout), 25)
        XCTAssertLessThan(alpha(at: 789, 10, in: cutout), 25)
    }

    /// Kleine input (<1500 px) gaat door het adaptieve-upscale-pad; de
    /// output moet desondanks de originele afmetingen houden.
    func testCutoutOnSmallInputKeepsOriginalSize() async throws {
        let fixture = portraitFixture(width: 600, height: 750)
        let engine = VisionCutoutEngine()
        let cutout = try await engine.cutout(fixture)

        XCTAssertEqual(cutout.width, 600)
        XCTAssertEqual(cutout.height, 750)
        XCTAssertGreaterThan(alpha(at: 300, 375, in: cutout), 230)
        XCTAssertLessThan(alpha(at: 8, 8, in: cutout), 25)
    }

    func testFlatImageThrowsNoSubjectFound() async {
        let engine = VisionCutoutEngine()
        do {
            _ = try await engine.cutout(flatFixture(width: 400, height: 400))
            XCTFail("Verwachtte noSubjectFound op vlak beeld")
        } catch let failure as VisionCutoutEngine.Failure {
            XCTAssertEqual(failure, .noSubjectFound)
        } catch {
            XCTFail("Onverwachte fout: \(error)")
        }
    }

    // MARK: - Adaptieve-inputpolicy (pure functie)

    func testVisionTargetLongEdgePolicy() {
        XCTAssertEqual(VisionCutoutEngine.visionTargetLongEdge(for: 800), 2048)
        XCTAssertEqual(VisionCutoutEngine.visionTargetLongEdge(for: 1499), 2048)
        XCTAssertEqual(VisionCutoutEngine.visionTargetLongEdge(for: 1500), 1500)
        XCTAssertEqual(VisionCutoutEngine.visionTargetLongEdge(for: 4096), 4096)
        XCTAssertEqual(VisionCutoutEngine.visionTargetLongEdge(for: 6048), 4096)
    }

    // MARK: - Router-integratie

    func testRouterPicksVisionEngine() async throws {
        let router = PipelineRouter(engines: [VisionCutoutEngine()])
        let engine = await router.engine(preferring: .vision)
        XCTAssertEqual(engine?.kind, .vision)
    }
}
