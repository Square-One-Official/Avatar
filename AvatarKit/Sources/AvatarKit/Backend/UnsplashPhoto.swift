// Unsplash-foto zoals /v1/unsplash die teruggeeft (UX-audit background-
// paneel, 2026-07-03). De backend proxied de Unsplash API (key server-side)
// en levert per foto een thumbnail (paneel-tegel), een resize-URL op
// exportkwaliteit, attributie en de download-registratie-URL.

import Foundation

public struct UnsplashPhoto: Identifiable, Equatable, Sendable, Decodable {
    public let id: String
    public let thumbUrl: URL
    public let fullUrl: URL
    public let authorName: String?
    public let authorUrl: URL?
    /// Unsplash-guideline: bij daadwerkelijk gebruik deze URL (server-side)
    /// aanroepen zodat de download geregistreerd wordt — zie
    /// `BackendClient.unsplashTrackDownload`.
    public let downloadLocation: String?

    public init(
        id: String, thumbUrl: URL, fullUrl: URL,
        authorName: String?, authorUrl: URL?, downloadLocation: String?
    ) {
        self.id = id
        self.thumbUrl = thumbUrl
        self.fullUrl = fullUrl
        self.authorName = authorName
        self.authorUrl = authorUrl
        self.downloadLocation = downloadLocation
    }
}

/// Envelope van POST /v1/unsplash. `enabled == false` = geen
/// `UNSPLASH_ACCESS_KEY` op de backend — de app toont dan een nette melding
/// i.p.v. een lege grid.
public struct UnsplashFeed: Equatable, Sendable, Decodable {
    public let enabled: Bool
    public let photos: [UnsplashPhoto]

    public init(enabled: Bool, photos: [UnsplashPhoto]) {
        self.enabled = enabled
        self.photos = photos
    }
}
