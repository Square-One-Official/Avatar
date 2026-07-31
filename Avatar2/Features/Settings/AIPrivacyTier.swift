// Drie privacy-tiers voor AI-bewerkingen (Privacy Tier Picker). Vervangt de
// binaire localOnly/cloudAllowed-modus; legacy rawValues blijven leesbaar bij migratie.

import AvatarUI
import Foundation

enum AIPrivacyTier: Int, CaseIterable, Codable, Sendable, Comparable {
    case onDevice = 1
    case appleCloud = 2
    case thirdParty = 3

    static func < (lhs: AIPrivacyTier, rhs: AIPrivacyTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

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

    var title: String {
        switch self {
        case .onDevice: return "On-device"
        case .appleCloud: return "Apple Private Cloud"
        case .thirdParty: return "Advanced"
        }
    }

    var description: String {
        switch self {
        case .onDevice:
            return "Your photos stay on your Mac. Edit, retouch and export. Fully offline."
        case .appleCloud:
            return "More creative AI through Apple, with Apple's privacy promise. Not used for training."
        case .thirdParty:
            return "The strongest results: sharper edges, styles and face edits. Processed securely, never used for training."
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
