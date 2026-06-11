import CoreGraphics
import XCTest
@testable import AvatarKit

private struct StubEngine: CutoutEngine {
    let kind: CutoutEngineKind
    let available: Bool

    var isAvailable: Bool { available }

    func cutout(_ image: CGImage) async throws -> CGImage {
        guard available else { throw CutoutEngineError.unavailable(kind) }
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
            StubEngine(kind: .replicate, available: true),
        ])
        let engine = await router.engine()
        XCTAssertEqual(engine?.kind, .ormbg)
    }

    func testExplicieteVoorkeurWint() async {
        let router = PipelineRouter(engines: [
            StubEngine(kind: .vision, available: true),
            StubEngine(kind: .replicate, available: true),
        ])
        let engine = await router.engine(preferring: .replicate)
        XCTAssertEqual(engine?.kind, .replicate)
    }

    func testOnbeschikbareVoorkeurValtTerug() async {
        let router = PipelineRouter(engines: [
            StubEngine(kind: .vision, available: true),
            StubEngine(kind: .replicate, available: false),
        ])
        let engine = await router.engine(preferring: .replicate)
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

    private static func makePixel() -> CGImage {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
