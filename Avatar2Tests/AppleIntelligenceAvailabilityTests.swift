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

    @MainActor
    func testEffectiveTierFallsBackWhenAppleCloudUnavailable() {
        let prefs = PrivacyPreferences2.shared
        let previous = prefs.tier
        defer { prefs.tier = previous }

        prefs.tier = .appleCloud
        if AppleIntelligenceAvailability.supportsApplePrivateCloud {
            XCTAssertEqual(prefs.effectiveTier, .appleCloud)
        } else {
            XCTAssertEqual(prefs.effectiveTier, .onDevice)
        }
    }
}
