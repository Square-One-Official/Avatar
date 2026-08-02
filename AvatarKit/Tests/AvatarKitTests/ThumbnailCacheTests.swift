import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import AvatarKit

/// E52.1 — gedrags-tests voor de gedeelde CMS-thumbnail-cache:
/// miss → download → memory-hit, disk-hit over instanties heen (her-open na
/// herstart), soft-fail naar nil bij een transportfout, en het downsample-
/// plafond van de CGImageSource-decode.
final class ThumbnailCacheTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbnailCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    // MARK: - Helpers

    private static let url = URL(string: "https://cdn.example.test/storage/v1/render/image/public/media/a.png?width=320")!

    /// Klein effen PNG-bestand (default 8×8) als download-fixture.
    private static func pngData(side: Int = 8) throws -> Data {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw XCTSkip("CGContext unavailable") }
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = ctx.makeImage() else { throw XCTSkip("makeImage failed") }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            throw XCTSkip("CGImageDestination unavailable")
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    /// Thread-safe download-teller voor de injecteerbare provider.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    // MARK: - Tests

    func testMissDownloadsThenMemoryHits() async throws {
        let png = try Self.pngData()
        let counter = Counter()
        let cache = ThumbnailCache(directory: directory) { _ in
            counter.increment()
            return png
        }

        // Koud: geen memory-hit, download vereist.
        XCTAssertNil(cache.cachedImage(for: Self.url))
        let first = await cache.image(for: Self.url)
        XCTAssertNotNil(first)
        XCTAssertEqual(counter.count, 1)

        // Warm: memory-hit — geen tweede download.
        XCTAssertNotNil(cache.cachedImage(for: Self.url))
        let second = await cache.image(for: Self.url)
        XCTAssertNotNil(second)
        XCTAssertEqual(counter.count, 1)
    }

    func testDiskHitAcrossInstancesSkipsDownload() async throws {
        let png = try Self.pngData()
        let warm = ThumbnailCache(directory: directory) { _ in png }
        _ = await warm.image(for: Self.url)

        // Nieuwe instantie, zelfde map (≈ app-herstart): disk-hit, provider
        // wordt niet aangeraakt.
        let counter = Counter()
        let cold = ThumbnailCache(directory: directory) { _ in
            counter.increment()
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertNil(cold.cachedImage(for: Self.url), "memory hoort leeg na 'herstart'")
        let image = await cold.image(for: Self.url)
        XCTAssertNotNil(image, "disk-cache hoort de download te vervangen")
        XCTAssertEqual(counter.count, 0)
    }

    func testTransportFailureSoftFailsToNil() async {
        let cache = ThumbnailCache(directory: directory) { _ in
            throw URLError(.timedOut)
        }
        let image = await cache.image(for: Self.url)
        XCTAssertNil(image)
        XCTAssertNil(cache.cachedImage(for: Self.url))
    }

    func testUndecodableDataSoftFailsToNil() async {
        let cache = ThumbnailCache(directory: directory) { _ in
            Data("definitely not an image".utf8)
        }
        let image = await cache.image(for: Self.url)
        XCTAssertNil(image)
    }

    func testDecodeDownsamplesLargeSources() async throws {
        // Een 256×256-bron met een decode-plafond van 64 px hoort maximaal
        // 64 px (langste zijde) uit de CGImageSource-thumbnail-API te komen.
        let png = try Self.pngData(side: 256)
        let cache = ThumbnailCache(directory: directory, maxPixelSize: 64) { _ in png }
        let image = await cache.image(for: Self.url)
        let size = try XCTUnwrap(image?.size)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 64)
    }

    // MARK: - Disk-byte-cap (E55.6)

    /// Boven de cap wijken de oudste entries (mtime = LRU); de nieuwste blijft.
    func testDiskCapEvictsOldestFirst() throws {
        let fm = FileManager.default
        // Drie bestanden van elk 1000 bytes met gespreide mtimes.
        for (i, name) in ["oud", "midden", "nieuw"].enumerated() {
            let file = directory.appendingPathComponent("\(name).img")
            try Data(repeating: 0xAB, count: 1000).write(to: file)
            try fm.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: Double(i - 3) * 60)],
                ofItemAtPath: file.path
            )
        }
        // Cap van 1500 bytes → de twee oudste (oud, midden) moeten wijken.
        let cache = ThumbnailCache(directory: directory, maxDiskBytes: 1500) { _ in Data() }
        cache.enforceDiskCapNow()
        let remaining = try fm.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(remaining, ["nieuw.img"])
    }

    /// Onder de cap wordt niets verwijderd.
    func testDiskCapLeavesSmallCacheAlone() throws {
        let file = directory.appendingPathComponent("a.img")
        try Data(repeating: 1, count: 100).write(to: file)
        let cache = ThumbnailCache(directory: directory, maxDiskBytes: 1_000_000) { _ in Data() }
        cache.enforceDiskCapNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
