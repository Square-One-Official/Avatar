import Foundation
import SwiftData
import AppKit
import CryptoKit
import ZIPFoundation

/// Library back-up: export every Portrait + its referenced BackgroundPresets
/// into a single .zip ("Avatar-bibliotheek-…zip") and import that file on a
/// different machine. Backgrounds are content-deduped on import so the bundled
/// Mesh presets that ship with every install never end up duplicated.
enum LibraryArchive {
    static let schemaVersion = 1
    static let manifestFilename = "manifest.json"

    enum LibraryArchiveError: LocalizedError {
        case cannotCreateArchive
        case cannotOpenArchive
        case missingManifest
        case unsupportedSchema(Int)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .cannotCreateArchive: return Loc.libraryExportFailedGeneric
            case .cannotOpenArchive:   return Loc.libraryImportNotAnArchive
            case .missingManifest:     return Loc.libraryImportMissingManifest
            case .unsupportedSchema(let v):
                return Loc.libraryImportSchemaTooNew(v)
            case .writeFailed(let m):  return m
            }
        }
    }

    // MARK: - Manifest

    struct Manifest: Codable {
        var schemaVersion: Int
        var appVersion: String
        var exportedAt: Date
        var portraits: [PortraitRecord]
        var backgrounds: [BackgroundRecord]
    }

    struct PortraitRecord: Codable {
        var id: UUID
        var name: String
        var tags: String
        var createdAt: Date
        var updatedAt: Date

        var cutoutPath: String?
        var preRetouchPath: String?
        var preFillBodyPath: String?

        var faceRectX: Double; var faceRectY: Double
        var faceRectW: Double; var faceRectH: Double
        var eyeCenterX: Double; var eyeCenterY: Double
        var interEyeDistance: Double
        var bodyBottomY: Double

        var offsetX: Double; var offsetY: Double; var scale: Double

        var backgroundPresetID: UUID?

        var adjExposure: Double
        var adjContrast: Double
        var adjBrightness: Double
        var adjSaturation: Double
        var adjHue: Double
        var adjTemperature: Double
        var adjTint: Double
        var adjHighlights: Double
        var adjShadows: Double
        var adjWhites: Double
        var adjBlacks: Double

        var isMagicRetouched: Bool
        var cutoutUsedMagic: Bool
        var isFillBodyApplied: Bool

        var preFillFaceRectX: Double; var preFillFaceRectY: Double
        var preFillFaceRectW: Double; var preFillFaceRectH: Double
        var preFillEyeCenterX: Double; var preFillEyeCenterY: Double
        var preFillInterEyeDistance: Double
        var preFillBodyBottomY: Double
        var preFillOffsetX: Double; var preFillOffsetY: Double
        var preFillScale: Double
    }

    struct BackgroundRecord: Codable {
        var id: UUID
        var name: String
        /// "image" or "color"; mirrors `BackgroundPreset.kindRaw`.
        var kind: String
        var imagePath: String?
        var colorR: Double
        var colorG: Double
        var colorB: Double
        var colorA: Double
        var isDefault: Bool
        var createdAt: Date
    }

    // MARK: - Conflict resolution

    enum Resolution {
        /// Keep the existing portrait, skip the imported one.
        case skipExisting
        /// Replace the existing portrait with the imported version (same UUID).
        case overwriteExisting
        /// Always assign a fresh UUID to imported portraits, never overwrite —
        /// the safe default for sharing libraries between users.
        case alwaysNew
    }

    struct ImportPreview: Identifiable {
        let id = UUID()
        let manifest: Manifest
        let archiveURL: URL
        /// Number of imported portraits whose UUID is already in the local library.
        let conflictCount: Int
        /// Number of imported portraits with a brand-new UUID.
        let newCount: Int
    }

    struct ImportSummary {
        var added: Int = 0
        var overwritten: Int = 0
        var skipped: Int = 0
        var backgroundsAdded: Int = 0
        var backgroundsReused: Int = 0
    }

    // MARK: - Export

    /// Builds a zip back-up of `portraits` and the `BackgroundPreset`s they
    /// reference. Excludes presets that aren't pointed at by any portrait —
    /// the user's full background catalog is large enough that copying it
    /// wholesale would bloat the archive without preserving anything the
    /// recipient can use. Throws on disk-full / permission errors.
    static func export(portraits: [Portrait],
                       backgrounds: [BackgroundPreset],
                       to destination: URL) throws {
        let referenced = Set(portraits.compactMap(\.backgroundPresetID))
        let bgsToExport = backgrounds.filter { referenced.contains($0.id) }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("AvatarLibExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        // Backgrounds: only image kind needs a payload file.
        var bgRecords: [BackgroundRecord] = []
        let backgroundsDir = staging.appendingPathComponent("backgrounds", isDirectory: true)
        var backgroundsDirCreated = false
        for bg in bgsToExport {
            var imagePath: String? = nil
            if bg.kind == .image, let data = bg.imageData, !data.isEmpty {
                if !backgroundsDirCreated {
                    try FileManager.default.createDirectory(at: backgroundsDir, withIntermediateDirectories: true)
                    backgroundsDirCreated = true
                }
                let rel = "backgrounds/\(bg.id.uuidString).png"
                try data.write(to: staging.appendingPathComponent(rel))
                imagePath = rel
            }
            bgRecords.append(BackgroundRecord(
                id: bg.id, name: bg.name, kind: bg.kindRaw,
                imagePath: imagePath,
                colorR: bg.colorR, colorG: bg.colorG, colorB: bg.colorB, colorA: bg.colorA,
                isDefault: bg.isDefault, createdAt: bg.createdAt
            ))
        }

        // Portraits + their PNG payloads (cutout + optional undo snapshots).
        var pRecords: [PortraitRecord] = []
        for p in portraits {
            let portraitDir = staging.appendingPathComponent("portraits/\(p.id.uuidString)", isDirectory: true)
            var portraitDirCreated = false
            func write(_ data: Data?, name: String) throws -> String? {
                guard let data, !data.isEmpty else { return nil }
                if !portraitDirCreated {
                    try FileManager.default.createDirectory(at: portraitDir, withIntermediateDirectories: true)
                    portraitDirCreated = true
                }
                let rel = "portraits/\(p.id.uuidString)/\(name)"
                try data.write(to: staging.appendingPathComponent(rel))
                return rel
            }
            let cutoutPath = try write(p.cutoutPNG, name: "cutout.png")
            let preRetouchPath = try write(p.preRetouchPNG, name: "preRetouch.png")
            let preFillBodyPath = try write(p.preFillBodyPNG, name: "preFillBody.png")

            pRecords.append(PortraitRecord(
                id: p.id, name: p.name, tags: p.tags,
                createdAt: p.createdAt, updatedAt: p.updatedAt,
                cutoutPath: cutoutPath, preRetouchPath: preRetouchPath, preFillBodyPath: preFillBodyPath,
                faceRectX: p.faceRectX, faceRectY: p.faceRectY,
                faceRectW: p.faceRectW, faceRectH: p.faceRectH,
                eyeCenterX: p.eyeCenterX, eyeCenterY: p.eyeCenterY,
                interEyeDistance: p.interEyeDistance, bodyBottomY: p.bodyBottomY,
                offsetX: p.offsetX, offsetY: p.offsetY, scale: p.scale,
                backgroundPresetID: p.backgroundPresetID,
                adjExposure: p.adjExposure, adjContrast: p.adjContrast,
                adjBrightness: p.adjBrightness, adjSaturation: p.adjSaturation,
                adjHue: p.adjHue, adjTemperature: p.adjTemperature, adjTint: p.adjTint,
                adjHighlights: p.adjHighlights, adjShadows: p.adjShadows,
                adjWhites: p.adjWhites, adjBlacks: p.adjBlacks,
                isMagicRetouched: p.isMagicRetouched,
                cutoutUsedMagic: p.cutoutUsedMagic,
                isFillBodyApplied: p.isFillBodyApplied,
                preFillFaceRectX: p.preFillFaceRectX, preFillFaceRectY: p.preFillFaceRectY,
                preFillFaceRectW: p.preFillFaceRectW, preFillFaceRectH: p.preFillFaceRectH,
                preFillEyeCenterX: p.preFillEyeCenterX, preFillEyeCenterY: p.preFillEyeCenterY,
                preFillInterEyeDistance: p.preFillInterEyeDistance,
                preFillBodyBottomY: p.preFillBodyBottomY,
                preFillOffsetX: p.preFillOffsetX, preFillOffsetY: p.preFillOffsetY,
                preFillScale: p.preFillScale
            ))
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let manifest = Manifest(
            schemaVersion: schemaVersion, appVersion: appVersion,
            exportedAt: Date(), portraits: pRecords, backgrounds: bgRecords
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: staging.appendingPathComponent(manifestFilename))

        // Replace any existing file at the destination.
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.zipItem(
            at: staging,
            to: destination,
            shouldKeepParent: false,
            compressionMethod: .deflate
        )
    }

    // MARK: - Import

    /// Reads the manifest from the archive without inserting anything into
    /// SwiftData. Drives the conflict-resolution sheet (counts of new vs.
    /// already-present portraits).
    @MainActor
    static func preview(from archiveURL: URL,
                        context: ModelContext) throws -> ImportPreview {
        let manifest = try readManifest(from: archiveURL)
        if manifest.schemaVersion > schemaVersion {
            throw LibraryArchiveError.unsupportedSchema(manifest.schemaVersion)
        }
        let existing = (try? context.fetch(FetchDescriptor<Portrait>())) ?? []
        let existingIDs = Set(existing.map(\.id))
        let importedIDs = Set(manifest.portraits.map(\.id))
        let conflicts = importedIDs.intersection(existingIDs).count
        let news = importedIDs.count - conflicts
        return ImportPreview(manifest: manifest,
                             archiveURL: archiveURL,
                             conflictCount: conflicts,
                             newCount: news)
    }

    /// Performs the import using the user's chosen `Resolution`. Background
    /// presets are content-deduped (image hash / RGBA equality) regardless of
    /// resolution — defaults bundled with the app and identical user-added
    /// images get reused so the picker doesn't grow duplicates.
    @MainActor
    static func performImport(preview: ImportPreview,
                              resolution: Resolution,
                              context: ModelContext) throws -> ImportSummary {
        // Stage extraction once so we don't re-open the archive per-asset.
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("AvatarLibImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.unzipItem(at: preview.archiveURL, to: staging)

        var summary = ImportSummary()

        // Background dedup: build a map from manifest IDs to local IDs.
        let existingBgs = (try? context.fetch(FetchDescriptor<BackgroundPreset>())) ?? []
        let existingHashes: [String: BackgroundPreset] = Dictionary(uniqueKeysWithValues:
            existingBgs.compactMap { bg -> (String, BackgroundPreset)? in
                guard bg.kind == .image, let data = bg.imageData else { return nil }
                return (Self.sha256Hex(data), bg)
            })
        var bgMap: [UUID: UUID] = [:]

        for rec in preview.manifest.backgrounds {
            if rec.kind == "image", let imagePath = rec.imagePath {
                let fileURL = staging.appendingPathComponent(imagePath)
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                let hash = Self.sha256Hex(data)
                if let match = existingHashes[hash] {
                    bgMap[rec.id] = match.id
                    summary.backgroundsReused += 1
                    continue
                }
                // Fresh UUID: avoids colliding with any local preset that
                // happens to share the manifest's UUID by coincidence (very
                // unlikely, but cheap to defend against).
                let bg = BackgroundPreset(
                    id: UUID(), name: rec.name, kind: .image, imageData: data,
                    color: (rec.colorR, rec.colorG, rec.colorB, rec.colorA),
                    isDefault: false
                )
                context.insert(bg)
                bgMap[rec.id] = bg.id
                summary.backgroundsAdded += 1
            } else if rec.kind == "color" {
                if let match = existingBgs.first(where: { Self.colorMatches($0, rec) }) {
                    bgMap[rec.id] = match.id
                    summary.backgroundsReused += 1
                } else {
                    let bg = BackgroundPreset(
                        id: UUID(), name: rec.name, kind: .color,
                        color: (rec.colorR, rec.colorG, rec.colorB, rec.colorA),
                        isDefault: false
                    )
                    context.insert(bg)
                    bgMap[rec.id] = bg.id
                    summary.backgroundsAdded += 1
                }
            }
        }

        // Portraits.
        let existingPortraits = (try? context.fetch(FetchDescriptor<Portrait>())) ?? []
        let existingPortraitsByID = Dictionary(uniqueKeysWithValues: existingPortraits.map { ($0.id, $0) })

        for rec in preview.manifest.portraits {
            let exists = existingPortraitsByID[rec.id] != nil
            if exists {
                switch resolution {
                case .skipExisting:
                    summary.skipped += 1
                    continue
                case .overwriteExisting:
                    if let old = existingPortraitsByID[rec.id] {
                        context.delete(old)
                    }
                    insert(record: rec, useNewUUID: false, bgMap: bgMap, staging: staging, context: context)
                    summary.overwritten += 1
                case .alwaysNew:
                    insert(record: rec, useNewUUID: true, bgMap: bgMap, staging: staging, context: context)
                    summary.added += 1
                }
            } else {
                insert(record: rec,
                       useNewUUID: resolution == .alwaysNew,
                       bgMap: bgMap, staging: staging, context: context)
                summary.added += 1
            }
        }

        try context.save()
        return summary
    }

    // MARK: - Helpers

    private static func readManifest(from archiveURL: URL) throws -> Manifest {
        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .read)
        } catch {
            throw LibraryArchiveError.cannotOpenArchive
        }
        guard let entry = archive[manifestFilename] else {
            throw LibraryArchiveError.missingManifest
        }
        var buffer = Data()
        _ = try archive.extract(entry) { chunk in buffer.append(chunk) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Manifest.self, from: buffer)
    }

    @MainActor
    private static func insert(record rec: PortraitRecord,
                               useNewUUID: Bool,
                               bgMap: [UUID: UUID],
                               staging: URL,
                               context: ModelContext) {
        let portrait = Portrait(
            id: useNewUUID ? UUID() : rec.id,
            name: rec.name,
            tags: rec.tags,
            cutoutPNG: nil,
            originalImageData: nil,
            faceRect: CGRect(x: rec.faceRectX, y: rec.faceRectY, width: rec.faceRectW, height: rec.faceRectH),
            eyeCenter: rec.interEyeDistance > 0
                ? CGPoint(x: rec.eyeCenterX, y: rec.eyeCenterY)
                : nil,
            interEyeDistance: rec.interEyeDistance,
            bodyBottomY: rec.bodyBottomY,
            offsetX: rec.offsetX, offsetY: rec.offsetY, scale: rec.scale,
            backgroundPresetID: rec.backgroundPresetID.flatMap { bgMap[$0] }
        )
        // PNG payloads
        if let p = rec.cutoutPath, let data = try? Data(contentsOf: staging.appendingPathComponent(p)) {
            portrait.cutoutPNG = data
        }
        if let p = rec.preRetouchPath, let data = try? Data(contentsOf: staging.appendingPathComponent(p)) {
            portrait.preRetouchPNG = data
        }
        if let p = rec.preFillBodyPath, let data = try? Data(contentsOf: staging.appendingPathComponent(p)) {
            portrait.preFillBodyPNG = data
        }
        portrait.adjExposure = rec.adjExposure
        portrait.adjContrast = rec.adjContrast
        portrait.adjBrightness = rec.adjBrightness
        portrait.adjSaturation = rec.adjSaturation
        portrait.adjHue = rec.adjHue
        portrait.adjTemperature = rec.adjTemperature
        portrait.adjTint = rec.adjTint
        portrait.adjHighlights = rec.adjHighlights
        portrait.adjShadows = rec.adjShadows
        portrait.adjWhites = rec.adjWhites
        portrait.adjBlacks = rec.adjBlacks
        portrait.isMagicRetouched = rec.isMagicRetouched
        portrait.cutoutUsedMagic = rec.cutoutUsedMagic
        portrait.isFillBodyApplied = rec.isFillBodyApplied
        portrait.preFillFaceRectX = rec.preFillFaceRectX
        portrait.preFillFaceRectY = rec.preFillFaceRectY
        portrait.preFillFaceRectW = rec.preFillFaceRectW
        portrait.preFillFaceRectH = rec.preFillFaceRectH
        portrait.preFillEyeCenterX = rec.preFillEyeCenterX
        portrait.preFillEyeCenterY = rec.preFillEyeCenterY
        portrait.preFillInterEyeDistance = rec.preFillInterEyeDistance
        portrait.preFillBodyBottomY = rec.preFillBodyBottomY
        portrait.preFillOffsetX = rec.preFillOffsetX
        portrait.preFillOffsetY = rec.preFillOffsetY
        portrait.preFillScale = rec.preFillScale
        portrait.createdAt = rec.createdAt
        portrait.updatedAt = rec.updatedAt
        context.insert(portrait)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 1/255 ≈ 0.004 tolerance handles float rounding when colors round-trip
    /// through ColorPicker → sRGB components → JSON → back.
    private static func colorMatches(_ bg: BackgroundPreset, _ rec: BackgroundRecord) -> Bool {
        guard bg.kind == .color else { return false }
        let eps = 0.004
        return abs(bg.colorR - rec.colorR) < eps
            && abs(bg.colorG - rec.colorG) < eps
            && abs(bg.colorB - rec.colorB) < eps
            && abs(bg.colorA - rec.colorA) < eps
    }
}
