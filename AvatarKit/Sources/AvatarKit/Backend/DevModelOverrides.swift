import Foundation

/// Dev-only model-override (E15.5). Spiegelt de backend-MODEL_REGISTRY
/// whitelist per cloud-feature en bewaart de keuze van een dev-account
/// (UserDefaults). BackendClient leest dit per call en stuurt
/// `model_override` mee; de backend honoreert het alleen voor
/// dev-allowlisted gebruikers (E01.10), dus voor reguliere gebruikers is
/// het een no-op. Niet de bron van waarheid voor aftrek — puur model-keuze.
public enum DevModelFeature: String, CaseIterable, Sendable {
    case cutout
    case colorize
    case fillBody = "fill_body"
    case stylize
    case generateBackground = "generate_background"

    public var label: String {
        switch self {
        case .cutout: return "Cut out"
        case .colorize: return "Colorize"
        case .fillBody: return "Fill in body"
        case .stylize: return "Generative (style/clothes/hair)"
        case .generateBackground: return "Generate background"
        }
    }

    /// Whitelist-spiegel van MODEL_REGISTRY (lib/models.ts). "" = default.
    /// Bij wijziging van de registry hier bijwerken (gedocumenteerde spiegel).
    public var modelKeys: [String] {
        switch self {
        case .cutout: return ["birefnet"]
        case .colorize: return ["deoldify"]
        case .fillBody: return ["flux-fill-pro"]
        case .stylize: return ["nano-banana", "flux-2-pro", "gpt-image-2", "gpt-image-1.5"]
        case .generateBackground: return ["nano-banana", "gpt-image-2", "gpt-image-1.5"]
        }
    }
}

@MainActor
public final class DevModelOverrides {
    public static let shared = DevModelOverrides()

    private let defaults: UserDefaults
    private static func key(_ f: DevModelFeature) -> String { "dev.modelOverride.\(f.rawValue)" }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Gekozen model-key voor een feature, of nil (= default model).
    public func override(for feature: DevModelFeature) -> String? {
        let v = defaults.string(forKey: Self.key(feature))
        return (v?.isEmpty == false) ? v : nil
    }

    public func setOverride(_ key: String?, for feature: DevModelFeature) {
        if let key, !key.isEmpty {
            defaults.set(key, forKey: Self.key(feature))
        } else {
            defaults.removeObject(forKey: Self.key(feature))
        }
    }
}
