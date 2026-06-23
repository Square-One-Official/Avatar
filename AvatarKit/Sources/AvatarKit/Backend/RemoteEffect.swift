import Foundation

/// One Effects-stijl, CMS-gestuurd (E33). Vervangt de hardgecodeerde
/// `StylizeStyle`-enum: de lijst komt nu uit Payload (`GET /v1/effects`) zodat
/// een nieuw effect — kaart + thumbnail + prompt — zonder app-release kan
/// worden toegevoegd. `key` is exact de server-side stijl-key uit `/v1/stylize`
/// (de prompt + identity-clausule leven op de server; de client kiest alleen de
/// key). Geen vrij prompt-veld: productie blijft binnen de CMS-whitelist.
///
/// Decode loopt via `BackendClient`'s generieke pad (`.convertFromSnakeCase`),
/// dus `thumbnail_url` → `thumbnailUrl`. We decoderen de URL als `String`
/// (zoals `Announcement.imageUrl`) zodat een leeg/ontbrekend veld `nil` wordt
/// i.p.v. de hele lijst te laten falen.
public struct RemoteEffect: Identifiable, Equatable, Sendable {
    /// Stabiele stijl-key, naar `/v1/stylize` gestuurd. Tevens de cache-key op
    /// het portret (`effectCache`/`effectActiveRaw`) — niet wijzigen zodra live.
    public let key: String
    /// Gebruikersgerichte naam op de stijl-kaart.
    public let label: String
    /// Vierkante preview; `nil` → de kaart valt terug op het sparkles-icoon.
    public let thumbnailUrl: URL?
    /// Sorteervolgorde in het paneel (lager = eerder).
    public let order: Int

    public var id: String { key }

    public init(key: String, label: String, thumbnailUrl: URL?, order: Int) {
        self.key = key
        self.label = label
        self.thumbnailUrl = thumbnailUrl
        self.order = order
    }
}

extension RemoteEffect: Decodable {
    // Custom init in een extension behoudt de memberwise `init` (voor `fallback`).
    enum CodingKeys: String, CodingKey {
        case key, label, order
        case thumbnailUrl
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        // Label ontbreekt → val terug op de key zodat de kaart nooit leeg is.
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? key
        if let raw = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl), !raw.isEmpty {
            thumbnailUrl = URL(string: raw)
        } else {
            thumbnailUrl = nil
        }
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }
}

extension RemoteEffect {
    /// Offline / pre-fetch-fallback: de vier launch-effecten. De keys matchen de
    /// server-`STYLE_PROMPTS` zodat genereren werkt vóór de CMS-lijst geladen is
    /// en het paneel nooit leeg opent (geen thumbnails — die komen uit de CMS).
    public static let fallback: [RemoteEffect] = [
        RemoteEffect(key: "clay", label: "Clay", thumbnailUrl: nil, order: 0),
        RemoteEffect(key: "wood", label: "Wood", thumbnailUrl: nil, order: 1),
        RemoteEffect(key: "3d", label: "3D", thumbnailUrl: nil, order: 2),
        RemoteEffect(key: "scribble", label: "Scribble", thumbnailUrl: nil, order: 3),
    ]
}
