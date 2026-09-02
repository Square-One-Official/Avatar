// Privacy-tiers voor AI-bewerkingen. Intern blijven drie waarden bestaan
// (Image Playground vereist nog `appleCloud`); de UI toont alleen Local only
// en Cloud (besluit Thierry 2026-09-02 — Figma toont nog drie rijen).

import AvatarUI
import Foundation

enum AIPrivacyTier: Int, CaseIterable, Codable, Sendable, Comparable {
    case onDevice = 1
    case appleCloud = 2
    case thirdParty = 3

    static func < (lhs: AIPrivacyTier, rhs: AIPrivacyTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Settings + onboarding: twee keuzes. `appleCloud` migreert naar Cloud.
    static var userFacingChoices: [AIPrivacyTier] { [.onDevice, .thirdParty] }

    var storageKey: String {
        switch self {
        case .onDevice: return "onDevice"
        case .appleCloud: return "appleCloud"
        case .thirdParty: return "thirdParty"
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "onDevice", "localOnly": self = .onDevice
        case "appleCloud": self = .appleCloud
        case "thirdParty", "cloudAllowed": self = .thirdParty
        default: return nil
        }
    }

    /// Opgeslagen Apple-Private-Cloud-keuze telt als Cloud.
    var userFacing: AIPrivacyTier {
        self == .onDevice ? .onDevice : .thirdParty
    }

    var title: String {
        switch self {
        case .onDevice: return "Local only"
        case .appleCloud, .thirdParty: return "Cloud"
        }
    }

    var description: String {
        switch self {
        case .onDevice:
            return "Photos stay on this Mac. Edit, retouch and export. Cloud features stay off until you turn them on."
        case .appleCloud, .thirdParty:
            return "The strongest AI results. Processed securely, never used for training. We pick the best model for each edit."
        }
    }

    var icon: DSIcon.Symbol {
        switch self {
        case .onDevice: return .privacyOnDevice
        case .appleCloud: return .privacyAppleCloud
        case .thirdParty: return .privacyAdvanced
        }
    }

    /// Legacy v1-modus voor gedeelde UserDefaults-key `aiPrivacyMode`.
    var legacyMode: AIPrivacyMode2 {
        self == .onDevice ? .localOnly : .cloudAllowed
    }
}
