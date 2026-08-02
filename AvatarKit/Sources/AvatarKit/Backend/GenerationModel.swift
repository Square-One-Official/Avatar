import Foundation

/// Gebruikersgerichte generatie-modelkeuze (E15.6; default geflipt in E55.2).
/// De generatieve cloud-acties (Effects-stijl, kleding, haar) draaien
/// standaard op het OpenAI-beeldmodel (besluit Thierry 2026-08-02, E55 — beste
/// stijlmatch, zeker met stijlreferenties); deze keuze laat de gebruiker
/// terugschakelen naar nano-banana. De `rawValue` is exact de server-side key
/// uit MODEL_REGISTRY.stylize (USER_SELECTABLE_MODELS). I.t.t.
/// DevModelOverrides is dit géén dev-tool: elke gebruiker mag uit deze twee
/// kiezen.
public enum GenerationModel: String, CaseIterable, Sendable, Identifiable {
    case openAI = "gpt-image-1.5"
    case nanoBanana = "nano-banana"

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
        case .openAI: "Default — best style match"
        case .nanoBanana: "Faster — strongest identity lock"
        }
    }
}

/// Persistente voorkeur (UserDefaults), geschreven door de Settings-rij.
///
/// E55.2-semantiek: BackendClient stuurt `generation_model` alléén mee bij een
/// expliciete keuze (`explicit != nil`). Zonder keuze bepaalt de sérver de
/// default — zo is een vloot-rollback één env-wijziging (`STYLIZE_DEFAULT_MODEL`)
/// + redeploy, zonder app-update. `current` is de weergave-waarde voor
/// Settings en toont de code-default (.openAI) zolang er geen keuze is.
@MainActor
public final class GenerationModelStore {
    public static let shared = GenerationModelStore()

    private let defaults: UserDefaults
    private static let key = "generation.model"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// De expliciete gebruikerskeuze, of nil wanneer die er (nog) niet is.
    /// Alleen dit gaat als `generation_model` de deur uit — wie ooit koos,
    /// houdt zijn keuze; wie nooit koos, volgt de server-default.
    public var explicit: GenerationModel? {
        guard let raw = defaults.string(forKey: Self.key) else { return nil }
        return GenerationModel(rawValue: raw)
    }

    public var current: GenerationModel {
        get { explicit ?? .openAI }
        set { defaults.set(newValue.rawValue, forKey: Self.key) }
    }
}
