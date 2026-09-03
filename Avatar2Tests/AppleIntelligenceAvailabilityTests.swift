import XCTest
@testable import Avatar2

final class AppleIntelligenceAvailabilityTests: XCTestCase {

    func testMacOSVersionComparison() {
        XCTAssertTrue(AppleIntelligenceAvailability.isMacOSAtLeast(major: 14, minor: 0))
        XCTAssertTrue(AppleIntelligenceAvailability.isMacOSAtLeast(major: 14, minor: 6))
        XCTAssertFalse(AppleIntelligenceAvailability.isMacOSAtLeast(major: 99, minor: 0))
    }

    func testStatusFootnotesAreNonEmptyWhenUnsupported() {
        let unsupported: [AppleIntelligenceSupportStatus] = [
            .unsupportedMacOS(requiredVersion: "15.1"),
            .unsupportedHardware,
            .appleIntelligenceUnavailable,
        ]
        for status in unsupported {
            XCTAssertFalse(status.footnote.isEmpty)
        }
        XCTAssertTrue(AppleIntelligenceSupportStatus.supported.footnote.isEmpty)
        XCTAssertTrue(AppleIntelligenceSupportStatus.appleIntelligenceUnavailable.offersSystemSettingsShortcut)
    }

    /// Bug-fix 2026-09-03: de refresh bij app-activatie mag de view-tree niet
    /// her-identificeren; de status leeft in een observable store die na
    /// `refresh()` de live evaluatie spiegelt.
    func testRefreshMirrorsLiveEvaluation() {
        AppleIntelligenceAvailability.refresh()
        XCTAssertEqual(AppleIntelligenceAvailability.status, AppleIntelligenceAvailability.evaluateSupport())
        XCTAssertEqual(
            AppleIntelligenceAvailability.supportsApplePrivateCloud,
            AppleIntelligenceAvailability.evaluateSupport() == .supported
        )
    }
}
