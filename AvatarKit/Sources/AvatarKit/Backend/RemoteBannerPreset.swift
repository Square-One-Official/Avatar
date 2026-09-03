import Foundation

/// Eén banner-preset, CMS-gestuurd (E39, `GET /v1/banner-presets`). Spiegelt
/// `RemoteEffect`: een nieuw startpunt voor de Banner Studio kan zonder
/// app-release worden toegevoegd. `config` is een JSON-string die de app
/// decodeert naar z'n eigen `BannerLayers`-laagstack (die leeft in de app, niet
/// in AvatarKit — vandaar een neutrale string hier).
///
/// Decode loopt via `BackendClient`'s `.convertFromSnakeCase`, dus
/// `thumbnail_url` → `thumbnailUrl`. URL als `String` zodat een leeg/ontbrekend
/// veld `nil` wordt i.p.v. de hele lijst te laten falen.
public struct RemoteBannerPreset: Identifiable, Equatable, Sendable {
    /// Stabiele key (= cache-key); niet wijzigen zodra live.
    public let key: String
    /// Gebruikersgerichte naam op de preset-kaart.
    public let label: String
    /// Groepering (bv. "minimal", "bold"). Leeg → "default".
    public let category: String
    /// Wijde preview; `nil` → de app rendert de laagstack zelf.
    public let thumbnailUrl: URL?
    /// JSON-geserialiseerde `BannerLayers`-laagstack; de app decodeert 'm.
    public let configJSON: String?
    /// Sorteervolgorde (lager = eerder).
    public let order: Int

    public var id: String { key }

    public init(key: String, label: String, category: String, thumbnailUrl: URL?, configJSON: String?, order: Int) {
        self.key = key
        self.label = label
        self.category = category
        self.thumbnailUrl = thumbnailUrl
        self.configJSON = configJSON
        self.order = order
    }
}

extension RemoteBannerPreset: Decodable {
    enum CodingKeys: String, CodingKey {
        case key, label, category, order
        case thumbnailUrl
        case config
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? key
        let cat = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        category = cat.isEmpty ? "default" : cat
        if let raw = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl), !raw.isEmpty {
            thumbnailUrl = URL(string: raw)
        } else {
            thumbnailUrl = nil
        }
        let cfg = try c.decodeIfPresent(String.self, forKey: .config)
        configJSON = (cfg?.isEmpty == true) ? nil : cfg
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }
}
