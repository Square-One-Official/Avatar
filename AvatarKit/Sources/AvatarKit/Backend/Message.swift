import Foundation

/// Eén getarget bericht uit `/v1/messages` (E17). Geauthord in de Payload-CMS
/// (`messages`-collectie), door de backend afgevlakt tot deze shape (Markdown
/// body, resolved image-URL). Opvolger van `Announcement` voor het verenigde
/// Message-model; targeting/schedule worden server-side toegepast, de client
/// krijgt alleen wat van toepassing is.
///
/// `slug` is de stabiele identifier voor dismiss-state (gedeelde
/// announcement_seen-tabel) — stabiel houden; nieuwe slug = opnieuw tonen.
public struct Message: Decodable, Identifiable, Equatable, Sendable {
    public let slug: String
    public let title: String
    /// Markdown — render met `AttributedString(markdown:)`.
    public let body: String
    public let imageUrl: URL?
    public let cta: CTA?
    /// Schedule-frequency uit de CMS (once / everySignInUntilDismissed /
    /// untilDate / delayedNthSignIn). Onbekend → "once".
    public let frequency: String

    public var id: String { slug }

    public struct CTA: Decodable, Equatable, Sendable {
        public let label: String
        public let url: URL
        public init(label: String, url: URL) {
            self.label = label
            self.url = url
        }
    }

    public init(slug: String, title: String, body: String = "", imageUrl: URL? = nil,
                cta: CTA? = nil, frequency: String = "once") {
        self.slug = slug
        self.title = title
        self.body = body
        self.imageUrl = imageUrl
        self.cta = cta
        self.frequency = frequency
    }

    enum CodingKeys: String, CodingKey {
        case slug, title, body, cta, frequency
        case imageUrl
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        if let raw = try c.decodeIfPresent(String.self, forKey: .imageUrl), !raw.isEmpty {
            imageUrl = URL(string: raw)
        } else {
            imageUrl = nil
        }
        cta = try c.decodeIfPresent(CTA.self, forKey: .cta)
        frequency = try c.decodeIfPresent(String.self, forKey: .frequency) ?? "once"
    }
}
