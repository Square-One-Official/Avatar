import Foundation

/// Gedeeld preset-model voor Hair-, Clothes- en Face-panelen (E33+).
/// Elke rij in de CMS-collectie `hair-presets` / `clothes-presets` / `face-presets`
/// wordt via `GET /v1/hair-presets` enz. opgehaald als `RemotePreset`.
/// De `prompt` blijft server-side; alleen `key`, `label` en `order` komen mee.
public struct RemotePreset: Identifiable, Equatable, Sendable, Decodable {
    public let key: String
    public let label: String
    public let order: Int

    public var id: String { key }

    public init(key: String, label: String, order: Int) {
        self.key = key
        self.label = label
        self.order = order
    }
}

/// Wrapper voor de `{ presets: [...] }` response van de drie preset-endpoints.
public struct RemotePresetsResponse: Decodable, Sendable {
    public let presets: [RemotePreset]
}
