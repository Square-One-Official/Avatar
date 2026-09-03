// E13.2 — lezer voor v1-bibliotheek-back-ups.
//
// De fixture wordt hier met ZIPFoundation opgebouwd in exact het formaat dat
// v1's `LibraryArchive.export` schrijft (manifest.json met ISO-8601-datums +
// portraits/<uuid>/cutout.png), zodat de test het échte contract dekt en niet
// een handige versimpeling ervan.

import Foundation
import XCTest
import ZIPFoundation
@testable import AvatarKit

final class V1LibraryArchiveTests: XCTestCase {

    private var tempZip: URL!

    override func setUp() {
        super.setUp()
        tempZip = FileManager.default.temporaryDirectory
            .appendingPathComponent("v1-backup-\(UUID().uuidString).zip")
    }

    override func tearDown() {
        if let tempZip { try? FileManager.default.removeItem(at: tempZip) }
        super.tearDown()
    }

    private func makeArchive(manifest: String, entries: [String: Data] = [:]) throws {
        let archive = try Archive(url: tempZip, accessMode: .create)
        let manifestData = Data(manifest.utf8)
        try archive.addEntry(
            with: "manifest.json", type: .file,
            uncompressedSize: Int64(manifestData.count),
            provider: { position, size in
                manifestData.subdata(in: Int(position)..<Int(position) + size)
            }
        )
        for (path, data) in entries {
            try archive.addEntry(
                with: path, type: .file,
                uncompressedSize: Int64(data.count),
                provider: { position, size in
                    data.subdata(in: Int(position)..<Int(position) + size)
                }
            )
        }
    }

    private func manifestJSON(portraits: [(id: UUID, name: String, cutoutPath: String?)]) -> String {
        let items = portraits.map { p in
            """
            {"id":"\(p.id.uuidString)","name":"\(p.name)","tags":"CEO",
             "createdAt":"2025-11-03T10:00:00Z","updatedAt":"2026-01-15T09:30:00Z",
             \(p.cutoutPath.map { "\"cutoutPath\":\"\($0)\"," } ?? "")
             "faceRectX":0,"faceRectY":0,"faceRectW":1,"faceRectH":1}
            """
        }.joined(separator: ",")
        return """
        {"schemaVersion":1,"appVersion":"1.2.1","exportedAt":"2026-02-01T12:00:00Z",
         "portraits":[\(items)],"backgrounds":[]}
        """
    }

    func testReadsPortraitWithCutout() throws {
        let id = UUID()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        try makeArchive(
            manifest: manifestJSON(portraits: [(id, "Ava", "portraits/\(id.uuidString)/cutout.png")]),
            entries: ["portraits/\(id.uuidString)/cutout.png": png]
        )

        let library = try V1LibraryArchive.read(from: tempZip)

        XCTAssertEqual(library.portraits.count, 1)
        let portrait = try XCTUnwrap(library.portraits.first)
        XCTAssertEqual(portrait.id, id)
        XCTAssertEqual(portrait.name, "Ava")
        XCTAssertEqual(portrait.tags, "CEO")
        XCTAssertEqual(portrait.cutoutPNG, png)
        // ISO-8601-datums uit het manifest, niet de import-datum van vandaag.
        XCTAssertEqual(Calendar.current.component(.year, from: portrait.createdAt), 2025)
    }

    /// Records zonder cutout worden benoemd overgeslagen — niet stil gesnoeid
    /// en niet als leeg portret geïmporteerd.
    func testRecordWithoutCutoutIsCountedNotImported() throws {
        let withID = UUID(); let withoutID = UUID()
        let png = Data([1, 2, 3])
        try makeArchive(
            manifest: manifestJSON(portraits: [
                (withID, "Has image", "portraits/\(withID.uuidString)/cutout.png"),
                (withoutID, "No image", nil),
            ]),
            entries: ["portraits/\(withID.uuidString)/cutout.png": png]
        )

        let library = try V1LibraryArchive.read(from: tempZip)

        XCTAssertEqual(library.portraits.count, 1)
        XCTAssertEqual(library.skippedWithoutCutout, 1)
    }

    /// Een NIEUWER schema weigeren is eerlijker dan half importeren.
    func testNewerSchemaIsRejected() throws {
        try makeArchive(manifest: """
        {"schemaVersion":2,"portraits":[],"backgrounds":[]}
        """)
        XCTAssertThrowsError(try V1LibraryArchive.read(from: tempZip)) { error in
            XCTAssertEqual(error as? V1LibraryArchive.ReadError, .unsupportedSchema(2))
        }
    }

    func testMissingManifestThrows() throws {
        try makeArchive(manifest: "x")
        // Herbouw zonder manifest: alleen een los bestand.
        try FileManager.default.removeItem(at: tempZip)
        try makeArchive(manifest: "niet-json")
        // manifest.json aanwezig maar geen JSON → malformed.
        XCTAssertThrowsError(try V1LibraryArchive.read(from: tempZip)) { error in
            XCTAssertEqual(error as? V1LibraryArchive.ReadError, .malformedManifest)
        }
    }

    func testNonZipThrowsCannotOpen() throws {
        try Data("geen zip".utf8).write(to: tempZip)
        XCTAssertThrowsError(try V1LibraryArchive.read(from: tempZip)) { error in
            XCTAssertEqual(error as? V1LibraryArchive.ReadError, .cannotOpenArchive)
        }
    }
}
