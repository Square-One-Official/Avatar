// Centrale registry: welke AI-feature welke privacy-tier vereist + UI-copy.

import Foundation

enum AIFeature: String, CaseIterable, Sendable, Equatable {
    case boostOnline
    case colorise
    case restoreBody
    case effectGenerate
    case effectRegenerate
    case hairEdit
    case clothesEdit
    case faceEdit
    case imagePlaygroundGenerate
    case imagePlaygroundEdit
    case backgroundGenerate

    var uiLabel: String {
        switch self {
        case .boostOnline: return "Boost resolution"
        case .colorise: return "Colorise"
        case .restoreBody: return "Fill in body"
        case .effectGenerate, .effectRegenerate: return "Apply style"
        case .hairEdit: return "Hair edit"
        case .clothesEdit: return "Clothing edit"
        case .faceEdit: return "Face edit"
        case .imagePlaygroundGenerate: return "Generate image"
        case .imagePlaygroundEdit: return "Edit with Apple Intelligence"
        case .backgroundGenerate: return "Generate background"
        }
    }

    var requiredTier: AIPrivacyTier {
        switch self {
        case .imagePlaygroundGenerate, .imagePlaygroundEdit:
            return .appleCloud
        default:
            return .thirdParty
        }
    }

    /// Fallback tier when a hybrid feature runs locally (nil = cloud-only).
    var fallbackTier: AIPrivacyTier? {
        switch self {
        case .boostOnline:
            return .onDevice
        default:
            return nil
        }
    }

    var creditCost: Int? {
        switch self {
        case .boostOnline, .colorise: return 1
        case .restoreBody: return 2
        case .effectGenerate, .effectRegenerate, .hairEdit, .clothesEdit, .faceEdit: return 4
        case .imagePlaygroundGenerate, .imagePlaygroundEdit: return nil
        case .backgroundGenerate: return 2
        }
    }

    var elevationBody: String {
        switch self {
        case .boostOnline:
            return "For the best upscaling quality, your photo is processed securely online. We never use your images for training."
        case .colorise:
            return "To add color to your photo, it is processed securely online. We never use your images for training."
        case .restoreBody:
            return "To restore missing areas in your photo, it is processed securely online. We never use your images for training."
        case .effectGenerate, .effectRegenerate:
            return "To apply this style, your photo is processed securely online. We never use your images for training."
        case .hairEdit:
            return "To edit hair, your photo is processed securely online. We never use your images for training."
        case .clothesEdit:
            return "To edit clothing, your photo is processed securely online. We never use your images for training."
        case .faceEdit:
            return "To edit your face, your photo is processed securely online. We never use your images for training."
        case .imagePlaygroundGenerate:
            return "To generate this image, it is processed securely. We never use your images for training."
        case .imagePlaygroundEdit:
            return "To edit this photo, it is processed securely. We never use your images for training."
        case .backgroundGenerate:
            return "To generate a background from your description, it is processed securely online. We never use your images for training."
        }
    }
}

enum AIFeatureRegistry {
    static func requiredTier(for feature: AIFeature) -> AIPrivacyTier {
        feature.requiredTier
    }

    static func tierSufficient(current: AIPrivacyTier, required: AIPrivacyTier) -> Bool {
        current >= required
    }
}
