import Foundation
import CryptoKit

/// User preference for the Pro Magic Cutout feature. The cutout itself runs
/// server-side via Replicate (`851-labs/background-remover`); this class only
/// persists whether the toggle is on. The processing path is gated by both
/// `ProEntitlement.canUseProCutout` and `enabled` — see
/// `ImportFlow.shouldUseMagicCutout`.
@MainActor
@Observable
final class MagicCutoutPreferences {

    private static let prefKey = "magicCutoutEnabled"

    /// Default-on so new users see Pro cutout quality on their very first
    /// import (server enforces the free-trial cap). Existing users who
    /// already toggled it off keep their choice — `register(defaults:)`
    /// only fills in the value when the key is missing.
    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.prefKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.prefKey) }
    }

    init() {
        UserDefaults.standard.register(defaults: [Self.prefKey: true])
        ModelManager.removeLegacyLocalModel()
    }
}

// MARK: - Downloadable matting model (BiRefNet_lite-matting)

/// State of the optional downloadable matting model. Drives the Settings
/// engine row's UI and the import-time fallback decision.
enum LocalModelState: Sendable, Equatable {
    /// No cached copy on disk (and no active download).
    case notDownloaded
    /// Download in progress; `progress` is `[0, 1]`. Updated frequently
    /// during the URLSession download — Settings reads this for the
    /// progress bar and re-renders.
    case downloading(progress: Double)
    /// Cached, SHA-verified, ready to use. URL points at the on-disk
    /// `.mlmodelc` directory under Application Support.
    case ready(URL)
    /// Last attempt failed. Carries the localized error string for the
    /// banner; user can retry via the Settings button.
    case failed(String)

    static func == (lhs: LocalModelState, rhs: LocalModelState) -> Bool {
        switch (lhs, rhs) {
        case (.notDownloaded, .notDownloaded): return true
        case (.downloading(let a), .downloading(let b)): return a == b
        case (.ready(let a), .ready(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

/// Errors surfaced from the download / verify / install pipeline. Mapped
/// to localized strings at the call site so the user sees something
/// actionable rather than a hex code.
enum ModelManagerError: Error {
    /// HTTP non-2xx, network failure, or SHA mismatch on the downloaded
    /// payload. SHA mismatch is the security-critical case: refuse to
    /// install a tampered or partially-downloaded zip rather than letting
    /// the inference path crash on malformed CoreML.
    case downloadFailed(String)
    case verificationFailed(expected: String, got: String)
    case unzipFailed(String)
    case installFailed(String)
}

/// Manages the optional downloadable BiRefNet_lite-matting model. Single
/// instance owned by `AppState`. UI surfaces (Settings → Privacy & AI
/// engine row) read `state` and call `download(force:)` /
/// `removeDownloaded()`. The cutout pipeline reads `cachedModelURL()` to
/// decide whether to use the downloaded engine or fall back to Apple
/// Vision V2.
///
/// Persistence layout (sandbox container):
/// ```
/// ~/Library/Containers/<bundle>/Data/Library/Application Support/Avatar/Models/
///   ├── birefnet-lite-matting.mlmodelc/   ← compiled, runtime-ready
///   └── .model_version                     ← "1\n" (matches `modelVersion`)
/// ```
///
/// Bumping `modelVersion` invalidates older cached copies on next launch.
/// The legacy V4 BiRefNet model (250 MB, removed in build 6) is also
/// cleaned up via `removeLegacyLocalModel()` for users updating from a
/// pre-pivot build.
@MainActor
@Observable
final class ModelManager {

    // MARK: - Manifest (update after each release)

    /// GitHub Releases URL of the matting model `.mlmodelc.zip`. Tag is
    /// part of the path and acts as a permanent version pin — never
    /// reuse a tag, always bump (`-v2`, `-v3`) when swapping models or
    /// reconverting. The release asset stays alive even after the tag
    /// is deleted, but pinning to the tag makes accidental cache
    /// invalidation impossible.
    ///
    /// History: planned to ship BiRefNet_lite-matting, but coremltools
    /// can't convert `torchvision::deform_conv2d`. Pivoted to IS-Net
    /// (DIS) per the documented runner-up — Apache 2.0, prebuilt
    /// CoreML from `john-rocky/CoreML-Models`. The on-disk model name
    /// stays generic (`matting-model.mlmodelc`) so future swaps don't
    /// touch this constant.
    static let modelURL = URL(string:
        "https://github.com/thierrzz/Avatar/releases/download/" +
        "models/matting-v1/matting-model.mlmodelc.zip"
    )!

    /// Hex SHA-256 of the `matting-model.mlmodelc.zip` — emitted by
    /// `scripts/convert_ormbg_to_coreml.py` and saved alongside the zip
    /// at `build/matting/matting-model.mlmodelc.zip.sha256`. Verified
    /// after every download; mismatch refuses to install (the CoreML
    /// loader would crash on a tampered or partially-downloaded
    /// payload, so the SHA gate is the only guard before the runtime).
    ///
    /// Bump on every model swap. Always paste exactly what the script
    /// prints — do not regenerate the hash from a hand-edited zip.
    static let expectedSHA256 = "7b0100451bf82a87b3c5fc50c7d4c79b4f6666575ac789701b1e8eacc008d347"

    /// Bump on every model swap. `.model_version` sidecar in the install
    /// dir compares against this to decide whether to wipe older caches
    /// at launch.
    static let modelVersion = "1"

    /// On-disk name of the compiled model directory. Must match the zip's
    /// inner directory name produced by the repackaging script. Kept
    /// engine-agnostic so swapping IS-Net for a future better model
    /// doesn't require any Swift changes — only a new release upload.
    static let modelDirName = "matting-model.mlmodelc"

    // MARK: - Observable state

    /// Live state of the cached model + any active download. Settings
    /// reads this for the engine-row UI; ImportFlow reads it (via
    /// `cachedModelURL()`) to decide between downloaded vs Apple Vision.
    private(set) var state: LocalModelState = .notDownloaded

    @ObservationIgnored
    private var activeTask: Task<Void, Never>?

    // MARK: - Lifecycle

    init() {
        // Resolve the cached state from disk on construction. Wrong-version
        // copies are wiped here so the user sees a clean "not downloaded"
        // state instead of a stale model that will fail later.
        Self.removeLegacyLocalModel()
        if let url = Self.cachedModelURLOnDisk(versionMatches: true) {
            state = .ready(url)
        } else {
            // Stale-version copies linger after a `modelVersion` bump until
            // we explicitly clean them up. Best-effort wipe here keeps the
            // disk footprint honest with what the UI claims.
            Self.removeStaleVersionedCache()
            state = .notDownloaded
        }
    }

    // MARK: - Public API

    /// Returns the on-disk URL to the compiled `.mlmodelc` if the cached
    /// copy matches the current `modelVersion`. Used by `ImageProcessor`
    /// to decide whether the downloaded engine is available right now.
    /// Synchronous so the cutout pipeline can branch without an `await`.
    func cachedModelURL() -> URL? {
        if case .ready(let url) = state { return url }
        return nil
    }

    /// Kicks off a download if one isn't in progress. Returns immediately;
    /// progress is published via `state`. Calling while a download is
    /// already running is a no-op. `force=true` re-downloads even if a
    /// cached copy exists (used by the Settings "Re-download" affordance
    /// after a SHA mismatch).
    func download(force: Bool = false) {
        if !force, case .ready = state { return }
        if case .downloading = state { return }
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.runDownload()
        }
    }

    /// Removes the cached model and resets state. Cancels any in-flight
    /// download. Errors are swallowed — if the disk write fails the user
    /// can re-trigger from Settings.
    func removeDownloaded() {
        activeTask?.cancel()
        activeTask = nil
        do {
            let dir = Self.modelInstallDirectory()
            if FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.removeItem(at: dir)
            }
            let sidecar = Self.versionSidecarURL()
            if FileManager.default.fileExists(atPath: sidecar.path) {
                try FileManager.default.removeItem(at: sidecar)
            }
        } catch {
            dlog("[ModelManager] remove failed: \(error)")
        }
        state = .notDownloaded
    }

    // MARK: - Download pipeline

    private func runDownload() async {
        state = .downloading(progress: 0)
        do {
            let zipURL = try await downloadToTemp { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .downloading = self.state {
                        self.state = .downloading(progress: progress)
                    }
                }
            }
            try await verifyAndInstall(zipURL: zipURL)
            // Successful install — `state` is already `.ready` from inside
            // `verifyAndInstall`. Nothing else to do.
        } catch is CancellationError {
            // User cancelled (e.g. clicked Remove mid-download). Treat as
            // a clean revert to "not downloaded" rather than a failure.
            state = .notDownloaded
        } catch {
            dlog("[ModelManager] download failed: \(error)")
            state = .failed(localizedMessage(for: error))
        }
    }

    private func downloadToTemp(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let session = URLSession(configuration: .ephemeral)
        let (location, response) = try await session.download(
            for: URLRequest(url: Self.modelURL),
            delegate: ProgressDelegate(progress: progress)
        )
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ModelManagerError.downloadFailed("HTTP \(code)")
        }
        // URLSession writes to a temp location that disappears once we
        // return — copy to a stable temp path we control before verify
        // and unzip. Using `.itemReplacementDirectory` keeps the file on
        // the same volume so `FileManager.replaceItem` can be atomic.
        let tmpDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: Self.modelInstallDirectory(),
            create: true
        )
        let stable = tmpDir.appendingPathComponent("birefnet-download.zip")
        if FileManager.default.fileExists(atPath: stable.path) {
            try? FileManager.default.removeItem(at: stable)
        }
        try FileManager.default.moveItem(at: location, to: stable)
        return stable
    }

    private func verifyAndInstall(zipURL: URL) async throws {
        // Hash on a background thread — the file is up to ~100 MB and
        // SHA-256 is CPU-bound. Keeping the main actor responsive during
        // a brief but visible operation matters for the Settings UI.
        let actualSHA = try await Task.detached(priority: .userInitiated) {
            try Self.sha256(of: zipURL)
        }.value

        if actualSHA != Self.expectedSHA256 {
            // Refuse to install a tampered or partially-downloaded zip.
            // The CoreML loader could otherwise crash on malformed input,
            // and a SHA mismatch is the only signal we have that the
            // download is bad before the model runs.
            try? FileManager.default.removeItem(at: zipURL)
            throw ModelManagerError.verificationFailed(
                expected: Self.expectedSHA256, got: actualSHA
            )
        }

        let installDir = Self.modelInstallDirectory()
        try FileManager.default.createDirectory(
            at: installDir.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Atomic install: unzip into a sibling temp dir, then rename.
        // Avoids leaving a half-extracted .mlmodelc on disk if the unzip
        // is interrupted (sandbox crash, machine sleep) — next launch
        // would otherwise see a corrupt directory and try to load it.
        let tmpExtract = installDir.deletingLastPathComponent()
            .appendingPathComponent(".birefnet-extract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpExtract, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpExtract) }

        try Self.unzip(zipURL, to: tmpExtract)

        // The zip's inner directory must match `modelDirName`.
        let extracted = tmpExtract.appendingPathComponent(Self.modelDirName)
        guard FileManager.default.fileExists(atPath: extracted.path) else {
            throw ModelManagerError.unzipFailed(
                "expected \(Self.modelDirName) inside zip"
            )
        }

        // Atomic swap: replace any existing install with the freshly-
        // extracted one. `replaceItem` does the right thing across the
        // sandbox container (same volume).
        if FileManager.default.fileExists(atPath: installDir.path) {
            try FileManager.default.removeItem(at: installDir)
        }
        try FileManager.default.moveItem(at: extracted, to: installDir)

        try Self.modelVersion.write(
            to: Self.versionSidecarURL(), atomically: true, encoding: .utf8
        )

        // Best-effort cleanup of the original zip; not critical if it
        // lingers in the temp directory — macOS reaps `.itemReplacement`
        // dirs on its own schedule.
        try? FileManager.default.removeItem(at: zipURL)

        state = .ready(installDir)
    }

    // MARK: - Disk paths

    private static func modelsBaseDirectory() -> URL {
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Avatar", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private static func modelInstallDirectory() -> URL {
        modelsBaseDirectory().appendingPathComponent(modelDirName, isDirectory: true)
    }

    private static func versionSidecarURL() -> URL {
        modelsBaseDirectory().appendingPathComponent(".model_version", isDirectory: false)
    }

    /// Returns the install URL only when both the directory exists AND
    /// the version sidecar's contents match the current `modelVersion`.
    /// Anything else returns nil — callers treat that as "not downloaded".
    private static func cachedModelURLOnDisk(versionMatches: Bool) -> URL? {
        let dir = modelInstallDirectory()
        guard FileManager.default.fileExists(atPath: dir.path) else { return nil }
        if versionMatches {
            let sidecar = versionSidecarURL()
            let onDisk = (try? String(contentsOf: sidecar, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard onDisk == modelVersion else { return nil }
        }
        return dir
    }

    private static func removeStaleVersionedCache() {
        let dir = modelInstallDirectory()
        if FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
        let sidecar = versionSidecarURL()
        if FileManager.default.fileExists(atPath: sidecar.path) {
            try? FileManager.default.removeItem(at: sidecar)
        }
    }

    /// Cleans up the legacy V4 BiRefNet model (`BiRefNet.mlmodelc`) shipped
    /// in builds prior to the local-first pivot. Called from
    /// `MagicCutoutPreferences.init` and `ModelManager.init` so any code
    /// path that touches the prefs subsystem clears it.
    static func removeLegacyLocalModel() {
        let modelsDir = modelsBaseDirectory()
        let legacy = modelsDir.appendingPathComponent("BiRefNet.mlmodelc")
        if FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.removeItem(at: legacy)
        }
    }

    // MARK: - SHA-256 + unzip

    /// Streaming SHA-256 to keep peak memory bounded — files are up to
    /// ~100 MB and we'd rather not materialise them all at once. 1 MiB
    /// chunks balance syscall overhead against memory.
    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = CryptoSHA256()
        while autoreleasepool(invoking: { () -> Bool in
            do {
                let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
                if chunk.isEmpty { return false }
                hasher.update(chunk)
                return true
            } catch {
                return false
            }
        }) {}
        return hasher.finalize()
    }

    /// Unzip via the `unzip` BSD utility. Available on every macOS, no
    /// dependency on a Swift archiver, handles `.mlmodelc` directory
    /// trees correctly. Errors when the process exits non-zero.
    nonisolated static func unzip(_ zip: URL, to dir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", zip.path, "-d", dir.path]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                              encoding: .utf8) ?? "unzip exit \(process.terminationStatus)"
            throw ModelManagerError.unzipFailed(err)
        }
    }

    // MARK: - Helpers

    private nonisolated func localizedMessage(for error: Error) -> String {
        switch error {
        case let ModelManagerError.downloadFailed(msg):
            return "Couldn't download (\(msg))"
        case let ModelManagerError.verificationFailed(expected, got):
            return "Integrity check failed. Expected \(String(expected.prefix(8)))…, got \(String(got.prefix(8)))…"
        case let ModelManagerError.unzipFailed(msg):
            return "Couldn't extract model (\(msg))"
        case let ModelManagerError.installFailed(msg):
            return "Couldn't install model (\(msg))"
        default:
            return error.localizedDescription
        }
    }
}

// MARK: - URLSession progress delegate

/// Bridges `URLSessionDownloadDelegate` progress callbacks into a plain
/// closure so `ModelManager` can stay agnostic of the delegate dance.
/// Lives on the URLSession's delegate queue; the closure should hop to
/// MainActor before mutating UI state.
private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progress(p)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The async/await `download(for:delegate:)` API consumes the
        // URL — nothing to do here. Required by the protocol.
    }
}

// MARK: - SHA-256 (CryptoKit wrapper kept tiny so this file stays self-contained)

/// Light wrapper so the streaming hash code reads naturally without
/// importing CryptoKit at every call site.
private struct CryptoSHA256 {
    private var hasher = SHA256()
    mutating func update(_ data: Data) { hasher.update(data: data) }
    func finalize() -> String {
        hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
