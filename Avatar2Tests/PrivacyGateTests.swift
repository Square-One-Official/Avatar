import AvatarKit
import XCTest
@testable import Avatar2

final class PrivacyGateTests: XCTestCase {

    @MainActor
    func testImagePlaygroundAllowedAtAppleCloudTierWithoutSignIn() throws {
        let prefs = PrivacyPreferences2.shared
        let previous = prefs.tier
        defer { prefs.tier = previous }

        guard AppleIntelligenceAvailability.supportsApplePrivateCloud else {
            throw XCTSkip("Image Playground not available on this Mac")
        }

        prefs.tier = .appleCloud
        let entitlement = EntitlementModel(auth: AuthService())

        let result = PrivacyGate.evaluate(.imagePlaygroundGenerate, entitlement: entitlement)
        XCTAssertEqual(result, PrivacyGateResult.allowed)
    }

    @MainActor
    func testImagePlaygroundNeedsElevationOnDeviceTier() {
        let prefs = PrivacyPreferences2.shared
        let previous = prefs.tier
        defer { prefs.tier = previous }

        prefs.tier = .onDevice
        let entitlement = EntitlementModel(auth: AuthService())

        let result = PrivacyGate.evaluate(.imagePlaygroundGenerate, entitlement: entitlement)
        XCTAssertEqual(
            result,
            PrivacyGateResult.needsElevation(requiredTier: .appleCloud, feature: .imagePlaygroundGenerate)
        )
    }
}
