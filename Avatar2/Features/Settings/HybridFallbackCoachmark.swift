// Eenmalige hint onder hybrid chips na eerste on-device fallback (plan §6D).

import Foundation

enum HybridFallbackCoachmark {
    private static let dismissedKey = "privacy.hybridFallbackCoachmarkDismissed"

    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: dismissedKey)
    }

    static func markShown() {
        UserDefaults.standard.set(true, forKey: dismissedKey)
    }

    static let message =
        "Processed on your Mac. Cloud unlocks sharper edges."
}
