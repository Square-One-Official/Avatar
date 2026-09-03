import Foundation

/// Gradient-preset uit de CMS AppConfig global (E33+).
/// fromHex/toHex zijn `#RRGGBB`-strings; `BackgroundKit.Color(hexRGB:)` parseert ze.
public struct RemoteGradientPreset: Decodable, Sendable {
    public let label: String
    public let fromHex: String
    public let toHex: String

    private enum CodingKeys: String, CodingKey {
        case label
        case fromHex = "from_hex"
        case toHex = "to_hex"
    }
}

/// App-brede visuele configuratie vanuit de CMS (E33+), via `GET /v1/app-config`.
/// Alle velden zijn optioneel / default-leeg — de app valt dan terug op
/// hardgecodeerde placeholders.
public struct RemoteAppConfig: Sendable {
    /// Achtergrond van het Onboarding Splash-scherm (was hardcoded blauwe gradient).
    public let splashBackgroundUrl: URL?
    /// Tot 6 portret-voorbeelden in de cirkels op het lege canvas
    /// (waren gekleurde `person.fill`-placeholder-cirkels).
    public let emptyStateAvatarUrls: [URL]
    /// CMS-gestuurde extra gradient-presets voor het Background-paneel.
    /// Leeg = app toont alleen de 10 lokale mesh-presets.
    public let gradientPresets: [RemoteGradientPreset]
    /// Bullets in de Pro-kaart op het Paywall-scherm.
    /// Leeg = app toont de Engelse hardgecodeerde teksten als fallback.
    public let paywallProFeatures: [String]

    public static let empty = RemoteAppConfig(
        splashBackgroundUrl: nil,
        emptyStateAvatarUrls: [],
        gradientPresets: [],
        paywallProFeatures: []
    )

    public init(
        splashBackgroundUrl: URL?,
        emptyStateAvatarUrls: [URL],
        gradientPresets: [RemoteGradientPreset],
        paywallProFeatures: [String]
    ) {
        self.splashBackgroundUrl = splashBackgroundUrl
        self.emptyStateAvatarUrls = emptyStateAvatarUrls
        self.gradientPresets = gradientPresets
        self.paywallProFeatures = paywallProFeatures
    }
}

/// Decodable wrapper voor de `/v1/app-config` JSON-response.
struct RemoteAppConfigResponse: Decodable {
    let splashBackgroundUrl: URL?
    let emptyStateAvatarUrls: [URL]
    let gradientPresets: [RemoteGradientPreset]
    let paywallProFeatures: [String]

    private enum CodingKeys: String, CodingKey {
        case splashBackgroundUrl = "splash_background_url"
        case emptyStateAvatarUrls = "empty_state_avatar_urls"
        case gradientPresets = "gradient_presets"
        case paywallProFeatures = "paywall_pro_features"
    }
}
