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

    // GEEN expliciete snake_case-CodingKeys hier: BackendClient decodeert al
    // met `.convertFromSnakeCase`, dus `effects_enabled` → `effectsEnabled`
    // gebeurt door de decoder. De vorige expliciete keys ("effects_enabled")
    // werden dáárna nooit meer gematcht — dubbele mapping — waardoor élke
    // /v1/feature-flags-decode faalde en de app stil op de allEnabled-
    // fallback bleef hangen (CMS-flags deden dus niets). Gevonden door
    // EntitlementModelTests.testFeatureFlagsFetchAppliesRemoteValues (E47.2).
}
