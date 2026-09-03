#if DEBUG

import Foundation
import AppKit
import AvatarKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Debug-only side-by-side benchmark for the Subject-Lift pipeline.
///
/// Runs every JPG/PNG/HEIC/AVIF/WebP fixture under the user-picked fixtures
/// folder (chosen once via NSOpenPanel + persisted as a security-scoped
/// bookmark — the app is sandboxed) through both `subjectLiftV1` (current
/// production) and `subjectLiftV2` (in-development), and writes results
/// inside the app's container at
/// `~/Library/Containers/<bundle-id>/Data/Library/Application Support/EdgeBench/edge-bench-{ISO8601}/`
/// for eyeball comparison. The output folder is revealed in Finder when
/// the run completes; "Open Latest" jumps back to it later.
///
/// The cutouts are composited over a *triptych* backdrop — light grey, dark
/// grey, and a busy noise pattern — because hair-edge defects only become
/// visible when the cutout sits over a backdrop that contrasts with the
/// original photo. A clean cutout looks fine on transparent; the question is
/// always "does it still look fine on a dark green wall".
///
/// Not part of any user-facing flow. Compiled out of Release builds.
@MainActor
enum EdgeBenchmark {

    /// UserDefaults key for the security-scoped bookmark that points at the
    /// fixtures folder. The app is sandboxed, so a user-picked URL plus a
    /// scoped bookmark is the only way to read photos from outside the
    /// container — including the source-tree `Avatar/Debug/Fixtures/` path
    /// that lives inside `~/Documents/Dev Projects/`.
    private static let fixturesBookmarkKey = "edgeBenchmarkFixturesBookmark"

    /// Discovers fixtures, runs V1 + V2 on each, writes a comparison folder,
    /// and reveals it in Finder. Returns the output folder URL on success.
    ///
    /// `sampleSize` caps the run to N random fixtures (used by the "Quick"
    /// menu item — fast iteration while tuning V2). nil = run everything.
    /// Either way the run order is shuffled so eyeballing the first few
    /// PNGs is representative, even when the source folder is alphabetical.
    @discardableResult
    static func run(sampleSize: Int? = nil) -> URL? {
        // Acquire security scope on the bookmarked fixtures folder for the
        // entire run. Without this the FileManager enumeration silently
        // returns nothing — sandbox blocks reads outside the container with
        // no error and no permission prompt.
        let scoped = resolveFixturesBookmark()
        let didStartScope = scoped?.startAccessingSecurityScopedResource() ?? false
        defer {
            if didStartScope, let scoped { scoped.stopAccessingSecurityScopedResource() }
        }

        let allFixtures = discoverFixtures(scopedFolder: scoped)
        guard !allFixtures.isEmpty else {
            // First-run path under sandbox: there's no folder picked yet,
            // or the saved bookmark resolved to an empty / moved folder.
            // Show the picker; on success, recurse so the new bookmark
            // takes effect with its own freshly-acquired scope.
            if pickFixturesFolder() != nil {
                return run(sampleSize: sampleSize)
            }
            showAlert(title: "No fixtures found", body: noFixturesBody())
            return nil
        }

        // Shuffle, then optionally cap. Shuffle first so a partial cap is a
        // genuine random subset rather than the alphabetical first-N.
        var fixtures = allFixtures.shuffled()
        if let n = sampleSize, n > 0, n < fixtures.count {
            fixtures = Array(fixtures.prefix(n))
        }

        let outDir = makeOutputDir()
        guard let outDir else {
            showAlert(title: "Couldn't create output folder",
                      body: "Tried to create a folder under ~/Desktop and failed.")
            return nil
        }

        // Optional downloaded-model arm (ORMBG): only when the user has the
        // model installed. Resolved once for the whole run.
        let downloadedModelURL = ModelManager().cachedModelURL()

        var rows: [String] = ["fixture,v1_ms,v2_ms,ratio,v1_ok,v2_ok,raw_ms,raw_ok,dl_ms,dl_ok,v2min_ms,v2min_ok"]
        var v1Times: [Double] = []
        var v2Times: [Double] = []
        for url in fixtures {
            let (row, v1ms, v2ms) = process(fixture: url, outDir: outDir,
                                            downloadedModelURL: downloadedModelURL)
            rows.append(row)
            if v1ms > 0 { v1Times.append(v1ms) }
            if v2ms > 0 { v2Times.append(v2ms) }
            dlog("[EdgeBench] \(url.lastPathComponent) → \(row)")
        }

        // Summary row at the top — easier to read in spreadsheet apps if it
        // sits below the header. Keep header + summary + per-fixture rows.
        let summary = makeSummaryRow(v1: v1Times, v2: v2Times,
                                      total: allFixtures.count,
                                      processed: fixtures.count)
        rows.insert(summary, at: 1)

        let csvURL = outDir.appendingPathComponent("00-summary.csv")
        try? rows.joined(separator: "\n").write(to: csvURL, atomically: true, encoding: .utf8)

        // Reveal in Finder so the user can scrub through the side-by-side
        // PNGs without re-finding the folder.
        NSWorkspace.shared.activateFileViewerSelecting([csvURL])
        return outDir
    }

    private static func makeSummaryRow(v1: [Double], v2: [Double],
                                        total: Int, processed: Int) -> String {
        let avg: ([Double]) -> Double = { $0.isEmpty ? 0 : $0.reduce(0, +) / Double($0.count) }
        let v1Avg = avg(v1), v2Avg = avg(v2)
        let ratio = v1Avg > 0 ? String(format: "%.2f", v2Avg / v1Avg) : ""
        let label = processed == total
            ? "SUMMARY (\(processed) fixtures)"
            : "SUMMARY (\(processed) of \(total) random)"
        return "\(label),\(Int(v1Avg)),\(Int(v2Avg)),\(ratio),avg_v1_ms,avg_v2_ms"
    }

    /// Body for the "no fixtures found" alert. Reached only when the user
    /// cancelled the picker — explains why the source-tree path won't work
    /// without a bookmark and tells them how to retry.
    private static func noFixturesBody() -> String {
        var lines = [
            "The app is sandboxed, so the harness needs you to pick the",
            "fixtures folder once via the OS file picker. macOS then grants",
            "this app a long-lived security-scoped bookmark to that folder.",
            "",
            "Try again with:",
            "  Debug → Choose Fixtures Folder…",
            ""
        ]
        if let env = ProcessInfo.processInfo.environment["AVATAR_BENCH_FIXTURES"] {
            lines.append("AVATAR_BENCH_FIXTURES env var is set to: \(env)")
            lines.append("(Only works for paths inside the sandbox container.)")
        }
        if resolveFixturesBookmark() != nil {
            lines.append("Saved bookmark exists, but the folder has no recognised")
            lines.append("portraits (.jpg/.jpeg/.png/.heic/.heif/.avif/.webp).")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Sandbox: user-picker + security-scoped bookmark

    /// Show NSOpenPanel for the user to pick a fixtures folder. Returns the
    /// picked URL on success (and saves a security-scoped bookmark for next
    /// time); nil if the user cancelled.
    @discardableResult
    @MainActor
    static func pickFixturesFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Pick the Subject-Lift fixtures folder"
        panel.message = "Drop your portrait fixtures here. The benchmark will run on every JPG, PNG, HEIC, AVIF, and WebP it finds."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        // .claude/worktrees/ lives behind a dotfile component — show hidden
        // so the user doesn't have to Cmd+Shift+. inside the panel.
        panel.showsHiddenFiles = true
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        saveFixturesBookmark(for: url)
        return url
    }

    /// Public action exposed via the Debug menu — re-prompt and replace the
    /// saved bookmark. Useful when the user moves the worktree.
    @MainActor
    static func chooseFixturesFolder() {
        _ = pickFixturesFolder()
    }

    private static func saveFixturesBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(options: .withSecurityScope,
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil)
            UserDefaults.standard.set(data, forKey: fixturesBookmarkKey)
        } catch {
            dlog("[EdgeBench] Failed to save bookmark: \(error)")
        }
    }

    /// Resolves the saved bookmark to a URL. Returns nil if there's no
    /// bookmark, or if the folder has been deleted entirely. Stale bookmarks
    /// (folder moved but still exists) are transparently re-saved.
    private static func resolveFixturesBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: fixturesBookmarkKey) else { return nil }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &stale)
            if stale { saveFixturesBookmark(for: url) }
            return url
        } catch {
            dlog("[EdgeBench] Bookmark resolution failed: \(error)")
            return nil
        }
    }

    /// Opens the most recent `EdgeBench/edge-bench-*` folder under
    /// Application Support in Finder, or shows an alert when none exist.
    static func revealLatest() {
        guard let root = benchmarkRootDir(),
              let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              )
        else {
            showAlert(title: "No benchmark folders found",
                      body: "Run the benchmark first.")
            return
        }
        let benches = entries
            .filter { $0.lastPathComponent.hasPrefix("edge-bench-") }
            .sorted { (a, b) in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
        guard let latest = benches.first else {
            showAlert(title: "No benchmark folders found",
                      body: "Run the benchmark first.")
            return
        }
        NSWorkspace.shared.open(latest)
    }

    // MARK: - Per-fixture work

    /// Runs both pipelines and writes the V1, V2, and side-by-side PNGs.
    /// Returns the CSV row plus the two wall-clock times so the caller can
    /// roll them up into the summary row. Failures are reported in the row
    /// (`v1_ok` / `v2_ok` flags) rather than aborting the whole run.
    private static func process(fixture url: URL, outDir: URL,
                                downloadedModelURL: URL? = nil) -> (row: String, v1ms: Double, v2ms: Double) {
        let name = url.deletingPathExtension().lastPathComponent
        guard let cg = ImageProcessor.cgImage(from: url) else {
            return ("\(name),,,,,LOAD_FAIL,,,,", 0, 0)
        }

        let (v1, v1ms) = timed { try? ImageProcessor.subjectLiftV1(image: cg) }
        let (v2, v2ms) = timed { try? ImageProcessor.subjectLiftV2(image: cg) }

        // 2.0 bakeoff arms: the unrefined Vision baseline (every refinement
        // stage must beat this to earn its place in 2.0), and the optional
        // downloaded matting model (decides whether ModelManager survives).
        let (raw, rawMs) = timed { try? ImageProcessor.subjectLiftRaw(image: cg) }
        let (dl, dlMs): (CGImage?, Double) = {
            guard let modelURL = downloadedModelURL else { return (nil, 0) }
            return timed { try? ImageProcessor.subjectLiftDownloaded(image: cg, modelURL: modelURL) }
        }()

        // Vijfde arm (E02.2): de 2.0-minimal pipeline zelf — VisionCutoutEngine
        // uit AvatarKit, exact wat Avatar2 gaat shippen.
        let (v2min, v2minMs) = timed { runV2Minimal(image: cg) }

        let v1Ok = (v1 != nil)
        let v2Ok = (v2 != nil)

        if let v1 { writePNG(v1, to: outDir.appendingPathComponent("\(name)-v1-cutout.png")) }
        if let v2 { writePNG(v2, to: outDir.appendingPathComponent("\(name)-v2-cutout.png")) }
        if let raw { writePNG(raw, to: outDir.appendingPathComponent("\(name)-raw-cutout.png")) }
        if let dl { writePNG(dl, to: outDir.appendingPathComponent("\(name)-ormbg-cutout.png")) }
        if let v2min { writePNG(v2min, to: outDir.appendingPathComponent("\(name)-v2min-cutout.png")) }

        // Extra triptychs so raw and ORMBG can be eyeballed against V2 on
        // the same contrast backdrops as the existing V1/V2 comparison.
        if let raw, let v2 {
            let strip = makeSideBySide(v1: raw, v2: v2)
            writePNG(strip, to: outDir.appendingPathComponent("\(name)-raw-vs-v2.png"))
        }
        if let dl, let v2 {
            let strip = makeSideBySide(v1: dl, v2: v2)
            writePNG(strip, to: outDir.appendingPathComponent("\(name)-ormbg-vs-v2.png"))
        }
        if let v2min, let v2 {
            let strip = makeSideBySide(v1: v2min, v2: v2)
            writePNG(strip, to: outDir.appendingPathComponent("\(name)-v2min-vs-v2.png"))
        }

        // Side-by-side over the triptych backdrop. We composite the cutout
        // onto each of three test backgrounds (light grey, dark grey, busy
        // noise) and stack them V1-on-top, V2-on-bottom for easy A/B.
        if let v1, let v2 {
            let triptych = makeSideBySide(v1: v1, v2: v2)
            writePNG(triptych, to: outDir.appendingPathComponent("\(name)-side-by-side.png"))
        }

        let ratio: String = {
            guard v1ms > 0 else { return "" }
            return String(format: "%.2f", v2ms / v1ms)
        }()
        let row = "\(name),\(Int(v1ms)),\(Int(v2ms)),\(ratio),\(v1Ok ? 1 : 0),\(v2Ok ? 1 : 0),"
            + "\(Int(rawMs)),\(raw != nil ? 1 : 0),"
            + "\(downloadedModelURL == nil ? "" : String(Int(dlMs))),\(dl != nil ? 1 : 0),"
            + "\(Int(v2minMs)),\(v2min != nil ? 1 : 0)"
        return (row, v1ms, v2ms)
    }

    /// Sync bridge naar de async VisionCutoutEngine. De engine doet puur
    /// Vision/CoreImage-werk zonder MainActor-afhankelijkheid, dus een
    /// detached task + semaphore vanaf de (MainActor-)harness is veilig —
    /// debug-harness-pragmatiek, geen productie-patroon.
    private static func runV2Minimal(image: CGImage) -> CGImage? {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: CGImage?
        Task.detached(priority: .userInitiated) {
            result = try? await VisionCutoutEngine().cutout(image)
            sem.signal()
        }
        sem.wait()
        return result
    }

    /// Renders a vertical stack: V1 over three backdrops on top, V2 over the
    /// same three backdrops on the bottom. Forces both pipelines to be
    /// inspected against backdrops that contrast with typical hair colours.
    private static func makeSideBySide(v1: CGImage, v2: CGImage) -> CGImage {
        let h = v1.height
        let w = v1.width
        // Three backdrops: light grey (catches dark hair fringe), dark grey
        // (catches blonde hair fringe), checker noise (catches both).
        let backdrops: [CIImage] = [
            solidColor(.init(red: 0.92, green: 0.92, blue: 0.94, alpha: 1), size: CGSize(width: w, height: h)),
            solidColor(.init(red: 0.10, green: 0.10, blue: 0.12, alpha: 1), size: CGSize(width: w, height: h)),
            checkerPattern(size: CGSize(width: w, height: h))
        ]

        let v1CI = CIImage(cgImage: v1)
        let v2CI = CIImage(cgImage: v2)

        // Composite each cutout over each backdrop.
        let v1Composites = backdrops.map { bg in
            v1CI.applyingFilter("CISourceOverCompositing", parameters: [
                kCIInputBackgroundImageKey: bg
            ]).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let v2Composites = backdrops.map { bg in
            v2CI.applyingFilter("CISourceOverCompositing", parameters: [
                kCIInputBackgroundImageKey: bg
            ]).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        }

        // Lay out: row 1 = V1 (3 panels), row 2 = V2 (3 panels). Each panel
        // sized to the source image. Output is 3w × 2h.
        let rowW = w * 3
        let totalH = h * 2
        let outRect = CGRect(x: 0, y: 0, width: rowW, height: totalH)

        var canvas = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: outRect)
        for (i, panel) in v1Composites.enumerated() {
            // Top row — Y axis is bottom-up in CIImage coordinates.
            let placed = panel.transformed(by: CGAffineTransform(translationX: CGFloat(i * w),
                                                                  y: CGFloat(h)))
            canvas = placed.composited(over: canvas).cropped(to: outRect)
        }
        for (i, panel) in v2Composites.enumerated() {
            let placed = panel.transformed(by: CGAffineTransform(translationX: CGFloat(i * w),
                                                                  y: 0))
            canvas = placed.composited(over: canvas).cropped(to: outRect)
        }

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        return ctx.createCGImage(canvas, from: outRect, format: .RGBA8, colorSpace: cs)!
    }

    private static func solidColor(_ c: CIColor, size: CGSize) -> CIImage {
        CIImage(color: c).cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Cheap "busy" backdrop — a 32-px checkerboard via CICheckerboardGenerator.
    /// Doesn't catch every kind of fringe but exposes the obvious ones (a clean
    /// cutout's edge should be invisible against any solid colour transition).
    private static func checkerPattern(size: CGSize) -> CIImage {
        let f = CIFilter.checkerboardGenerator()
        f.color0 = CIColor(red: 0.50, green: 0.62, blue: 0.45)
        f.color1 = CIColor(red: 0.18, green: 0.30, blue: 0.55)
        f.width = 32
        return (f.outputImage ?? CIImage(color: .gray))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    // MARK: - Discovery + IO

    private static func discoverFixtures(scopedFolder: URL? = nil) -> [URL] {
        var roots: [URL] = []

        // 1) Env var override — handy in non-sandboxed test runs. Under the
        //    real sandbox this only resolves if the path is inside the
        //    container, so the bookmark path (2) is the primary mechanism.
        if let envPath = ProcessInfo.processInfo.environment["AVATAR_BENCH_FIXTURES"],
           !envPath.isEmpty {
            roots.append(URL(fileURLWithPath: envPath, isDirectory: true))
        }

        // 2) User-picked folder via NSOpenPanel + security-scoped bookmark.
        //    Caller has already started scope before invoking us; we just
        //    enumerate. This is the path that lets the sandboxed app read
        //    fixtures sitting in the worktree (or anywhere else outside
        //    the container).
        if let scopedFolder { roots.append(scopedFolder) }

        // 3) Bundled Fixtures folder (if anyone ever copies them into
        //    Resources for an end-to-end test build). Always sandbox-safe.
        if let bundleURL = Bundle.main.url(forResource: "Fixtures", withExtension: nil) {
            roots.append(bundleURL)
        }

        // ImageIO on macOS 14+ handles AVIF and WebP natively; CGImageSource
        // (used by ImageProcessor.cgImage) accepts them via the same path as
        // JPG/PNG/HEIC, so we don't need any extra decode setup.
        let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "avif", "webp"]
        var fixtures: [URL] = []
        var seen = Set<String>()
        for root in roots {
            guard let it = FileManager.default.enumerator(at: root,
                                                          includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else { continue }
            for case let url as URL in it {
                guard exts.contains(url.pathExtension.lowercased()) else { continue }
                let key = url.standardizedFileURL.path
                if seen.insert(key).inserted {
                    fixtures.append(url)
                }
            }
        }
        return fixtures.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Output folder lives inside the sandbox's Application Support
    /// container — the only place a sandboxed app is guaranteed to be able
    /// to write without requesting any further entitlements. The user
    /// reaches it via Finder when the run completes (NSWorkspace reveal).
    /// Concretely: `~/Library/Containers/<bundle-id>/Data/Library/Application Support/EdgeBench/edge-bench-<stamp>/`.
    private static func benchmarkRootDir() -> URL? {
        guard let appSupport = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                              in: .userDomainMask,
                                                              appropriateFor: nil,
                                                              create: true) else { return nil }
        let dir = appSupport.appendingPathComponent("EdgeBench", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func makeOutputDir() -> URL? {
        guard let root = benchmarkRootDir() else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dir = root.appendingPathComponent("edge-bench-\(stamp)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }

    private static func writePNG(_ cg: CGImage, to url: URL) {
        guard let data = ImageProcessor.pngData(from: cg) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Wall-clock timing in milliseconds. Returns the result paired with the
    /// elapsed time so callers can record both even when the result is nil.
    private static func timed<T>(_ block: () -> T) -> (T, Double) {
        let start = CFAbsoluteTimeGetCurrent()
        let result = block()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        return (result, ms)
    }

    private static func showAlert(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.runModal()
    }
}

#endif
