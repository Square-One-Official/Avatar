import Foundation

/// Remote feature flags opgehaald via `GET /v1/feature-flags` (E33+).
/// Alle flags default naar `true` (allEnabled) zodat de app nooit kapot gaat
/// als de CMS onbereikbaar is.
public struct RemoteFeatureFlags: Decodable, Sendable {
    public let effectsEnabled: Bool
    public let hairEnabled: Bool
    public let clothesEnabled: Bool
    public let faceEnabled: Bool
    public let backgroundsEnabled: Bool

    public static let allEnabled = RemoteFeatureFlags(
        effectsEnabled: true,
        hairEnabled: true,
        clothesEnabled: true,
        faceEnabled: true,
        backgroundsEnabled: true
    )

    public init(
        effectsEnabled: Bool,
        hairEnabled: Bool,
        clothesEnabled: Bool,
        faceEnabled: Bool,
        backgroundsEnabled: Bool
    ) {
        self.effectsEnabled = effectsEnabled
        self.hairEnabled = hairEnabled
        self.clothesEnabled = clothesEnabled
        self.faceEnabled = faceEnabled
        self.backgroundsEnabled = backgroundsEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case effectsEnabled = "effects_enabled"
        case hairEnabled = "hair_enabled"
        case clothesEnabled = "clothes_enabled"
        case faceEnabled = "face_enabled"
        case backgroundsEnabled = "backgrounds_enabled"
    }
}
