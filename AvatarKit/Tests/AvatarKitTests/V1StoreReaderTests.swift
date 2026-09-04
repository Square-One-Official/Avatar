// E13.7 — lezer voor de live Aaavatar 1-store.
//
// De fixture is een échte SwiftData-store met een spiegel van v1's
// `Portrait`-entiteit (zelfde entiteits- en property-namen → zelfde tabel/
// kolommen: ZPORTRAIT, ZCUTOUTPNG, …). Zo dekt de test Core Data's echte
// external-storage-codering (0x01 inline / 0x02 + bestandsnaam) in plaats van
// een handgemaakt SQLite-bestand dat toevallig op v1 lijkt.

import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import AvatarKit

/// Spiegel van v1's `Portrait` (Avatar/Models/Portrait.swift) — alleen de
/// kolommen die de lezer aanraakt.
@Model
final class Portrait {
    @Attribute(.unique) var id: UUID
    var name: String
    var tags: String
    var createdAt: Date
    var updatedAt: Date
    var originalImageData: Data?
    @Attribute(.externalStorage) var cutoutPNG: Data?

    init(id: UUID, name: String, tags: String, createdAt: Date, updatedAt: Date,
         originalImageData: Data?, cutoutPNG: Data?) {
        self.id = id
        self.name = name
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originalImageData = originalImageData
        self.cutoutPNG = cutoutPNG
    }
}

/// Een store die géén v1-bibliotheek is (andere entiteit).
@Model
final class Widget {
    var title: String
    init(title: String) { self.title = title }
}

final class V1StoreReaderTests: XCTestCase {

    private var directory: URL!
    /// Blijft leven tijdens de test: zolang de container open is, staan de
    /// laatste writes in `-wal` en niet in `default.store` — precies het pad
    /// dat de lezer moet aankunnen.
    private var container: ModelContainer?

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("v1-store-fixture-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        container = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    // MARK: - Fixture

    private var storeURL: URL { directory.appendingPathComponent("default.store") }

    @MainActor
    private func makeStore(_ portraits: [Portrait]) throws {
        let config = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(for: Portrait.self, configurations: config)
        let context = container.mainContext
        for portrait in portraits { context.insert(portrait) }
        try context.save()
        self.container = container
    }

    /// Ruim boven Core Data's inline-drempel → belandt in _EXTERNAL_DATA.
    private func bigPNG() -> Data {
        var data = Data(count: 3_000_000)
        data[0] = 0x89; data[1] = 0x50; data[2] = 0x4E; data[3] = 0x47
        return data
    }

    /// Een écht 1×1 PNG via ImageIO, zodat `isImage` op iets echts test.
    private func tinyPNG() throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func fileBytes(_ name: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    // MARK: - Tests

    @MainActor
    func testReadsInlineAndExternalCutoutsWithOriginals() throws {
        let big = bigPNG()
        let small = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4])
        let original = try tinyPNG()
        let idA = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let idB = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let created = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let updated = Date(timeIntervalSinceReferenceDate: 800_000_500)

        try makeStore([
            Portrait(id: idA, name: "Ava", tags: "CEO", createdAt: created, updatedAt: updated,
                     originalImageData: original, cutoutPNG: big),
            // "bookmark"-achtige bytes als origineel: geen afbeelding → nil.
            Portrait(id: idB, name: "Bo", tags: "", createdAt: created, updatedAt: created,
                     originalImageData: Data("book0000mark".utf8), cutoutPNG: small)
        ])

        // De fixture moet het externe pad écht raken, anders test dit niets.
        let externalDir = directory.appendingPathComponent(".default_SUPPORT/_EXTERNAL_DATA")
        let externalFiles = (try? FileManager.default.contentsOfDirectory(atPath: externalDir.path)) ?? []
        XCTAssertFalse(externalFiles.isEmpty, "3 MB-cutout hoort in _EXTERNAL_DATA te staan")

        let library = try V1StoreReader.read(storeDirectory: directory)

        XCTAssertEqual(library.portraits.count, 2)
        XCTAssertEqual(library.skippedWithoutCutout, 0)
        let byID = Dictionary(uniqueKeysWithValues: library.portraits.map { ($0.id, $0) })

        let ava = try XCTUnwrap(byID[idA])
        XCTAssertEqual(ava.name, "Ava")
        XCTAssertEqual(ava.tags, "CEO")
        XCTAssertEqual(ava.createdAt.timeIntervalSinceReferenceDate, 800_000_000, accuracy: 0.001)
        XCTAssertEqual(ava.updatedAt.timeIntervalSinceReferenceDate, 800_000_500, accuracy: 0.001)
        XCTAssertEqual(ava.cutoutPNG, big, "externe blob via _EXTERNAL_DATA")
        XCTAssertEqual(ava.originalImage, original, "origineel gaat mee als het een afbeelding is")

        let bo = try XCTUnwrap(byID[idB])
        XCTAssertEqual(bo.cutoutPNG, small, "inline blob zonder de 0x01-prefix")
        XCTAssertNil(bo.originalImage, "niet-afbeelding wordt geen origineel")
    }

    @MainActor
    func testRecordWithoutCutoutIsCountedNotImported() throws {
        try makeStore([
            Portrait(id: UUID(), name: "Leeg", tags: "", createdAt: .now, updatedAt: .now,
                     originalImageData: nil, cutoutPNG: nil)
        ])

        let library = try V1StoreReader.read(storeDirectory: directory)

        XCTAssertEqual(library.portraits.count, 0)
        XCTAssertEqual(library.skippedWithoutCutout, 1)
    }

    @MainActor
    func testReadLeavesSourceFilesUntouched() throws {
        try makeStore([
            Portrait(id: UUID(), name: "Ava", tags: "", createdAt: .now, updatedAt: .now,
                     originalImageData: nil, cutoutPNG: bigPNG())
        ])
        let before = ["default.store", "default.store-wal", "default.store-shm"].map(fileBytes)
        XCTAssertNotNil(before[1], "fixture hoort in WAL-modus te staan")

        _ = try V1StoreReader.read(storeDirectory: directory)

        let after = ["default.store", "default.store-wal", "default.store-shm"].map(fileBytes)
        XCTAssertEqual(before, after, "lezen mag de v1-bestanden byte voor byte niet veranderen")
    }

    func testMissingStoreThrowsNotFound() {
        XCTAssertThrowsError(try V1StoreReader.read(storeDirectory: directory)) { error in
            XCTAssertEqual(error as? V1StoreReader.ReadError, .notFound)
        }
    }

    @MainActor
    func testStoreWithoutPortraitTableIsRejected() throws {
        let config = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(for: Widget.self, configurations: config)
        container.mainContext.insert(Widget(title: "x"))
        try container.mainContext.save()
        self.container = container

        XCTAssertThrowsError(try V1StoreReader.read(storeDirectory: directory)) { error in
            XCTAssertEqual(error as? V1StoreReader.ReadError, .notAV1Store)
        }
    }

    func testExternalReferenceRejectsPathTraversal() {
        let sneaky = Data([0x02]) + Data("../default.store".utf8)
        XCTAssertNil(V1StoreReader.resolveExternal(sneaky, externalDir: directory))
    }

    func testUUIDDecoding() {
        let bytes = Data([0x11, 0x11, 0x11, 0x11, 0x22, 0x22, 0x33, 0x33,
                          0x44, 0x44, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55])
        XCTAssertEqual(V1StoreReader.uuid(from: bytes)?.uuidString, "11111111-2222-3333-4444-555555555555")
        XCTAssertNil(V1StoreReader.uuid(from: Data([1, 2, 3])))
    }
}
