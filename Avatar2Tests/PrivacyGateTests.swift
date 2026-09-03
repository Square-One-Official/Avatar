import AvatarKit
import XCTest
@testable import Avatar2

final class PrivacyGateTests: XCTestCase {

    @MainActor
    func testImagePlaygroundAllowedAtCloudTierWithoutSignIn() {
        let prefs = PrivacyPreferences2.shared
        let previous = prefs.tier
        defer { prefs.tier = previous }

        prefs.tier = .thirdParty
        let entitlement = EntitlementModel(auth: AuthService.isolated())

        let result = PrivacyGate.evaluate(.imagePlaygroundGenerate, entitlement: entitlement)
        XCTAssertEqual(result, PrivacyGateResult.allowed)
    }

    @MainActor
    func testImagePlaygroundNeedsCloudElevationOnLocalTier() {
        let prefs = PrivacyPreferences2.shared
        let previous = prefs.tier
        defer { prefs.tier = previous }

        prefs.tier = .onDevice
        let entitlement = EntitlementModel(auth: AuthService.isolated())

        let result = PrivacyGate.evaluate(.imagePlaygroundGenerate, entitlement: entitlement)
        XCTAssertEqual(
            result,
            PrivacyGateResult.needsElevation(requiredTier: .thirdParty, feature: .imagePlaygroundGenerate)
        )
    }

    @MainActor
    func testEnableCloudFromElevationSetsCloudAndRetries() {
        let prefs = PrivacyPreferences2.shared
        let previous = prefs.tier
        defer { prefs.tier = previous }

        prefs.tier = .onDevice
        let entitlement = EntitlementModel(auth: AuthService.isolated())
        var retried = false
        XCTAssertFalse(entitlement.allowAIFeature(.colorise, retry: { retried = true }))
        XCTAssertNotNil(entitlement.privacyElevation)

        entitlement.enableCloudFromElevation()

        XCTAssertEqual(prefs.tier, .thirdParty)
        XCTAssertNil(entitlement.privacyElevation)
        XCTAssertTrue(retried)
    }
}

final class PrivacyTierChoiceTests: XCTestCase {

    func testUserFacingChoicesAreLocalAndCloud() {
        XCTAssertEqual(AIPrivacyTier.userFacingChoices, [.onDevice, .thirdParty])
        XCTAssertEqual(AIPrivacyTier.onDevice.title, "Local only")
        XCTAssertEqual(AIPrivacyTier.thirdParty.title, "Cloud")
        XCTAssertEqual(AIPrivacyTier.appleCloud.userFacing, .thirdParty)
    }

    @MainActor
    func testStoredAppleCloudMigratesToCloud() {
        let prefs = PrivacyPreferences2.shared
        let previous = prefs.tier
        defer { prefs.tier = previous }

        prefs.tier = .appleCloud
        XCTAssertEqual(prefs.tier, .thirdParty)
        XCTAssertEqual(prefs.effectiveTier, .thirdParty)
        XCTAssertTrue(prefs.allowsThirdPartyCloud)
        XCTAssertTrue(prefs.allowsAppleCloud)
    }
}
