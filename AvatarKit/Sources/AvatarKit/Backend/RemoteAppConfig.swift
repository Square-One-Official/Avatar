import Foundation

/// App-brede visuele configuratie vanuit de CMS (E33+), via `GET /v1/app-config`.
/// Beide velden zijn optioneel — leeg = de hardgecodeerde placeholder in de app.
public struct RemoteAppConfig: Sendable {
    /// Achtergrond van het Onboarding Splash-scherm (was hardcoded blauwe gradient).
    public let splashBackgroundUrl: URL?
    /// Tot 6 portret-voorbeelden in de cirkels op het lege canvas
    /// (waren gekleurde `person.fill`-placeholder-cirkels).
    public let emptyStateAvatarUrls: [URL]

    public static let empty = RemoteAppConfig(splashBackgroundUrl: nil, emptyStateAvatarUrls: [])

    public init(splashBackgroundUrl: URL?, emptyStateAvatarUrls: [URL]) {
        self.splashBackgroundUrl = splashBackgroundUrl
        self.emptyStateAvatarUrls = emptyStateAvatarUrls
    }
}
