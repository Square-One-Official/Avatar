#if DEBUG

import Foundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Debug-only side-by-side benchmark for the Subject-Lift pipeline.
///
/// Runs every JPG/PNG/HEIC fixture under `Avatar/Debug/Fixtures/` (or the path
/// set in the `AVATAR_BENCH_FIXTURES` env var) through both `subjectLiftV1`
/// (current production) and `subjectLiftV2` (in-development) and writes the
/// results to `~/Desktop/edge-bench-{ISO8601}/` for eyeball comparison.
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

    /// Discovers fixtures, runs V1 + V2 on each, writes a comparison folder,
    /// and reveals it in Finder. Returns the output folder URL on success.
    ///
    /// `sampleSize` caps the run to N random fixtures (used by the "Quick"
    /// menu item — fast iteration while tuning V2). nil = run everything.
    /// Either way the run order is shuffled so eyeballing the first few
    /// PNGs is representative, even when the source folder is alphabetical.
    @discardableResult
    static func run(sampleSize: Int? = nil) -> URL? {
        let allFixtures = discoverFixtures()
        guard !allFixtures.isEmpty else {
            showAlert(
                title: "No fixtures found",
                body: noFixturesBody()
            )
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

        var rows: [String] = ["fixture,v1_ms,v2_ms,ratio,v1_ok,v2_ok"]
        var v1Times: [Double] = []
        var v2Times: [Double] = []
        for url in fixtures {
            let (row, v1ms, v2ms) = process(fixture: url, outDir: outDir)
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

    /// Body for the "no fixtures found" alert. Lists every path the harness
    /// looked at so a misconfigured env var is obvious instead of mysterious.
    private static func noFixturesBody() -> String {
        var lines = ["Looked here:"]
        if let env = ProcessInfo.processInfo.environment["AVATAR_BENCH_FIXTURES"] {
            lines.append("• AVATAR_BENCH_FIXTURES → \(env)")
        }
        if let bundled = Bundle.main.url(forResource: "Fixtures", withExtension: nil) {
            lines.append("• Bundle: \(bundled.path)")
        }
        if let src = locateSourceTreeFixturesFolder() {
            lines.append("• Source tree: \(src.path)")
        } else {
            lines.append("• Source tree: <not resolved>")
        }
        lines.append("")
        lines.append("Drop any portrait JPG/PNG/HEIC files into one of those folders.")
        lines.append("Naming doesn't matter — the harness picks them up automatically.")
        return lines.joined(separator: "\n")
    }

    /// Opens the most recent `~/Desktop/edge-bench-*` folder in Finder, or
    /// shows an alert when none exist.
    static func revealLatest() {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard let desktop,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: desktop,
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
    private static func process(fixture url: URL, outDir: URL) -> (row: String, v1ms: Double, v2ms: Double) {
        let name = url.deletingPathExtension().lastPathComponent
        guard let cg = ImageProcessor.cgImage(from: url) else {
            return ("\(name),,,,,LOAD_FAIL", 0, 0)
        }

        let (v1, v1ms) = timed { try? ImageProcessor.subjectLiftV1(image: cg) }
        let (v2, v2ms) = timed { try? ImageProcessor.subjectLiftV2(image: cg) }

        let v1Ok = (v1 != nil)
        let v2Ok = (v2 != nil)

        if let v1 { writePNG(v1, to: outDir.appendingPathComponent("\(name)-v1-cutout.png")) }
        if let v2 { writePNG(v2, to: outDir.appendingPathComponent("\(name)-v2-cutout.png")) }

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
        let row = "\(name),\(Int(v1ms)),\(Int(v2ms)),\(ratio),\(v1Ok ? 1 : 0),\(v2Ok ? 1 : 0)"
        return (row, v1ms, v2ms)
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

    private static func discoverFixtures() -> [URL] {
        var roots: [URL] = []

        // 1) Env var override — fastest iteration when the dev keeps fixtures
        //    outside the repo.
        if let envPath = ProcessInfo.processInfo.environment["AVATAR_BENCH_FIXTURES"],
           !envPath.isEmpty {
            roots.append(URL(fileURLWithPath: envPath, isDirectory: true))
        }

        // 2) Bundled Fixtures folder (if it ships with the build).
        if let bundleURL = Bundle.main.url(forResource: "Fixtures", withExtension: nil) {
            roots.append(bundleURL)
        }

        // 3) Source-tree fallback — works when running from Xcode out of the
        //    worktree. Walks up from the executable until it finds the folder.
        if let srcTree = locateSourceTreeFixturesFolder() {
            roots.append(srcTree)
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

    /// Resolves the source-tree `Avatar/Debug/Fixtures` folder by anchoring
    /// to *this file's* compile-time path. Walking up from `Bundle.main`
    /// doesn't work for Debug builds — the .app sits in DerivedData,
    /// nowhere near the worktree. `#filePath` always points to the source
    /// file used at build time, so the Fixtures sibling is one step away.
    /// Returns nil when the source tree has been moved or deleted since
    /// build (rare; user fixes by rebuilding).
    private static func locateSourceTreeFixturesFolder() -> URL? {
        let thisFile = URL(fileURLWithPath: #filePath)
        let candidate = thisFile.deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir),
              isDir.boolValue else { return nil }
        return candidate
    }

    private static func makeOutputDir() -> URL? {
        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dir = desktop.appendingPathComponent("edge-bench-\(stamp)", isDirectory: true)
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
