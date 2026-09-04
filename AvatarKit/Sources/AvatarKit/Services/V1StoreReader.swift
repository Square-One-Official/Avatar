// E13.7 — read-only lezer voor de LIVE Aaavatar 1-bibliotheek op dezelfde Mac.
//
// Context: v1 (bundle-id nl.avatar.app) en 2.0 (nl.squareone.aaavatar2) zijn
// twee gesandboxte apps. Een drag-install van 2.0 vervangt Aaavatar.app maar
// laat v1's container met rust:
//   ~/Library/Containers/nl.avatar.app/Data/Library/Application Support/
//     default.store (+ -wal / -shm)            ← SwiftData/Core Data-SQLite
//     .default_SUPPORT/_EXTERNAL_DATA/<UUID>   ← grote blobs (de cutouts)
// 13.2 leunt op een zip-export die de gebruiker in v1 maakt vóór de install;
// deze lezer is het vangnet voor iedereen die dat oversloeg. Vereist de
// read-only sandbox-uitzondering in Avatar2.entitlements; macOS 15+ vraagt
// daarbovenop eenmalig "would like to access data from other apps".
//
// Strikt read-only richting v1: de drie store-bestanden worden eerst naar een
// tmp-map GEKOPIEERD en alleen de kopie gaat open. SQLite raakt het origineel
// nooit aan (geen WAL-checkpoint, geen -shm-rewrite) — ook al openen we de
// kopie read-write, zodat WAL-herstel op de kopie gewoon kan lopen.
//
// Opslagcodering (empirisch geverifieerd met een SwiftData-fixture,
// 2026-09-04; zie V1StoreReaderTests): kolommen van
// `@Attribute(.externalStorage)`-properties bevatten óf 0x01 + de bytes
// inline (kleine waarden) óf 0x02 + de ASCII-UUID-bestandsnaam in
// _EXTERNAL_DATA (grote waarden). Gewone `Data`-kolommen bevatten de rauwe
// bytes. UUID-attributen zijn 16 rauwe bytes; datums zijn seconden sinds
// 2001-01-01 (Core Data-referentiedatum).
//
// Winst t.o.v. het zip-pad: v1 bewaart de ORIGINELE foto-bytes in
// `originalImageData` (ondanks de "bookmark"-comment op het model — zie
// Avatar/Services/ImportFlow.swift:1031), en de zip-export laat die weg. Wij
// nemen 'm mee zodra hij als afbeelding decodeert.

import Foundation
import ImageIO
import SQLite3

public enum V1StoreReader {

    public enum ReadError: LocalizedError, Equatable {
        /// Geen `default.store` op de verwachte plek.
        case notFound
        /// Sandbox/TCC weigerde (de gebruiker koos "Don't Allow", of de
        /// entitlement ontbreekt in deze build).
        case accessDenied
        case cannotCopy(String)
        case cannotOpen(String)
        /// Wel een SQLite-bestand, maar geen `ZPORTRAIT`-tabel.
        case notAV1Store
        case query(String)

        public var errorDescription: String? {
            switch self {
            case .notFound:
                return "No Aaavatar 1 library was found on this Mac."
            case .accessDenied:
                return "macOS didn't allow access to the Aaavatar 1 library. Use “Import backup…” instead."
            case .cannotCopy(let m):
                return "The Aaavatar 1 library couldn't be read (\(m))."
            case .cannotOpen(let m):
                return "The Aaavatar 1 library couldn't be opened (\(m))."
            case .notAV1Store:
                return "That folder doesn't contain an Aaavatar 1 library."
            case .query(let m):
                return "The Aaavatar 1 library couldn't be read (\(m))."
            }
        }
    }

    public static let v1BundleID = "nl.avatar.app"
    static let storeFilename = "default.store"
    /// Core Data's map voor external-storage-blobs naast `default.store`.
    static let externalDataSubpath = ".default_SUPPORT/_EXTERNAL_DATA"

    /// v1's Application Support-map voor de huidige gebruiker. Bewust via de
    /// ÉCHTE home-directory (getpwuid): binnen de sandbox wijst
    /// `NSHomeDirectory()` naar onze eigen container.
    public static func defaultStoreDirectory() -> URL {
        let home: String
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            home = String(cString: dir)
        } else {
            home = NSHomeDirectory()
        }
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Containers/\(v1BundleID)/Data/Library/Application Support", isDirectory: true)
    }

    /// Bestaat er een v1-store? Let op: op macOS 15+ kan alleen al deze
    /// check de "data from other apps"-prompt triggeren — alleen aanroepen
    /// op een expliciete gebruikersactie.
    public static func libraryExists(at directory: URL = defaultStoreDirectory()) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(storeFilename).path)
    }

    /// Leest de complete v1-bibliotheek. Blokkerend (I/O + kopie van de
    /// store) — niet op de main actor aanroepen bij grote bibliotheken.
    public static func read(storeDirectory: URL = defaultStoreDirectory()) throws -> V1LibraryArchive.Library {
        let fm = FileManager.default
        let source = storeDirectory.appendingPathComponent(storeFilename)

        // Onderscheid "niet aanwezig" van "niet toegestaan": een sandbox-
        // of TCC-weigering komt als leesfout terug, niet als ontbrekend bestand.
        do {
            _ = try fm.attributesOfItem(atPath: source.path)
        } catch {
            throw classify(error, fallback: .notFound)
        }

        let temp = fm.temporaryDirectory
            .appendingPathComponent("v1-store-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        // Store + WAL + shm: in WAL-modus staan de laatste wijzigingen alléén
        // in `-wal`; zonder die kopie zou een recente v1-bibliotheek oud lijken.
        for suffix in ["", "-wal", "-shm"] {
            let src = storeDirectory.appendingPathComponent(storeFilename + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            do {
                try fm.copyItem(at: src, to: temp.appendingPathComponent(storeFilename + suffix))
            } catch {
                throw classify(error, fallback: .cannotCopy(error.localizedDescription))
            }
        }

        let externalDir = storeDirectory.appendingPathComponent(externalDataSubpath, isDirectory: true)
        return try readStore(at: temp.appendingPathComponent(storeFilename), externalDir: externalDir)
    }

    // MARK: - SQLite

    /// Opent de (gekopieerde) store en leest ZPORTRAIT. `SELECT *` + mapping
    /// op kolomnaam: oudere v1-stores missen mogelijk latere kolommen en
    /// mogen daar niet op stukgaan.
    static func readStore(at storeURL: URL, externalDir: URL) throws -> V1LibraryArchive.Library {
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(storeURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil)
        guard rc == SQLITE_OK, let db = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite error \(rc)"
            if let handle { sqlite3_close(handle) }
            throw ReadError.cannotOpen(message)
        }
        defer { sqlite3_close(db) }

        guard try tableExists(db, "ZPORTRAIT") else { throw ReadError.notAV1Store }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT * FROM ZPORTRAIT", -1, &statement, nil) == SQLITE_OK,
              let stmt = statement else {
            throw ReadError.query(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var columns: [String: Int32] = [:]
        for i in 0..<sqlite3_column_count(stmt) {
            columns[String(cString: sqlite3_column_name(stmt, i)).uppercased()] = i
        }

        func blob(_ name: String) -> Data? {
            guard let i = columns[name], sqlite3_column_type(stmt, i) == SQLITE_BLOB else { return nil }
            let count = Int(sqlite3_column_bytes(stmt, i))
            guard count > 0, let bytes = sqlite3_column_blob(stmt, i) else { return nil }
            return Data(bytes: bytes, count: count)
        }
        func text(_ name: String) -> String? {
            guard let i = columns[name], sqlite3_column_type(stmt, i) == SQLITE_TEXT,
                  let cString = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: cString)
        }
        func date(_ name: String) -> Date? {
            guard let i = columns[name], sqlite3_column_type(stmt, i) != SQLITE_NULL else { return nil }
            return Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, i))
        }

        var portraits: [V1LibraryArchive.PortraitPayload] = []
        var skipped = 0
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw ReadError.query(String(cString: sqlite3_errmsg(db)))
            }
            // Zonder geldige v1-UUID is er geen dedup-sleutel; zo'n rij hoort
            // in v1 niet te bestaan (`@Attribute(.unique) var id: UUID`).
            guard let id = blob("ZID").flatMap(uuid(from:)) else { skipped += 1; continue }
            // Geen cutout = niets om te tonen; benoemd i.p.v. stil gesnoeid
            // (zelfde contract als de zip-lezer).
            guard let cutout = resolveExternal(blob("ZCUTOUTPNG"), externalDir: externalDir),
                  !cutout.isEmpty else { skipped += 1; continue }
            let createdAt = date("ZCREATEDAT") ?? Date()
            let original = blob("ZORIGINALIMAGEDATA").flatMap { isImage($0) ? $0 : nil }
            portraits.append(V1LibraryArchive.PortraitPayload(
                id: id,
                name: text("ZNAME") ?? "",
                tags: text("ZTAGS") ?? "",
                createdAt: createdAt,
                updatedAt: date("ZUPDATEDAT") ?? createdAt,
                cutoutPNG: cutout,
                originalImage: original
            ))
        }

        return V1LibraryArchive.Library(
            schemaVersion: V1LibraryArchive.supportedSchemaVersion,
            appVersion: "1.x (library on this Mac)",
            exportedAt: Date(),
            portraits: portraits,
            skippedWithoutCutout: skipped
        )
    }

    private static func tableExists(_ db: OpaquePointer, _ table: String) throws -> Bool {
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            throw ReadError.query(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        // SQLITE_TRANSIENT laat SQLite de string kopiëren; de Swift-string leeft
        // korter dan het statement.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, table, -1, transient)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    // MARK: - Decodering

    /// Core Data-codering voor `.externalStorage`-kolommen (zie header).
    static func resolveExternal(_ column: Data?, externalDir: URL) -> Data? {
        guard let column, let tag = column.first else { return nil }
        switch tag {
        case 0x01:
            return column.count > 1 ? Data(column.dropFirst()) : nil
        case 0x02:
            guard let name = String(data: column.dropFirst(), encoding: .utf8),
                  isPlainFilename(name) else { return nil }
            return try? Data(contentsOf: externalDir.appendingPathComponent(name))
        case 0x89:
            // Rauwe PNG zonder prefix — komt in de praktijk niet voor, maar
            // een cutout weggooien omdat de codering ooit verandert is erger
            // dan deze ene defensieve tak.
            return column
        default:
            return nil
        }
    }

    static func uuid(from data: Data) -> UUID? {
        guard data.count == 16 else { return nil }
        let raw: uuid_t = data.withUnsafeBytes { $0.load(as: uuid_t.self) }
        return UUID(uuid: raw)
    }

    /// Een verwijzing uit de store blijft binnen `_EXTERNAL_DATA`.
    private static func isPlainFilename(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\\") && name != "." && name != ".."
    }

    /// v1's `originalImageData` heet in het model een bookmark; in de praktijk
    /// zijn het de foto-bytes. Alleen wat als afbeelding decodeert gaat mee —
    /// een écht bookmark-blob zou anders als "origineel" in v2 belanden.
    static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0 && CGImageSourceGetStatus(source) == .statusComplete
    }

    /// Vertaalt een FileManager-fout naar "geen toegang" (sandbox/TCC) of
    /// "niet gevonden"; alles anders wordt de meegegeven fallback.
    private static func classify(_ error: Error, fallback: ReadError) -> ReadError {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return .accessDenied
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return .notFound
            default: break
            }
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
               underlying.domain == NSPOSIXErrorDomain {
                return classifyPOSIX(underlying.code) ?? fallback
            }
        }
        if nsError.domain == NSPOSIXErrorDomain, let mapped = classifyPOSIX(nsError.code) {
            return mapped
        }
        return fallback
    }

    private static func classifyPOSIX(_ code: Int) -> ReadError? {
        switch Int32(code) {
        case EACCES, EPERM: return .accessDenied
        case ENOENT: return .notFound
        default: return nil
        }
    }
}
