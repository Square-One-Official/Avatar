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

// MARK: - Downloadable matting model (ORMBG)

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

/// Manages the optional downloadable matting model (currently ORMBG,
/// Apache-2.0, DIS-family). Single instance owned by `AppState`. UI
/// surfaces (Settings → Privacy & AI engine row + onboarding step 3)
/// read `state` and call `download(force:)` / `removeDownloaded()`.
/// The cutout pipeline reads `cachedModelURL()` to decide whether to
/// use the downloaded engine or fall back to Apple Vision V2.
///
/// "Matting model" is the engine-agnostic name in code paths and on
/// disk; the specific model in use is recorded only in the release
/// metadata and this top-of-file comment. Swapping ORMBG for a future
/// model (e.g. once coremltools supports `deform_conv2d` and BiRefNet
/// is back on the table) only requires re-running the conversion
/// script + updating `modelURL` / `expectedSHA256` / bumping
/// `modelVersion` — no Swift renames.
///
/// Persistence layout (sandbox container):
/// ```
/// ~/Library/Containers/<bundle>/Data/Library/Application Support/Avatar/Models/
///   ├── matting-model.mlmodelc/   ← compiled, runtime-ready
///   └── .model_version             ← "1\n" (matches `modelVersion`)
/// ```
///
/// Bumping `modelVersion` invalidates older cached copies on next launch.
/// The legacy V4 BiRefNet model (`BiRefNet.mlmodelc`, ~250 MB, bundled
/// pre-pivot, removed in build 6) is also cleaned up via
/// `removeLegacyLocalModel()` for users updating from a pre-pivot build.
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
    /// can't convert `torchvision::deform_conv2d`. After a brief
    /// IS-Net intermezzo we landed on ORMBG (Apache-2.0, DIS-family,
    /// portrait-trained, 2024) — same restrictions but the only
    /// architecture in scope that converts cleanly. The on-disk
    /// model name stays generic (`matting-model.mlmodelc`) so future
    /// swaps don't touch this constant.
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
        // Why not `URLSession.download(for:delegate:)` async API:
        // that variant routes delegate callbacks via the calling
        // thread, which is suspended in `await`, so
        // `urlSession(_:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)`
        // never fires until the download is already complete — the
        // user sees 0% then a jump to ready, no progress in between.
        // A delegate-bound session running on its own queue avoids
        // that suspension. Side benefit: we can also drive a synthetic
        // progress timer for fast downloads where the real delegate
        // would fire only once or twice.
        let coordinator = DownloadCoordinator(progress: progress)
        return try await coordinator.download(from: Self.modelURL)
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
            .appendingPathComponent(".matting-extract-\(UUID().uuidString)", isDirectory: true)
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

    /// Cleans up the legacy V4 BiRefNet model (`BiRefNet.mlmodelc`,
    /// ~250 MB) shipped in builds prior to the local-first pivot.
    /// Called from `MagicCutoutPreferences.init` and `ModelManager.init`
    /// so any code path that touches the prefs subsystem clears it.
    /// The current downloadable engine lives at `matting-model.mlmodelc`
    /// (engine-agnostic name, currently ORMBG).
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

// MARK: - Download coordinator

/// Self-contained URLSessionDownloadDelegate that owns its session,
/// runs the download via a `URLSessionDownloadTask`, and resumes a
/// continuation when the file lands or the request fails. Designed
/// for one shot: instantiate, call `download(from:)`, throw away.
///
/// Two callbacks of interest fire here:
///   • `didWriteData` updates `progress` from real bytes received.
///   • A synthetic timer ticks ~10× per second while the download is
///     in flight, smoothly easing toward an estimated 90% based on
///     elapsed time vs an ~12 s budget. The timer never reports a
///     value lower than the real progress, so it acts as a *floor*
///     when GitHub's CDN streams the whole file in two big chunks
///     (which would otherwise show 0% → jump → 100%).
///
/// Lifecycle: the URLSession holds the delegate strongly, the delegate
/// holds the session inside `download(from:)` until completion. Both
/// drop their references via `session.invalidateAndCancel()` after
/// the continuation resumes so neither leaks.
private final class DownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var startedAt: Date?
    private var lastReported: Double = 0
    private var syntheticTimer: Task<Void, Never>?

    /// Synthetic-progress budget. Picked so the bar reaches ~90%
    /// after about ten seconds even on a connection that delivers
    /// the whole file in one chunk. Real progress always wins when
    /// it's higher; the synthetic curve only fills the silence.
    private static let syntheticBudgetSeconds: TimeInterval = 12.0
    private static let syntheticCeiling: Double = 0.90

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    func download(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            self.continuation = cont
            self.startedAt = Date()
            lock.unlock()

            // Per-download session — owns this delegate, gets
            // invalidated in `finish(...)`. `delegateQueue: nil`
            // gives URLSession its own serial OperationQueue, so
            // delegate callbacks never collide with our calling
            // thread (which is the actual reason the async
            // `download(for:delegate:)` fails to deliver progress
            // — its delegate runs on the suspended awaiter).
            let config = URLSessionConfiguration.ephemeral
            let s = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            lock.lock()
            self.session = s
            lock.unlock()

            startSyntheticTimer()

            let task = s.downloadTask(with: URLRequest(url: url))
            task.resume()
        }
    }

    // MARK: Real progress (URLSessionDownloadDelegate)

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        report(p)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file at `location` is auto-deleted as soon as this
        // method returns, so we MUST move it inside this scope — the
        // continuation can't be resumed asynchronously with the
        // original URL or it'll point at a missing file.
        do {
            let stable = try moveToStablePath(location)
            report(1.0)
            finish(.success(stable))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        // `didFinishDownloadingTo` already resumed the continuation
        // on success. This handler exists only for the failure path
        // (server error, cancelled, network drop). Check for HTTP
        // non-2xx too — URLSession reports those via the response
        // not the error, so a 404 would otherwise look successful
        // until SHA verify catches it.
        if let error {
            finish(.failure(ModelManagerError.downloadFailed(error.localizedDescription)))
            return
        }
        if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(ModelManagerError.downloadFailed("HTTP \(http.statusCode)")))
        }
    }

    // MARK: Synthetic-progress timer

    /// Drives a slow ease toward `syntheticCeiling` over
    /// `syntheticBudgetSeconds`, reporting 10× per second. Clamped so
    /// it never overrides a higher real-progress value. Cancels itself
    /// on completion via `finish(...)`.
    private func startSyntheticTimer() {
        let task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.reportSynthetic()
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 s
            }
        }
        lock.lock()
        self.syntheticTimer = task
        lock.unlock()
    }

    private func reportSynthetic() {
        lock.lock()
        let start = startedAt
        let last = lastReported
        lock.unlock()
        guard let start else { return }

        // Logistic-ish ease so we don't crawl too slowly at the start
        // or jump too fast near the ceiling. Linear-with-cap is fine
        // for our needs; the visual is much closer to real progress
        // than instant 0→100, which is what the user sees today.
        let elapsed = Date().timeIntervalSince(start)
        let raw = elapsed / Self.syntheticBudgetSeconds
        let synthetic = min(Self.syntheticCeiling, max(0, raw))

        // Don't go backward: only report if the synthetic floor is
        // strictly above the last real-or-synthetic value. This is
        // the "floor" behaviour — real progress (often higher than
        // the timer) always wins.
        if synthetic > last {
            report(synthetic)
        }
    }

    private func report(_ value: Double) {
        lock.lock()
        guard value > lastReported else { lock.unlock(); return }
        lastReported = value
        lock.unlock()
        progress(value)
    }

    // MARK: Cleanup

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let cont = self.continuation
        let s = self.session
        let timer = self.syntheticTimer
        self.continuation = nil
        self.session = nil
        self.syntheticTimer = nil
        lock.unlock()

        timer?.cancel()
        // `invalidateAndCancel` releases the URLSession→delegate
        // strong ref so the coordinator (and the closures it holds)
        // can deinit. Without this the session sits around until
        // the URLSession's own bookkeeping reaps it.
        s?.invalidateAndCancel()

        switch result {
        case .success(let url): cont?.resume(returning: url)
        case .failure(let err): cont?.resume(throwing: err)
        }
    }

    private func moveToStablePath(_ location: URL) throws -> URL {
        // System temp directory is fine — the caller (ModelManager)
        // verifies SHA + extracts immediately and cleans up the zip.
        // No need for `.itemReplacementDirectory` since we never call
        // `FileManager.replaceItem` on it.
        let stable = FileManager.default.temporaryDirectory
            .appendingPathComponent("matting-download-\(UUID().uuidString).zip")
        if FileManager.default.fileExists(atPath: stable.path) {
            try? FileManager.default.removeItem(at: stable)
        }
        try FileManager.default.moveItem(at: location, to: stable)
        return stable
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
