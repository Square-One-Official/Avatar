// Identity-fidelity regression hooks for Hair/Face stylize at varying input
// resolutions. Cloud calls are not run in unit tests — use the E09.1 bakeoff
// harness (`plan/e09-1-bakeoff.md`) for manual identity checks after resolution
// policy changes. These tests guard the structural preconditions.

import AppKit
import XCTest
@testable import Avatar2

final class StylizeIdentityRegressionTests: XCTestCase {

    /// Input sizes that must remain identity-safe after the quality rev2 pipeline.
    /// Re-run hair/face presets against this matrix on preview before release.
    private let identityMatrix: [(width: Int, height: Int)] = [
        (512, 768),
        (800, 1200),
        (1024, 1536),
        (1536, 2048),
    ]

    func testIdentityMatrixPixelSizesAreValid() {
        for size in identityMatrix {
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
            XCTAssertLessThanOrEqual(max(size.width, size.height), 2048)
        }
    }

    func testEditStylizeSourceUsesCutoutUnmodified() {
        let cutout = NSImage(size: NSSize(width: 1024, height: 1536))
        let source = StylizeQuality.editStylizeSource(cutout: cutout)
        XCTAssertEqual(source.size.width, 1024, accuracy: 0.5)
    }

    /// Documented manual step: for each size in `identityMatrix`, run
    /// `editHair(preset: "short")` and `editFace(preset: "reduce-wrinkles")`
    /// on the same portrait; verify identity in the bakeoff sheet.
    func testManualIdentityBakeoffReminder() {
        XCTAssertEqual(identityMatrix.count, 4)
    }
}
