import AppKit
import AvatarKit
import AvatarUI
import SwiftUI
import XCTest
@testable import Avatar2

/// Visuele contactsheet van alle Enhance-tegels (E53.10) — geen assert, alleen
/// een PNG voor review. Draait uitsluitend met:
///   TEST_RUNNER_ENHANCE_TILE_DUMP_DIR=<map> TEST_RUNNER_ENHANCE_TILE_SUBJECT=<cutout.png>
@MainActor
final class EnhanceTileSnapshotDumpTests: XCTestCase {

    func testDumpContactSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["ENHANCE_TILE_DUMP_DIR"],
              let subjectPath = env["ENHANCE_TILE_SUBJECT"],
              let subject = NSImage(contentsOfFile: subjectPath),
              let cg = subject.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { throw XCTSkip("ENHANCE_TILE_DUMP_DIR / ENHANCE_TILE_SUBJECT niet gezet") }

        let scene = EnhancePreviewScenes.image(named: EnhancePreviewScenes.names[0])?
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
        let actions: [(String, EnhanceTilePreview.Action, EnhanceTileMotion, Bool)] = [
            ("Retouch", .retouch, .wipeHorizontal(rest: 0.5, from: .trailing), false),
            ("Studio Light", .studioLight, .spotlight, false),
            ("Portrait", .portrait, .depthPull, true),
            ("Colorise", .colorise, .wipeHorizontal(rest: 0.5, from: .trailing), false),
            ("Boost", .boost, .resolve, false),
            ("Fill in body", .fillBody, .wipeVertical(rest: Double(EnhanceTilePreview.fillBodySplit)), false),
            ("Remove background", .removeBackground, .dissolve, false)
        ]
        let tileW = EnhanceTileMetrics.tileWidth, tileH = EnhanceTileMetrics.height, gap: CGFloat = 12
        let steps: [Double?] = [nil, 0.35, 0.55, 1.0]
        let sheet = NSImage(size: NSSize(
            width: gap + CGFloat(steps.count) * (tileW + gap),
            height: gap + CGFloat(actions.count) * (tileH + gap)
        ))
        sheet.lockFocus()
        NSColor(red: 0.11, green: 0.098, blue: 0.09, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: sheet.size)).fill()
        for (row, entry) in actions.enumerated() {
            let (title, action, motion, useScene) = entry
            let layers = EnhanceTilePreview.renderLayers(
                action: action, subject: cg, backdrop: useScene ? scene : nil
            ).map(EnhanceTileLayers.init)
            for (col, step) in steps.enumerated() {
                let progress = step ?? motion.rest
                let tile = EnhanceActionTile(
                    title: title,
                    credit: action == .fillBody ? "2" : nil,
                    showsMenu: action == .boost || action == .removeBackground,
                    layers: layers,
                    motion: motion,
                    fallback: subject,
                    debugProgress: progress,
                    action: {}
                )
                .frame(width: tileW, height: tileH)
                .background(DSColor.Background.card)
                .environment(\.colorScheme, .dark)
                let renderer = ImageRenderer(content: tile)
                renderer.scale = 2
                guard let img = renderer.nsImage else { continue }
                let x = gap + CGFloat(col) * (tileW + gap)
                let y = sheet.size.height - gap - CGFloat(row + 1) * (tileH + gap) + gap
                img.draw(in: NSRect(x: x, y: y, width: tileW, height: tileH))
            }
        }
        sheet.unlockFocus()
        let tiff = try XCTUnwrap(sheet.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        // Sandbox: "TMP" = container-tempmap (daarna kopiëren).
        let base = dir == "TMP" ? NSTemporaryDirectory() : dir
        let url = URL(fileURLWithPath: base).appendingPathComponent("enhance-tiles.png")
        try png.write(to: url)
        print("ENHANCE_TILE_DUMP: \(url.path)")
    }
}
