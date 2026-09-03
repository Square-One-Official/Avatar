// Env-gated probe: AVATAR_CUTOUT_PROBE_IN=<bron.png> AVATAR_CUTOUT_PROBE_OUT=<uit.png>
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
        let cutout = try await VisionCutoutEngine().cutout(SRGBNormalizer.normalized(image))
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cutout, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
}
