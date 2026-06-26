// CMS-presets voor de Banner Studio (E39.2). Spiegelt `EffectsModel`: de
// beschikbare startpunten komen uit Payload (`backend.bannerPresets()`, E39.1);
// een nieuwe preset verschijnt zonder app-release. Tot de fetch landt (of bij
// offline / een CMS-hik) draait de UI op `BannerPresetItem.fallback` — een
// lokale set zodat de empty-state nooit leeg of kapot is. Thumbnails worden op
// de achtergrond geprefetcht (CMS levert een wijde preview-URL); lokale
// fallbacks hebben er geen en de kaart rendert dan de fill zelf.

import AppKit
import AvatarKit
import Foundation

/// Eén preset zoals de UI 'm toont: een gedecodeerde laag-stack + label +
/// optionele CMS-thumbnail-URL. Een klik maakt hieruit een nieuw `BannerDoc`
/// (zie `BannersGalleryView.makeBanner(from:)`).
struct BannerPresetItem: Identifiable, Equatable {
    let id: String
    let label: String
    let layers: BannerLayers
    let thumbnailURL: URL?

    /// Lokale fallback-presets (CMS down / nog niet geladen). Verving de oude
    /// hardgecodeerde lijst in `BannersEmptyState`; nu één bron.
    static let fallback: [BannerPresetItem] = [
        .init(id: "local-ocean", label: "Ocean",
              layers: BannerLayers(fill: .meshGradient(stops: [MeshStop(hex: "#6EC6FF", x: 0, y: 0), MeshStop(hex: "#E3F2FF", x: 1, y: 1)])),
              thumbnailURL: nil),
        .init(id: "local-blossom", label: "Blossom",
              layers: BannerLayers(fill: .meshGradient(stops: [MeshStop(hex: "#FFB4A2", x: 0, y: 0), MeshStop(hex: "#E7C6FF", x: 1, y: 1)])),
              thumbnailURL: nil),
        .init(id: "local-teal", label: "Teal",
              layers: BannerLayers(fill: .meshGradient(stops: [MeshStop(hex: "#2C3E50", x: 0, y: 0), MeshStop(hex: "#4CA1AF", x: 1, y: 1)])),
              thumbnailURL: nil),
        .init(id: "local-ink", label: "Ink",
              layers: BannerLayers(fill: .solid(hex: "#1C1917")),
              thumbnailURL: nil),
        .init(id: "local-mint", label: "Mint",
              layers: BannerLayers(fill: .meshGradient(stops: [MeshStop(hex: "#B5EAD7", x: 0, y: 0), MeshStop(hex: "#C7CEEA", x: 1, y: 1)])),
              thumbnailURL: nil),
        .init(id: "local-lime", label: "Lime",
              layers: BannerLayers(fill: .solid(hex: "#D5F466")),
              thumbnailURL: nil),
    ]
}

@Observable
final class BannerPresetsModel {
    /// Sessie-cache: gedeeld over alle instanties zodat heropenen van de
    /// Banners-tab/home niet terugvalt op de fallback. Leeg = nog niet geladen.
    private static var sessionCache: [BannerPresetItem] = []

    /// Gedeelde thumbnail-cache (key = preview-URL), zoals EffectsModel.
    private static let imageCache = NSCache<NSURL, NSImage>()

    /// De getoonde presets: start op de sessie-cache als die al gevuld is,
    /// anders op de lokale fallback.
    private(set) var presets: [BannerPresetItem] =
        BannerPresetsModel.sessionCache.isEmpty ? BannerPresetItem.fallback : BannerPresetsModel.sessionCache

    /// Loopt op telkens een thumbnail in de cache belandt → view herrendert.
    private(set) var thumbnailVersion = 0

    private let backend: BackendClient

    init(backend: BackendClient) { self.backend = backend }

    /// CMS-presets laden; soft-fail → behoud de fallback (zoals
    /// `EffectsModel.loadEffects`). Een preset waarvan `config` niet naar
    /// `BannerLayers` decodeert, wordt overgeslagen i.p.v. de hele lijst te laten
    /// vallen.
    func load() async {
        let remote = (try? await backend.bannerPresets()) ?? []
        let items = remote.compactMap(Self.item(from:))
        guard !items.isEmpty else { return }
        BannerPresetsModel.sessionCache = items
        presets = items
        prefetchThumbnails(for: items)
    }

    /// Decodeert de opake CMS-`config`-JSON naar de app's `BannerLayers`.
    private static func item(from remote: RemoteBannerPreset) -> BannerPresetItem? {
        guard let json = remote.configJSON?.data(using: .utf8),
              let layers = try? JSONDecoder().decode(BannerLayers.self, from: json)
        else { return nil }
        return BannerPresetItem(id: remote.key, label: remote.label, layers: layers, thumbnailURL: remote.thumbnailUrl)
    }

    func cachedThumbnail(for item: BannerPresetItem) -> NSImage? {
        guard let url = item.thumbnailURL else { return nil }
        return BannerPresetsModel.imageCache.object(forKey: url as NSURL)
    }

    /// Downloadt preview-URLs op de achtergrond en cachet ze; elke hit bumpt
    /// `thumbnailVersion` zodat de view herrendert.
    private func prefetchThumbnails(for items: [BannerPresetItem]) {
        let urls = items.compactMap(\.thumbnailURL)
            .filter { BannerPresetsModel.imageCache.object(forKey: $0 as NSURL) == nil }
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for url in urls {
                    group.addTask {
                        guard let (data, _) = try? await URLSession.shared.data(from: url),
                              let image = NSImage(data: data) else { return }
                        BannerPresetsModel.imageCache.setObject(image, forKey: url as NSURL)
                        await MainActor.run { self?.thumbnailVersion += 1 }
                    }
                }
            }
        }
    }
}
