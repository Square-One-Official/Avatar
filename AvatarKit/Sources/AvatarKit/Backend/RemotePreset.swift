import Foundation

/// Gedeeld preset-model voor Hair-, Clothes- en Face-panelen (E33+).
/// Elke rij in de CMS-collectie `hair-presets` / `clothes-presets` / `face-presets`
/// wordt via `GET /v1/hair-presets` enz. opgehaald als `RemotePreset`.
/// De `prompt` blijft server-side; `key`, `label`, `order` en (E52.1) een
/// optionele `thumbnail_url` komen mee. De thumbnail is een verkleinde
/// Supabase-render-variant; `nil` zolang de CMS-collectie geen thumbnail heeft.
public struct RemotePreset: Identifiable, Equatable, Sendable {
    public let key: String
    public let label: String
    public let order: Int
    /// Optionele preset-preview (E52.1); `nil` → het paneel toont z'n icoon/chip.
    public let thumbnailUrl: URL?

    public var id: String { key }

    public init(key: String, label: String, order: Int, thumbnailUrl: URL? = nil) {
        self.key = key
        self.label = label
        self.order = order
        self.thumbnailUrl = thumbnailUrl
    }
}

extension RemotePreset: Decodable {
    // Custom decode in een extension behoudt de memberwise `init` (voor de
    // hardgecodeerde panel-fallbacks). Decode loopt via `BackendClient`'s
    // `.convertFromSnakeCase`, dus `thumbnail_url` → `thumbnailUrl`. URL als
    // `String` (zoals RemoteEffect) zodat een leeg/ontbrekend veld `nil` wordt
    // i.p.v. de hele lijst te laten falen.
    enum CodingKeys: String, CodingKey {
        case key, label, order
        case thumbnailUrl
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? key
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 99
        if let raw = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl), !raw.isEmpty {
            thumbnailUrl = URL(string: raw)
        } else {
            thumbnailUrl = nil
        }
    }
}

/// Wrapper voor de `{ presets: [...] }` response van de drie preset-endpoints.
public struct RemotePresetsResponse: Decodable, Sendable {
    public let presets: [RemotePreset]
}
