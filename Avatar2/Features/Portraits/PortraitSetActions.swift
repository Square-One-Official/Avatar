// Set-brede acties (Align, Match lighting, bulk-export) — gelift uit de
// verwijderde rechter set-sidebar zodat ze nu via de gedeelde selectie +
// rechtermuis op Home én Portraits beschikbaar zijn (Finder-stijl). Ze werken op
// de huidige multi-selectie i.p.v. de hele set; elke actie is één undo-groep.

import AppKit
import AvatarKit
import SwiftData
import SwiftUI

@MainActor
enum PortraitSetActions {
    /// Auto-frame (E06.5) elk geselecteerd portret als één undo-stap.
    static func align(_ targets: [Portrait2], undoManager: UndoManager?, onBusy: @escaping (String?) -> Void) {
        guard !targets.isEmpty else { return }
        onBusy("Aligning…")
        Task {
            defer { onBusy(nil) }
            // 1. Bereken alle transforms (off-main per cutout).
            var items: [(Portrait2, TransformUndo.Snapshot, AutoFramer.Transform)] = []
            for portrait in targets {
                guard let cg = NSImage(data: portrait.cutoutData)?
                    .cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                let before = TransformUndo.snapshot(of: portrait)
                let transform = await AutoFramer.transform(forCutout: cg)
                items.append((portrait, before, transform))
            }
            // 2. Schrijf + registreer in één undo-groep.
            undoManager?.beginUndoGrouping()
            undoManager?.setActionName("Align")
            withAnimation(.spring(duration: 0.45)) {
                for (portrait, before, transform) in items {
                    portrait.offsetX = transform.offset.width
                    portrait.offsetY = transform.offset.height
                    portrait.scale = transform.scale
                    portrait.touch()
                    TransformUndo.register(
                        undoManager, portrait: portrait,
                        undoTo: before, redoTo: TransformUndo.snapshot(of: portrait),
                        actionName: "Align"
                    )
                }
            }
            undoManager?.endUndoGrouping()
        }
    }

    /// Trek de belichting van de selectie naar `reference` (de aangeklikte tegel)
    /// als referentie; de referentie zelf blijft ongemoeid.
    static func matchLighting(_ targets: [Portrait2], reference: Portrait2, undoManager: UndoManager?, onBusy: @escaping (String?) -> Void) {
        guard targets.count >= 2 else { return }
        onBusy("Matching lighting…")
        Task {
            defer { onBusy(nil) }
            guard let refCG = cgImage(from: reference.cutoutData),
                  let refStats = SetLightingNormalizer.referenceStats(of: refCG) else { return }
            var items: [(Portrait2, Data, Data)] = []
            for portrait in targets where portrait.persistentModelID != reference.persistentModelID {
                guard let cg = cgImage(from: portrait.cutoutData),
                      let outCG = SetLightingNormalizer.match(cg, to: refStats),
                      let png = pngData(from: outCG) else { continue }
                items.append((portrait, portrait.cutoutData, png))
            }
            undoManager?.beginUndoGrouping()
            undoManager?.setActionName("Match Lighting")
            withAnimation(.spring(duration: 0.4)) {
                for (portrait, before, after) in items {
                    portrait.cutoutData = after
                    portrait.touch()
                    CutoutDataUndo.register(
                        undoManager, portrait: portrait,
                        undoTo: before, redoTo: after, actionName: "Match Lighting"
                    )
                }
            }
            undoManager?.endUndoGrouping()
        }
    }

    /// Exporteer de selectie naar een gekozen map (free = watermerk).
    static func export(_ targets: [Portrait2], isPro: Bool, onBusy: @escaping (String?) -> Void) {
        guard !targets.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose a folder to export the selected portraits"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        onBusy("Exporting \(targets.count) portraits…")
        Task {
            defer { onBusy(nil) }
            for (i, p) in targets.enumerated() {
                guard let data = PortraitExporter.makePNG(for: p, watermark: !isPro, shape: p.frameShape) else { continue }
                let base = p.name.trimmingCharacters(in: .whitespaces)
                let name = (base.isEmpty ? "portrait-\(i + 1)" : base.replacingOccurrences(of: "/", with: "-")) + ".png"
                try? data.write(to: dir.appendingPathComponent(name))
            }
        }
    }

    private static func cgImage(from data: Data) -> CGImage? {
        NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func pngData(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
