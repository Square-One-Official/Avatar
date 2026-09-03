// Env-gated probe: AVATAR_CUTOUT_PROBE_IN=<bron.png> AVATAR_CUTOUT_PROBE_OUT=<uit.png>
// [AVATAR_CUTOUT_PROBE_ENGINE=ormbg]
// draait de echte VisionCutoutEngine op een bestand en schrijft de cutout weg,
// zodat een randgeval (Figma-avatar op een gekleurde schijf) visueel te
// controleren is zonder fixture in de repo. Zonder env: skip.

import ImageIO
import XCTest
@testable import AvatarKit

final class VisionCutoutProbeTests: XCTestCase {
    func testProbeCutoutToFile() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let inPath = env["AVATAR_CUTOUT_PROBE_IN"], let outPath = env["AVATAR_CUTOUT_PROBE_OUT"] else {
            throw XCTSkip("AVATAR_CUTOUT_PROBE_IN/OUT niet gezet")
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: inPath) as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let normalized = SRGBNormalizer.normalized(image)
        let cutout: CGImage
        if env["AVATAR_CUTOUT_PROBE_ENGINE"] == "ormbg" {
            let engine = OrmbgEngine()
            guard await engine.isAvailable else { throw XCTSkip("ORMBG-model niet geïnstalleerd voor dit proces") }
            cutout = try await engine.cutout(normalized)
        } else {
            cutout = try await VisionCutoutEngine().cutout(normalized)
        }
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cutout, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
}
