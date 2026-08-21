// E42 — Stijl/view-catalogus + prompt-compositie voor AI-achtergrondgeneratie.

import Foundation

enum BackgroundGenerationContext: Equatable, Sendable {
    case portrait
    case banner(width: Int, height: Int)

    var targetWidth: Int {
        switch self {
        case .portrait: PortraitExporter.exportSide
        case .banner(let width, _): max(1, width)
        }
    }

    var targetHeight: Int {
        switch self {
        case .portrait: PortraitExporter.exportSide
        case .banner(_, let height): max(1, height)
        }
    }

    var contextHint: String {
        switch self {
        case .portrait:
            return "Square · fits your portrait"
        case .banner(let width, let height):
            return "\(width) × \(height) · fits this banner"
        }
    }

    var isWide: Bool {
        Double(targetWidth) / Double(max(targetHeight, 1)) >= 2.5
    }

    var creditCost: Int { isWide ? 3 : 2 }
}

enum BackgroundGenerationModel: String, CaseIterable, Identifiable, Sendable {
    case apple
    case gemini
    case openAI

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple: "Apple"
        case .gemini: "Gemini"
        case .openAI: "OpenAI"
        }
    }

    var menuIcon: String {
        switch self {
        case .apple: "apple.logo"
        case .gemini: "sparkles"
        case .openAI: "cloud"
        }
    }

    /// Server-side MODEL_REGISTRY key (cloud only).
    var generationModelKey: String? {
        switch self {
        case .gemini: "nano-banana"
        // gpt-image-2-swap (E55-amendement): 1.5 is niet meer user-selectable —
        // de server zou 'm stil naar nano laten degraderen.
        case .openAI: "gpt-image-2"
        case .apple: nil
        }
    }

    var privacyTier: AIPrivacyTier {
        switch self {
        case .apple: .appleCloud
        case .gemini, .openAI: .thirdParty
        }
    }

    var isAppleAvailable: Bool {
        switch self {
        case .apple: AppleIntelligenceAvailability.supportsApplePrivateCloud
        default: true
        }
    }

    var isCloudAvailable: Bool {
        switch self {
        case .apple: false
        default: true
        }
    }

    @MainActor
    var isSelectable: Bool {
        switch self {
        case .apple: isAppleAvailable
        case .gemini, .openAI: isCloudAvailable && PrivacyPreferences2.shared.effectiveTier >= .thirdParty
        }
    }
}

enum BackgroundGenerationStyle: String, CaseIterable, Identifiable, Sendable {
    case photorealistic
    case illustration
    case line
    case bold
    case watercolour
    case pencil
    case animation3D = "3d"
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .photorealistic: "Photorealistic"
        case .illustration: "Illustration"
        case .line: "Line"
        case .bold: "Bold"
        // UXS-24: US-spelling op het LABEL; de case-naam blijft, die kan
        // in opgeslagen keuzes/CMS-keys zitten.
        case .watercolour: "Watercolor"
        case .pencil: "Pencil"
        case .animation3D: "3D Animation"
        case .custom: "Custom"
        }
    }

    /// Placeholder gradient tint for the style swatch (MVP — geen assets).
    var swatchColors: (top: UInt32, bottom: UInt32) {
        switch self {
        case .photorealistic: (0x4A6741, 0x87CEEB)
        case .illustration: (0xFF6B6B, 0xFFE66D)
        case .line: (0x2C3E50, 0xECF0F1)
        case .bold: (0xE74C3C, 0x3498DB)
        case .watercolour: (0xA8D8EA, 0xFCE38A)
        case .pencil: (0xBDC3C7, 0x7F8C8D)
        case .animation3D: (0x9B59B6, 0x1ABC9C)
        case .custom: (0x555555, 0x888888)
        }
    }
}

enum BackgroundGenerationView: String, CaseIterable, Identifiable, Sendable {
    case any
    case angle45 = "45_angle"
    case highAngle = "high_angle"
    case lowAngle = "low_angle"
    case overhead
    case closeUp = "close_up"
    case wide
    case front
    case side
    case back

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: "Any"
        case .angle45: "45° Angle"
        case .highAngle: "High Angle"
        case .lowAngle: "Low Angle"
        case .overhead: "Overhead"
        case .closeUp: "Close-Up"
        case .wide: "Wide"
        case .front: "Front"
        case .side: "Side"
        case .back: "Back"
        }
    }
}

enum BackgroundGenerationCatalog {

    private static let userDefaultsKey = "backgroundGeneration.model"

    @MainActor
    static func storedModel(default fallback: BackgroundGenerationModel) -> BackgroundGenerationModel {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
              let model = BackgroundGenerationModel(rawValue: raw) else { return fallback }
        return model
    }

    static func storeModel(_ model: BackgroundGenerationModel) {
        UserDefaults.standard.set(model.rawValue, forKey: userDefaultsKey)
    }

    @MainActor
    static func defaultModel() -> BackgroundGenerationModel {
        if PrivacyPreferences2.shared.effectiveTier >= .thirdParty {
            return storedModel(default: .gemini)
        }
        if AppleIntelligenceAvailability.supportsApplePrivateCloud {
            return .apple
        }
        return .gemini
    }

    @MainActor
    static func availableModels() -> [BackgroundGenerationModel] {
        BackgroundGenerationModel.allCases.filter(\.isSelectable)
    }

    @MainActor
    static var hasGenerationPath: Bool {
        !availableModels().isEmpty
    }

    static func canGenerate(
        prompt: String,
        style: BackgroundGenerationStyle,
        customStyleText: String
    ) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if style == .custom {
            return !customStyleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    static func sanitizedPrompt(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sanitizedCustomStyle(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }
}
