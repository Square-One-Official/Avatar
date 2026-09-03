// E13.2 — lezer voor Aaavatar 1-bibliotheek-back-ups (.zip).
//
// v1 exporteert zijn bibliotheek via `LibraryArchive.export` (Avatar/Services/
// LibraryArchive.swift): een zip met `manifest.json` (schemaVersion 1, ISO-8601-
// datums) + `portraits/<uuid>/cutout.png` (+ optionele undo-snapshots) +
// `backgrounds/<uuid>.png`. Dit is de MIGRATIEWEG naar 2.0: beide apps zijn
// gesandboxt onder verschillende bundle-ids, dus v2 kán v1's live SwiftData-
// store niet stil lezen — de gebruiker exporteert in v1 en kiest het zip-bestand
// in v2 (user-selected read valt binnen de sandbox-entitlement).
//
// Bewust READ-ONLY en tolerant: we decoderen alleen de velden die v2 nodig
// heeft (identiteit, naam, datums, cutout-pad) en negeren de rest van het
// manifest — v1 is bevroren, maar een oudere v1-export mist mogelijk latere
// velden en mag daarop niet stukgaan.

import Foundation
import ZIPFoundation

public enum V1LibraryArchive {

    /// Eén portret uit de back-up, klaar om te importeren.
    public struct PortraitPayload: Sendable {
        /// v1's UUID — de dedup-sleutel voor idempotente her-import.
        public let id: UUID
        public let name: String
        /// v1's vrije-tekst-tags. v2 heeft geen tags-veld; de call site beslist
        /// wat hiermee gebeurt (nu: bewaren als rol wanneer het er één lijkt te
        /// zijn is aan de gebruiker — we geven 'm alleen dóór).
        public let tags: String
        public let createdAt: Date
        public let updatedAt: Date
        /// De vrijstaande cutout (PNG met alpha) — het enige beeld dat de
        /// back-up van het portret bevat; v1 archiveert de originele foto niet.
        public let cutoutPNG: Data

        public init(id: UUID, name: String, tags: String, createdAt: Date, updatedAt: Date, cutoutPNG: Data) {
            self.id = id
            self.name = name
            self.tags = tags
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.cutoutPNG = cutoutPNG
        }
    }

    public struct Library: Sendable {
        public let schemaVersion: Int
        public let appVersion: String
        public let exportedAt: Date
        public let portraits: [PortraitPayload]
        /// Records zonder cutout-payload (lege/ontbrekende PNG) — benoemd zodat
        /// de UI eerlijk kan melden wat er is overgeslagen i.p.v. stil te snoeien.
        public let skippedWithoutCutout: Int

        public init(schemaVersion: Int, appVersion: String, exportedAt: Date, portraits: [PortraitPayload], skippedWithoutCutout: Int) {
            self.schemaVersion = schemaVersion
            self.appVersion = appVersion
            self.exportedAt = exportedAt
            self.portraits = portraits
            self.skippedWithoutCutout = skippedWithoutCutout
        }
    }

    public enum ReadError: LocalizedError, Equatable {
        case cannotOpenArchive
        case missingManifest
        case malformedManifest
        /// De export komt van een NIEUWERE v1 dan wij kennen. Kan in de praktijk
        /// niet meer gebeuren (v1 is bevroren op schema 1) — maar als het tóch
        /// gebeurt is weigeren eerlijker dan half importeren.
        case unsupportedSchema(Int)

        public var errorDescription: String? {
            switch self {
            case .cannotOpenArchive: return "That file isn't a readable backup archive."
            case .missingManifest: return "The archive is missing its manifest — is this an Aaavatar backup?"
            case .malformedManifest: return "The backup manifest couldn't be read."
            case .unsupportedSchema(let v): return "This backup uses a newer format (v\(v)) than this app understands."
            }
        }
    }

    /// Hoogste manifest-schema dat we kennen. v1 is bevroren; dit is 1.
    public static let supportedSchemaVersion = 1

    // Tolerante spiegel van v1's manifest: alléén de velden die wij gebruiken.
    private struct Manifest: Decodable {
        var schemaVersion: Int
        var appVersion: String?
        var exportedAt: Date?
        var portraits: [Record]

        struct Record: Decodable {
            var id: UUID
            var name: String
            var tags: String?
            var createdAt: Date
            var updatedAt: Date
            var cutoutPath: String?
        }
    }

    /// Leest een v1-back-up volledig in het geheugen. Bibliotheken zijn
    /// cutout-PNG's (enkele MB per stuk); v1's eigen import doet hetzelfde.
    public static func read(from url: URL) throws -> Library {
        guard let archive = try? Archive(url: url, accessMode: .read) else {
            throw ReadError.cannotOpenArchive
        }

        func extract(_ path: String) -> Data? {
            guard let entry = archive[path] else { return nil }
            var data = Data()
            // ZIPFoundation levert per chunk; een corrupt entry gooit — dat
            // behandelen we als "geen payload" i.p.v. de hele import te breken.
            guard (try? archive.extract(entry, consumer: { data.append($0) })) != nil else { return nil }
            return data
        }

        guard let manifestData = extract("manifest.json") else {
            throw ReadError.missingManifest
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(Manifest.self, from: manifestData) else {
            throw ReadError.malformedManifest
        }
        guard manifest.schemaVersion <= supportedSchemaVersion else {
            throw ReadError.unsupportedSchema(manifest.schemaVersion)
        }

        var portraits: [PortraitPayload] = []
        var skipped = 0
        for record in manifest.portraits {
            guard let path = record.cutoutPath, let png = extract(path), !png.isEmpty else {
                skipped += 1
                continue
            }
            portraits.append(PortraitPayload(
                id: record.id,
                name: record.name,
                tags: record.tags ?? "",
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                cutoutPNG: png
            ))
        }

        return Library(
            schemaVersion: manifest.schemaVersion,
            appVersion: manifest.appVersion ?? "?",
            exportedAt: manifest.exportedAt ?? .distantPast,
            portraits: portraits,
            skippedWithoutCutout: skipped
        )
    }
}
