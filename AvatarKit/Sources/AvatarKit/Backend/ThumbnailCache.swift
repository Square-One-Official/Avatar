// E52.1 — gedeelde thumbnail-cache voor CMS-media (backgrounds, effects,
// presets, banner-presets). Vervangt de losse per-panel `NSCache`-exemplaren:
// die waren in-memory-only, dus elke koude app-start (en elk panel dat z'n
// eigen cache had) downloadde de bronnen opnieuw. Supabase Storage serveert
// bovendien `Cache-Control: no-cache`, waardoor ook URLCache/AsyncImage niets
// hergebruikt.
//
// Drie lagen:
//   1. memory  — NSCache<NSURL, NSImage>, instant her-render binnen de sessie;
//   2. disk    — ~/Library/Caches/…/CMSThumbnails, her-opens na herstart instant;
//   3. netwerk — URLSession-download, daarna downsampled decode (CGImageSource-
//                thumbnail-API) zodat een per ongeluk groot origineel nooit
//                full-size gedecodeerd in het geheugen belandt.
//
// Latency is meetbaar gelogd (DoD): elke load logt bron + duur via os.Logger
// en een OSSignposter-interval ("thumbnail.load"), en `prefetch` logt de
// totale batch-duur bij panel-open ("thumbnail.prefetch").

import AppKit
import CryptoKit
import Foundation
import ImageIO
import os
import OSLog

public final class ThumbnailCache: @unchecked Sendable {

    /// Proces-breed gedeelde instantie; alle panels/grids gebruiken deze zodat
    /// dezelfde URL nooit twee keer wordt gedownload of gedecodeerd.
    public static let shared = ThumbnailCache()

    /// Injecteerbare transportlaag (tests): URL → rauwe bytes.
    public typealias DataProvider = @Sendable (URL) async throws -> Data

    private let memory = NSCache<NSURL, NSImage>()
    private let directory: URL
    private let maxPixelSize: Int
    private let dataProvider: DataProvider

    /// In-flight-dedupe: een cel-`.task` en een panel-`prefetch` die tegelijk
    /// om dezelfde URL vragen delen één download i.p.v. er twee te starten.
    /// `OSAllocatedUnfairLock` i.p.v. NSLock: veilig vanuit async context
    /// (de kritieke sectie bevat nooit een suspension point).
    private let inFlight = OSAllocatedUnfairLock(initialState: [URL: Task<NSImage?, Never>]())

    private static let log = Logger(subsystem: "nl.squareone.AvatarKit", category: "ThumbnailCache")
    private static let signposter = OSSignposter(subsystem: "nl.squareone.AvatarKit", category: "ThumbnailCache")

    /// - Parameters:
    ///   - directory: disk-cache-map; default `Caches/CMSThumbnails`.
    ///   - maxPixelSize: decode-plafond (langste zijde, px). 640 dekt de
    ///     grootste tile (banner-preset 240 pt @2x = 480 px) met marge.
    ///   - dataProvider: netwerk-transport; default `URLSession.shared`.
    public init(
        directory: URL? = nil,
        maxPixelSize: Int = 640,
        dataProvider: DataProvider? = nil
    ) {
        self.directory = directory ?? Self.defaultDirectory
        self.maxPixelSize = maxPixelSize
        self.dataProvider = dataProvider ?? { url in
            try await URLSession.shared.data(from: url).0
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CMSThumbnails", isDirectory: true)
    }

    // MARK: - Lookup

    /// Synchronen memory-hit (voor view-body's): geen disk/netwerk.
    public func cachedImage(for url: URL) -> NSImage? {
        memory.object(forKey: url as NSURL)
    }

    /// Memory → disk → netwerk. Nil bij download-/decode-fout (de view valt
    /// dan terug op z'n placeholder — soft-fail, geen throw).
    public func image(for url: URL) async -> NSImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }

        // Dedupe: bestaande in-flight task hergebruiken.
        let task = inFlight.withLock { running -> Task<NSImage?, Never> in
            if let existing = running[url] { return existing }
            let task = Task<NSImage?, Never> { [weak self] in
                await self?.loadIgnoringMemory(url) ?? nil
            }
            running[url] = task
            return task
        }
        let image = await task.value
        inFlight.withLock { $0[url] = nil }
        return image
    }

    /// Warmt de cache voor een panel-open. Fire-and-forget; logt de totale
    /// duur zodat de "koud panel-open < ~500 ms"-DoD meetbaar is.
    public func prefetch(_ urls: [URL]) {
        let missing = urls.filter { memory.object(forKey: $0 as NSURL) == nil }
        guard !missing.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let state = Self.signposter.beginInterval("thumbnail.prefetch")
            let start = ContinuousClock.now
            await withTaskGroup(of: Void.self) { group in
                for url in missing {
                    group.addTask { _ = await self.image(for: url) }
                }
            }
            let ms = Self.milliseconds(ContinuousClock.now - start)
            Self.signposter.endInterval("thumbnail.prefetch", state)
            Self.log.info("prefetch \(missing.count) thumbnails in \(ms, format: .fixed(precision: 1)) ms")
        }
    }

    // MARK: - Laag 2/3

    private func loadIgnoringMemory(_ url: URL) async -> NSImage? {
        let state = Self.signposter.beginInterval("thumbnail.load")
        let start = ContinuousClock.now
        defer { Self.signposter.endInterval("thumbnail.load", state) }

        let file = fileURL(for: url)

        // Disk-hit: downsampled decode, dan memory vullen.
        if let data = try? Data(contentsOf: file), let image = Self.decodeDownsampled(data, maxPixelSize: maxPixelSize) {
            memory.setObject(image, forKey: url as NSURL)
            logLoad("disk", url: url, since: start)
            return image
        }

        // Netwerk: download → disk → downsampled decode → memory.
        guard let data = try? await dataProvider(url),
              let image = Self.decodeDownsampled(data, maxPixelSize: maxPixelSize) else {
            logLoad("failed", url: url, since: start)
            return nil
        }
        try? data.write(to: file, options: .atomic)
        memory.setObject(image, forKey: url as NSURL)
        logLoad("network", url: url, since: start)
        return image
    }

    private func logLoad(_ source: String, url: URL, since start: ContinuousClock.Instant) {
        let ms = Self.milliseconds(ContinuousClock.now - start)
        Self.log.info("thumbnail \(source, privacy: .public) \(ms, format: .fixed(precision: 1)) ms — \(url.lastPathComponent, privacy: .public)")
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1e15
    }

    /// Content-addressed bestandsnaam: SHA-256 van de absolute URL. De
    /// render-query (`?width=…`) telt mee, zodat een andere maat een eigen
    /// cache-entry krijgt.
    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("img")
    }

    /// Downsampled decode via de CGImageSource-thumbnail-API: decodeert
    /// rechtstreeks naar maximaal `maxPixelSize` px (langste zijde) i.p.v.
    /// eerst het volledige origineel in het geheugen te rasteren.
    static func decodeDownsampled(_ data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
