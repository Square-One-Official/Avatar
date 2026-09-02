// E50.3 — diagnose-dump voor Match lighting op ECHTE cutouts (geen assert).
// Draait uitsluitend met:
//   LIGHTING_DIAG_DIR=<map met cutout-PNG's> [LIGHTING_DIAG_OUT=<uitvoermap>]
// Print per beeld de stats (rauw), de kwaliteitsscore, de doelkeuze en per
// buitenstaander de (verfijnde) Adjust-suggestie; schrijft optioneel
// before/after-PNG's + een contactsheet naar de uitvoermap.

import AppKit
import CoreGraphics
import XCTest
@testable import AvatarKit

final class SetLightingDiagnosticsTests: XCTestCase {
    func testDumpMatchLightingDiagnostics() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["LIGHTING_DIAG_DIR"] else { throw XCTSkip("LIGHTING_DIAG_DIR niet gezet") }
        let outDir = env["LIGHTING_DIAG_OUT"]
        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
            .filter { $0.lowercased().hasSuffix(".png") }.sorted()
        var names: [String] = []
        var images: [CGImage] = []
        var regions: [CGRect?] = []
        var stats: [SetLightingNormalizer.Stats] = []
        for file in files {
            guard let full = NSImage(contentsOfFile: dir + "/" + file)?
                    .cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let scaled = SetLightingNormalizer.downscaled(full, maxSide: 256) else { continue }
            let region = SetLightingNormalizer.faceRegion(in: full).map {
                $0.applying(CGAffineTransform(scaleX: scaled.scale, y: scaled.scale))
            }
            guard let s = SetLightingNormalizer.referenceStats(of: scaled.image, in: region) else { continue }
            names.append(file); images.append(scaled.image); regions.append(region); stats.append(s)
            print(String(format: "%@: exposure %.3f kelvin %.0f tint %.1f contrast %.3f quality %.2f face %@",
                         file, s.exposure, s.kelvin, s.tint, s.contrast,
                         SetLightingNormalizer.qualityScore(s), region.map { "\($0.integral)" } ?? "none"))
        }
        for i in 0..<stats.count { for j in (i + 1)..<stats.count {
            print(String(format: "distance %@ ↔ %@: %.2f", names[i], names[j], SetLightingNormalizer.distance(stats[i], stats[j])))
        } }
        guard let choice = SetLightingNormalizer.chooseTarget(stats) else { return }
        let target: SetLightingNormalizer.Stats
        switch choice.target {
        case .portrait(let i): target = stats[i]; print("target: portrait \(names[i])")
        case .centroid(let c): target = c; print(String(format: "target: centroid exposure %.3f kelvin %.0f contrast %.3f", c.exposure, c.kelvin, c.contrast))
        }
        print("adjust:", choice.adjust.map { names[$0] })
        for i in choice.adjust {
            let within = SetLightingNormalizer.isWithinTolerance(stats[i], target)
            let s = SetLightingNormalizer.adjustSuggestion(from: stats[i], to: target)
            let r = SetLightingNormalizer.refine(s, raw: images[i], region: regions[i], to: target)
            print(String(format: "  %@: within %@ suggestion b %.3f c %.3f t %.3f → refined b %.3f c %.3f t %.3f",
                         names[i], within ? "yes" : "no", s.brightness, s.contrast, s.temperature, r.brightness, r.contrast, r.temperature))
            if let outDir, let out = PortraitEnhancer.colorAdjust(images[i], brightness: r.brightness, contrast: r.contrast, saturation: 1, temperatureShift: r.temperature) {
                try? write(out, to: outDir + "/after-" + names[i])
                try? write(images[i], to: outDir + "/before-" + names[i])
                if let after = SetLightingNormalizer.referenceStats(of: out, in: regions[i]) {
                    print(String(format: "    after: exposure %.3f kelvin %.0f contrast %.3f", after.exposure, after.kelvin, after.contrast))
                }
            }
        }
        if let outDir {
            for (i, img) in images.enumerated() where !choice.adjust.contains(i) { try? write(img, to: outDir + "/keep-" + names[i]) }
        }
    }

    private func write(_ image: CGImage, to path: String) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try data.write(to: URL(fileURLWithPath: path))
    }
}
