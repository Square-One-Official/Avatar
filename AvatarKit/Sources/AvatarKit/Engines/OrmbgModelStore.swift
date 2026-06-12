import CoreML
import CryptoKit
import Foundation
import ZIPFoundation

/// Download, installatie en caching van het ORMBG-matting-model.
///
/// Versimpeld uit v1's `ModelManager`: geen Observation-state-machine en
/// geen voortgangs-UI (dat is een zorg van de 2.0-settings-story), geen
/// versie-sidecar (de versie zit in de mapnaam), wél dezelfde harde
/// SHA-256-gate vóór installatie — de CoreML-loader crasht op een
/// gemanipuleerde of half-gedownloade payload, dus de hash is de enige
/// wacht vóór de runtime.
public actor OrmbgModelStore {
    public static let shared = OrmbgModelStore()

    public struct Manifest: Sendable {
        /// GitHub Releases-URL van de `.mlmodelc.zip`. De tag in het pad is
        /// een permanente versie-pin — nooit een tag hergebruiken, altijd
        /// bumpen bij een model-swap.
        public var zipURL: URL
        /// Hex SHA-256 van de zip, zoals `scripts/convert_ormbg_to_coreml.py`
        /// hem print. Bump bij elke model-swap.
        public var expectedSHA256: String
        /// Bump bij elke model-swap; bepaalt de installatiemap, dus een bump
        /// invalideert oude caches vanzelf.
        public var version: String
        /// Naam van de gecompileerde modelmap in de zip.
        public var modelDirName: String

        public static let current = Manifest(
            zipURL: URL(string: "https://github.com/thierrzz/Avatar/releases/download/"
                + "models/matting-v1/matting-model.mlmodelc.zip")!,
            expectedSHA256: "7b0100451bf82a87b3c5fc50c7d4c79b4f6666575ac789701b1e8eacc008d347",
            version: "1",
            modelDirName: "matting-model.mlmodelc"
        )
    }

    public enum Failure: Error, Equatable {
        /// SHA-256 van de download wijkt af van het manifest.
        case checksumMismatch(expected: String, actual: String)
        /// De zip bevatte de verwachte modelmap niet.
        case malformedArchive
    }

    private let manifest: Manifest
    private let baseDirectory: URL
    private var activeDownload: Task<URL, Error>?
    private var loadedModel: (url: URL, model: MLModel)?

    /// `baseDirectory` is injecteerbaar voor tests; default is
    /// `Application Support/AvatarKit/Models/ormbg/`.
    public init(manifest: Manifest = .current, baseDirectory: URL? = nil) {
        self.manifest = manifest
        self.baseDirectory = baseDirectory ?? Self.defaultBaseDirectory()
    }

    private static func defaultBaseDirectory() -> URL {
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("AvatarKit", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("ormbg", isDirectory: true)
    }

    private nonisolated var installDirectory: URL {
        installBase.appendingPathComponent("v\(installVersion)", isDirectory: true)
    }

    // nonisolated toegang tot de twee let-properties die `installedModelURL`
    // nodig heeft. (Stored lets op een actor zijn nonisolated leesbaar; deze
    // computed helpers houden dat expliciet.)
    private nonisolated var installBase: URL { baseDirectory }
    private nonisolated var installVersion: String { manifest.version }
    private nonisolated var installModelDirName: String { manifest.modelDirName }

    /// URL van het geïnstalleerde model, of nil als het (in deze versie)
    /// niet op schijf staat. Disk-check zonder actor-hop zodat
    /// `OrmbgEngine.isAvailable` goedkoop blijft.
    public nonisolated func installedModelURL() -> URL? {
        let url = installDirectory.appendingPathComponent(installModelDirName, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else { return nil }
        return url
    }

    /// Downloadt en installeert het model. Idempotent: al geïnstalleerd →
    /// geeft direct de bestaande URL terug; een lopende download wordt
    /// gedeeld door gelijktijdige aanroepers.
    public func download() async throws -> URL {
        if let installed = installedModelURL() { return installed }
        if let active = activeDownload { return try await active.value }

        let manifest = self.manifest
        let installDirectory = self.installDirectory
        let task = Task<URL, Error>.detached(priority: .userInitiated) {
            try await Self.fetchAndInstall(manifest: manifest, installDirectory: installDirectory)
        }
        activeDownload = task
        defer { activeDownload = nil }
        return try await task.value
    }

    /// Verwijdert alle geïnstalleerde versies en de model-cache.
    public func removeInstalled() throws {
        loadedModel = nil
        let base = installBase
        if FileManager.default.fileExists(atPath: base.path) {
            try FileManager.default.removeItem(at: base)
        }
    }

    /// Laadt het geïnstalleerde model (of hergebruikt de cache — laden kost
    /// ~200 ms, inference niet; her-importen mag die cold-start maar één
    /// keer betalen). Gooit `CutoutEngineError.unavailable` zonder install.
    func model() async throws -> MLModel {
        guard let url = installedModelURL() else {
            throw CutoutEngineError.unavailable(.ormbg)
        }
        if let cached = loadedModel, cached.url == url { return cached.model }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model = try MLModel(contentsOf: url, configuration: configuration)
        loadedModel = (url, model)
        return model
    }

    // MARK: - Download + installatie (synchroon, draait detached)

    private static func fetchAndInstall(manifest: Manifest, installDirectory: URL) async throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("ormbg-download-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        // 1. Download de zip — gestreamd naar schijf, niet via Data in
        //    het geheugen.
        let zipURL = scratch.appendingPathComponent("model.zip")
        let (tempFile, _) = try await URLSession.shared.download(from: manifest.zipURL)
        try fm.moveItem(at: tempFile, to: zipURL)

        // 2. SHA-256-gate.
        let actual = try sha256(of: zipURL)
        guard actual == manifest.expectedSHA256 else {
            throw Failure.checksumMismatch(expected: manifest.expectedSHA256, actual: actual)
        }

        // 3. Uitpakken en de modelmap atomisch op zijn plek zetten.
        let extractDir = scratch.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try fm.unzipItem(at: zipURL, to: extractDir)
        let extractedModel = extractDir.appendingPathComponent(manifest.modelDirName, isDirectory: true)
        guard fm.fileExists(atPath: extractedModel.path) else {
            throw Failure.malformedArchive
        }

        // Oude versies opruimen (versie zit in de mapnaam, dus alles onder
        // de base behalve de doelmap is per definitie staal).
        let base = installDirectory.deletingLastPathComponent()
        if let stale = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) {
            for url in stale where url.lastPathComponent != installDirectory.lastPathComponent {
                try? fm.removeItem(at: url)
            }
        }
        try fm.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        let destination = installDirectory.appendingPathComponent(manifest.modelDirName, isDirectory: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: extractedModel, to: destination)
        return destination
    }

    /// Streamende SHA-256 zodat de zip (~45 MB) niet twee keer in het
    /// geheugen hoeft.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
