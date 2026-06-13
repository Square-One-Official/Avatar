import Foundation

/// Gebruikersgerichte generatie-modelkeuze (E15.6). De generatieve cloud-
/// acties (Effects-stijl, kleding, haar) draaien standaard op nano-banana;
/// deze keuze laat de gebruiker schakelen naar het OpenAI-beeldmodel. De
/// `rawValue` is exact de server-side key uit MODEL_REGISTRY.stylize
/// (USER_SELECTABLE_MODELS). I.t.t. DevModelOverrides is dit géén dev-tool:
/// elke gebruiker mag uit deze twee kiezen.
public enum GenerationModel: String, CaseIterable, Sendable, Identifiable {
    case nanoBanana = "nano-banana"
    case openAI = "gpt-image-1.5"

    public var id: String { rawValue }

    /// Gebruikersgerichte naam in de Settings-rij.
    public var label: String {
        switch self {
        case .nanoBanana: "Nano Banana"
        case .openAI: "OpenAI"
        }
    }

    /// Korte toelichting onder de optie.
    public var detail: String {
        switch self {
        case .nanoBanana: "Default — best identity preservation"
        case .openAI: "Stronger stylization, slower"
        }
    }
}

/// Persistente voorkeur (UserDefaults), gelezen door BackendClient.stylize
/// en geschreven door de Settings-rij. Default = nano-banana, zodat het
/// gedrag ongewijzigd blijft tot een gebruiker bewust schakelt.
@MainActor
public final class GenerationModelStore {
    public static let shared = GenerationModelStore()

    private let defaults: UserDefaults
    private static let key = "generation.model"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var current: GenerationModel {
        get {
            guard let raw = defaults.string(forKey: Self.key),
                  let model = GenerationModel(rawValue: raw) else { return .nanoBanana }
            return model
        }
        set { defaults.set(newValue.rawValue, forKey: Self.key) }
    }
}
