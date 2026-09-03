import Foundation

/// Eén achtergrond uit de CMS (E33+), CMS-gestuurd via `GET /v1/backgrounds`.
/// De app groepeert op `category` en toont elke groep als een gelabelde
/// sectie in het Background-paneel. `imageUrl` is voor export-compositing;
/// `thumbnailUrl` is de kleine swatch-preview (valt server-side terug op imageUrl).
public struct RemoteBackground: Identifiable, Equatable, Sendable {
    public let key: String
    public let label: String
    public let category: String
    public let imageUrl: URL
    public let thumbnailUrl: URL
    public let order: Int

    public var id: String { key }

    public init(key: String, label: String, category: String, imageUrl: URL, thumbnailUrl: URL, order: Int) {
        self.key = key
        self.label = label
        self.category = category
        self.imageUrl = imageUrl
        self.thumbnailUrl = thumbnailUrl
        self.order = order
    }
}

extension RemoteBackground: Decodable {
    enum CodingKeys: String, CodingKey {
        case key, label, category, order
        case imageUrl
        case thumbnailUrl
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? key
        category = try c.decode(String.self, forKey: .category)
        guard
            let rawImage = try? c.decode(String.self, forKey: .imageUrl),
            let imgURL = URL(string: rawImage)
        else { throw DecodingError.dataCorruptedError(forKey: .imageUrl, in: c, debugDescription: "invalid image_url") }
        imageUrl = imgURL
        let rawThumb = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl) ?? rawImage
        thumbnailUrl = URL(string: rawThumb) ?? imgURL
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 99
    }
}
