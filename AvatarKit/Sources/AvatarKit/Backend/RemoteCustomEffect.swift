import Foundation

/// One user-created custom Effect (E34). Unlike `RemoteEffect` (the CMS-curated
/// styles keyed by a server-side prompt), a custom effect is owned by the
/// signed-in user: they made it from a reference image + a description. It
/// syncs per account via `GET /v1/custom-effects`.
///
/// The card thumbnail IS the reference image (`thumbnailUrl`, a public bucket
/// URL). The generation prompt (the description) stays server-side — only
/// `/v1/stylize` reads it — so it's intentionally absent here, exactly like
/// `RemoteEffect`. To apply one, the client sends `custom_effect_id: id` to
/// `/v1/stylize`; the reference image is added there as a style reference.
public struct RemoteCustomEffect: Identifiable, Equatable, Sendable {
    /// Server row id. The apply call sends this as `custom_effect_id`.
    public let id: String
    /// User-facing name on the card (auto-derived from the description if the
    /// user didn't name it).
    public let label: String
    /// The reference image, doubling as the square thumbnail. Public URL.
    public let thumbnailUrl: URL?
    /// Sort order in the panel (lower = earlier).
    public let order: Int

    /// Cache/persistence key, namespaced so a custom effect never collides with
    /// a built-in `RemoteEffect.key` in the portrait's `effectCache` /
    /// `effectActiveRaw` (both string-keyed). Stable for the row's lifetime.
    public var cacheKey: String { "custom:\(id)" }

    public init(id: String, label: String, thumbnailUrl: URL?, order: Int) {
        self.id = id
        self.label = label
        self.thumbnailUrl = thumbnailUrl
        self.order = order
    }
}

extension RemoteCustomEffect: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, label, order
        case thumbnailUrl
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? "Custom effect"
        if let raw = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl), !raw.isEmpty {
            thumbnailUrl = URL(string: raw)
        } else {
            thumbnailUrl = nil
        }
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }
}
