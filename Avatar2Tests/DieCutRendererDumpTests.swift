import AppKit
import AvatarKit
import XCTest
@testable import Avatar2

/// Visuele contactsheet van de die-cut-afwerking (E55.13) — geen assert,
/// alleen een PNG voor review. Per input (een ruw gpt-image-sticker-resultaat,
/// bv. uit de e55-bakeoff): [model-resultaat | her-isolatie zoals vóór de fix |
/// her-isolatie + DieCutRenderer] op een gekleurde achtergrond, zodat de rand
/// leesbaar is. Draait uitsluitend met:
///   TEST_RUNNER_DIECUT_DUMP_INPUTS=<a.png>:<b.png>
/// Output: <container tmp>/diecut-dump.png (sandbox: alleen daar schrijfbaar).
final class DieCutRendererDumpTests: XCTestCase {

    func testDumpContactSheet() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let inputs = env["DIECUT_DUMP_INPUTS"]?.split(separator: ":").map(String.init), !inputs.isEmpty
        else { throw XCTSkip("DIECUT_DUMP_INPUTS niet gezet") }

        let cell: CGFloat = 420, gap: CGFloat = 12
        var rows: [[NSImage]] = []
        for path in inputs {
            guard let raw = NSImage(contentsOfFile: path),
                  let cg = raw.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let isolatedCG = try await VisionCutoutEngine().cutout(cg)
            let isolated = NSImage(cgImage: isolatedCG, size: NSSize(width: isolatedCG.width, height: isolatedCG.height))
            let finished = await DieCutRenderer.finish(isolated)
            let metrics = AutoFramer.metrics(for: isolatedCG)
            let r = DieCutRenderer.borderRadius(
                geometry: .init(metrics: metrics), imageSize: CGSize(width: isolatedCG.width, height: isolatedCG.height)
            )
            for factor in [0.75, 1.0, 1.5] {
                let sample = DieCutRenderer.paperSample(of: isolatedCG, bandWidth: r * factor)
                print("[diecut-dump] \(path.split(separator: "/").last ?? "") r=\(r) band×\(factor) fraction=\(String(format: "%.3f", sample.fraction)) color=\(sample.color)")
            }
            rows.append([raw, isolated, finished])
        }
        XCTAssertFalse(rows.isEmpty, "geen leesbare inputs")

        let sheet = NSImage(size: NSSize(
            width: gap + 3 * (cell + gap),
            height: gap + CGFloat(rows.count) * (cell + gap)
        ))
        sheet.lockFocus()
        NSColor(red: 0.85, green: 0.12, blue: 0.12, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: sheet.size)).fill()
        for (row, images) in rows.enumerated() {
            for (col, image) in images.enumerated() {
                let scale = min(cell / max(image.size.width, 1), cell / max(image.size.height, 1))
                let w = image.size.width * scale, h = image.size.height * scale
                let x = gap + CGFloat(col) * (cell + gap) + (cell - w) / 2
                let y = sheet.size.height - gap - CGFloat(row + 1) * (cell + gap) + gap + (cell - h) / 2
                image.draw(in: NSRect(x: x, y: y, width: w, height: h))
            }
        }
        sheet.unlockFocus()

        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("diecut-dump.png")
        guard let tiff = sheet.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("sheet-encode faalde"); return
        }
        try png.write(to: url)
        print("[diecut-dump] \(url.path)")
    }
}
