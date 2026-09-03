// E55.6 — disk-persistentie van de CMS-lijsten (effects + custom effects).
// De thumbnails hadden al een disk-cache (E52.1, ThumbnailCache), maar de
// JSON-lijst die de URLs benoemt niet: elke koude start blokkeerde álle
// thumbnails achter één netwerk-round-trip naar /v1/effects. Met deze cache
// hydrateert het paneel synchroon van disk (stale-while-revalidate) en zijn
// warme opens instant — de netwerk-refresh ververst lijst + disk daarna.
//
// Bewust in Caches (het OS mag opruimen): de lijst is her-fetchbaar en de
// hardgecodeerde fallback vangt een lege cache op.

import Foundation
import os

public struct EffectsListCache: Sendable {

    public static let shared = EffectsListCache()

    private let directory: URL
    private static let log = Logger(subsystem: "nl.squareone.AvatarKit", category: "EffectsListCache")

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CMSLists", isDirectory: true)
    }

    // MARK: - Effects (built-in, CMS)

    public func loadEffects() -> [RemoteEffect]? {
        load([RemoteEffect].self, from: "effects.json")
    }

    public func saveEffects(_ effects: [RemoteEffect]) {
        save(effects, to: "effects.json")
    }

    // MARK: - Custom effects (per account, E34)

    public func loadCustomEffects() -> [RemoteCustomEffect]? {
        load([RemoteCustomEffect].self, from: "custom-effects.json")
    }

    public func saveCustomEffects(_ effects: [RemoteCustomEffect]) {
        save(effects, to: "custom-effects.json")
    }

    // MARK: - Generiek

    private func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let file = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: file) else { return nil }
        // Corrupt bestand → nil (caller valt terug op fallback); opruimen zodat
        // we niet elke start opnieuw op dezelfde rotte bytes stuklopen.
        guard let decoded = try? JSONDecoder().decode(type, from: data) else {
            try? FileManager.default.removeItem(at: file)
            Self.log.warning("corrupt \(name, privacy: .public) verwijderd")
            return nil
        }
        return decoded
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
