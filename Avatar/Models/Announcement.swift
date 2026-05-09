import Foundation

/// One feature-announcement document fetched from the backend. Authored
/// in the Payload CMS at admin.aaavatar.nl; the macOS app receives a
/// flattened, pre-rendered shape (Markdown body, resolved image URL).
///
/// `slug` is the stable identifier used to mark the announcement seen on
/// the server — it must remain stable over the lifetime of an announcement
/// or users will be re-shown content they already dismissed. To "re-show"
/// a campaign, publish a new document with a new slug.
struct Announcement: Decodable, Identifiable, Equatable {
    let slug: String
    let title: String
    /// Markdown. Render with `AttributedString(markdown:)` so links and
    /// emphasis flow inline without each call site re-parsing.
    let body: String
    let imageUrl: URL?
    let cta: CTA?

    var id: String { slug }

    struct CTA: Decodable, Equatable {
        let label: String
        let url: URL
    }

    /// Custom decoder so the `image_url` snake-case from the backend
    /// becomes `URL?`, and a missing or empty `cta` payload decodes to
    /// `nil` instead of throwing.
    enum CodingKeys: String, CodingKey {
        case slug, title, body, cta
        case imageUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        if let raw = try c.decodeIfPresent(String.self, forKey: .imageUrl),
           !raw.isEmpty {
            imageUrl = URL(string: raw)
        } else {
            imageUrl = nil
        }
        cta = try c.decodeIfPresent(CTA.self, forKey: .cta)
    }
}

/// Active "NEW" badge keyed on a stable component identifier. Component
/// IDs are coordinated with Payload's `badge-component-registry` — see
/// `BadgeComponent` in `AnnouncementService` for the canonical list.
struct AnnouncementBadge: Decodable, Equatable {
    let componentId: String
    let expiresAt: Date
}
