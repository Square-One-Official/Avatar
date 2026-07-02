import CoreGraphics
import XCTest
@testable import AvatarKit

private struct StubEngine: CutoutEngine {
    let kind: CutoutEngineKind
    let available: Bool
    /// Beschikbaar, maar gooit tijdens `cutout` (model-fout / geen subject) —
    /// om de fallback-cascade te toetsen.
    var failsCutout: Bool = false

    var isAvailable: Bool { available }

    func cutout(_ image: CGImage) async throws -> CGImage {
        guard available else { throw CutoutEngineError.unavailable(kind) }
        if failsCutout { throw CutoutEngineError.unavailable(kind) }
        return image
    }
}

final class PipelineRouterTests: XCTestCase {
    func testLegeRouterGeeftGeenEngine() async {
        let router = PipelineRouter()
        let engine = await router.engine()
        XCTAssertNil(engine)
    }

    func testVoorkeursvolgordeKiestEersteBeschikbare() async {
        let router = PipelineRouter(engines: [
            StubEngine(kind: .vision, available: false),
            StubEngine(kind: .ormbg, available: true),
        ])
        let engine = await router.engine()
        XCTAssertEqual(engine?.kind, .ormbg)
    }

    func testExplicieteVoorkeurWint() async {
        let router = PipelineRouter(engines: [
            StubEngine(kind: .vision, available: true),
            StubEngine(kind: .ormbg, available: true),
        ])
        let engine = await router.engine(preferring: .ormbg)
        XCTAssertEqual(engine?.kind, .ormbg)
    }

    func testOnbeschikbareVoorkeurValtTerug() async {
        let router = PipelineRouter(engines: [
            StubEngine(kind: .vision, available: true),
            StubEngine(kind: .ormbg, available: false),
        ])
        let engine = await router.engine(preferring: .ormbg)
        XCTAssertEqual(engine?.kind, .vision)
    }

    func testCutoutZonderEngineGooitNoEngineAvailable() async {
        let router = PipelineRouter()
        let image = Self.makePixel()
        do {
            _ = try await router.cutout(image)
            XCTFail("verwachtte CutoutEngineError.noEngineAvailable")
        } catch let error as CutoutEngineError {
            XCTAssertEqual(error, .noEngineAvailable)
        } catch {
            XCTFail("onverwachte fout: \(error)")
        }
    }

    func testCutoutValtTerugOpVolgendeEngineBijFout() async throws {
        // Voorkeur is beschikbaar maar faalt tijdens cutout → cascade naar de
        // volgende beschikbare engine (Vision-vangnet) i.p.v. de hele import af
        // te breken.
        let router = PipelineRouter(engines: [
            StubEngine(kind: .ormbg, available: true, failsCutout: true),
            StubEngine(kind: .vision, available: true),
        ])
        let result = try await router.cutout(Self.makePixel(), preferring: .ormbg)
        XCTAssertEqual(result.width, 1, "fallback-engine leverde geen beeld")
    }

    func testCutoutGooitAlsAlleBeschikbareEnginesFalen() async {
        let router = PipelineRouter(engines: [
            StubEngine(kind: .vision, available: true, failsCutout: true),
            StubEngine(kind: .ormbg, available: true, failsCutout: true),
        ])
        do {
            _ = try await router.cutout(Self.makePixel())
            XCTFail("verwachtte een fout toen álle engines faalden")
        } catch {
            // verwacht — geen enkele engine slaagde
        }
    }

    private static func makePixel() -> CGImage {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
