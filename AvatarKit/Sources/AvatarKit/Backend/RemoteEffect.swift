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
    /// Sticker-fix (2026-09-02): wat voor beeld het effect oplevert. De server
    /// (`/v1/effects`, DIE_CUT_STYLE_KEYS) is de bron; ontbreekt het veld
    /// (oude lijst-snapshot) dan `.portrait` = het bestaande gedrag.
    public let composition: Composition

    /// `portrait`: het onderwerp loopt tot de onderrand door (romp uit beeld) —
    /// de canvas-transform blijft behouden. `dieCut`: één vrijstaande, rondom
    /// gesloten vorm (sticker) — de client kadert 'm als content-fit.
    public enum Composition: String, Sendable, Equatable {
        case portrait
        case dieCut = "die_cut"
    }

    public var isDieCut: Bool { composition == .dieCut }

    public var id: String { key }

    public init(
        key: String, label: String, thumbnailUrl: URL?, order: Int,
        composition: Composition = .portrait
    ) {
        self.key = key
        self.label = label
        self.thumbnailUrl = thumbnailUrl
        self.order = order
        self.composition = composition
    }
}

extension RemoteEffect: Decodable {
    // Custom init in een extension behoudt de memberwise `init` (voor `fallback`).
    enum CodingKeys: String, CodingKey {
        case key, label, order, composition
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
        // Onbekende waarde (nieuwere server) → portrait: nooit de lijst laten falen.
        composition = (try c.decodeIfPresent(String.self, forKey: .composition))
            .flatMap(Composition.init(rawValue:)) ?? .portrait
    }
}

// E55.6: symmetrische encode zodat `EffectsListCache` de lijst op disk kan
// persisteren (stale-while-revalidate). Zelfde keys als de decode — de cache
// gebruikt een plain JSONEncoder/-Decoder, dus geen snake_case-strategie nodig.
extension RemoteEffect: Encodable {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(label, forKey: .label)
        try c.encodeIfPresent(thumbnailUrl?.absoluteString, forKey: .thumbnailUrl)
        try c.encode(order, forKey: .order)
        try c.encode(composition.rawValue, forKey: .composition)
    }
}

extension RemoteEffect {
    /// Offline / pre-fetch-fallback (E55.6: de zes Styles-2.0-keys — besluit
    /// Thierry 2026-08-02; de oude 4 gaan op inactief). De keys matchen de
    /// CMS-seed (`effects-seed.json`) zodat genereren werkt vóór de lijst
    /// geladen is en het paneel nooit leeg opent (geen thumbnails — die komen
    /// uit de CMS).
    public static let fallback: [RemoteEffect] = [
        RemoteEffect(key: "balloon", label: "Balloon", thumbnailUrl: nil, order: 10, composition: .dieCut),
        RemoteEffect(key: "windy", label: "Windy", thumbnailUrl: nil, order: 11),
        RemoteEffect(key: "sticker", label: "Sticker", thumbnailUrl: nil, order: 12, composition: .dieCut),
        RemoteEffect(key: "flowers", label: "Flowers", thumbnailUrl: nil, order: 13),
        RemoteEffect(key: "3d-head", label: "3D Head", thumbnailUrl: nil, order: 14),
        RemoteEffect(key: "hairy", label: "Hairy", thumbnailUrl: nil, order: 15),
    ]
}
