// Centrale privacy-gate: tier-check vóór credits/sign-in.

import Foundation

enum PrivacyGateResult: Equatable {
    case allowed
    case needsElevation(requiredTier: AIPrivacyTier, feature: AIFeature)
    case needsSignIn
    case needsCredits
}

@MainActor
enum PrivacyGate {

    static func evaluate(_ feature: AIFeature, entitlement: EntitlementModel) -> PrivacyGateResult {
        let current = PrivacyPreferences2.shared.effectiveTier
        let required = AIFeatureRegistry.requiredTier(for: feature)
        guard AIFeatureRegistry.tierSufficient(current: current, required: required) else {
            // UI only offers Cloud (thirdParty), even when the feature
            // internally needs Apple Private Cloud.
            return .needsElevation(requiredTier: .thirdParty, feature: feature)
        }
        // Apple Private Cloud features (Image Playground): tier suffices, no account/credits.
        if feature.requiredTier == .appleCloud, feature.creditCost == nil {
            return .allowed
        }
        if !entitlement.isSignedIn {
            return .needsSignIn
        }
        if entitlement.isProActive || entitlement.isDevUnlimited || entitlement.creditsRemaining > 0 {
            return .allowed
        }
        if feature.creditCost == nil {
            return .allowed
        }
        return .needsCredits
    }
}
