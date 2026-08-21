// Set-brede acties (Match framing, Match lighting, bulk-export, Set background)
// — via de gedeelde selectie + rechtermuis op Home én Portraits (Finder-stijl).
// Ze werken op de huidige multi-selectie i.p.v. de hele set; elke actie is
// één undo-groep.

import AppKit
import AvatarKit
import AvatarUI
import SwiftData
import SwiftUI

@MainActor
enum PortraitSetActions {
    /// Zelfde ooglijn + camera-afstand over de selectie, zonder lege onderkant.
    /// Eén undo-stap. Editor Auto-frame blijft per-portret (`AutoFramer.apply`).
    static func matchFraming(_ targets: [Portrait2], undoManager: UndoManager?, onBusy: @escaping (String?) -> Void) {
        guard !targets.isEmpty else { return }
        onBusy("Matching framing…")
        Task {
            defer { onBusy(nil) }
            var portraits: [Portrait2] = []
            var befores: [TransformUndo.Snapshot] = []
            var images: [CGImage] = []
            for portrait in targets {
                guard let cg = NSImage(data: portrait.cutoutData)?
                    .cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                portraits.append(portrait)
                befores.append(TransformUndo.snapshot(of: portrait))
                images.append(cg)
            }
            let transforms = await AutoFramer.sharedTransforms(for: images)
            undoManager?.beginUndoGrouping()
            undoManager?.setActionName("Match Framing")
            DSMotion.animate(DSMotion.springTransform) {
                for (index, portrait) in portraits.enumerated() {
                    let transform = transforms[index]
                    portrait.offsetX = transform.offset.width
                    portrait.offsetY = transform.offset.height
                    portrait.scale = transform.scale
                    portrait.touch()
                    TransformUndo.register(
                        undoManager, portrait: portrait,
                        undoTo: befores[index], redoTo: TransformUndo.snapshot(of: portrait),
                        actionName: "Match Framing"
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
            DSMotion.animate(DSMotion.springTransform) {
                for (portrait, before, after) in items {
                    portrait.cutoutData = after
                    portrait.cutoutDerivesFromOriginal = false
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

    /// Zelfde achtergrond op alle targets, één undo-groep.
    static func setBackground(
        _ targets: [Portrait2],
        _ background: PortraitBackground,
        undoManager: UndoManager?
    ) {
        guard !targets.isEmpty else { return }
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName("Background")
        for portrait in targets {
            let before = portrait.background
            guard before != background else { continue }
            portrait.setBackground(background)
            ReversibleChange.register(
                undoManager, target: portrait,
                from: before, to: background, actionName: "Background"
            ) { p, bg in
                p.setBackground(bg)
            }
        }
        undoManager?.endUndoGrouping()
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
            // Dedupliceer binnen de batch: twee portretten met dezelfde naam
            // worden "Naam.png", "Naam-2.png", "Naam-3.png" i.p.v. elkaar stil
            // te overschrijven.
            var usedNames: Set<String> = []
            for (i, p) in targets.enumerated() {
                // Off-main render (makePNGAsync) — de compositing blokkeert de UI niet.
                guard let data = await PortraitExporter.makePNGAsync(for: p, watermark: !isPro, shape: p.frameShape) else { continue }
                let trimmed = p.name.trimmingCharacters(in: .whitespaces)
                let base = trimmed.isEmpty ? "portrait-\(i + 1)" : trimmed.replacingOccurrences(of: "/", with: "-")
                var name = base
                var counter = 2
                while usedNames.contains(name.lowercased()) {
                    name = "\(base)-\(counter)"
                    counter += 1
                }
                usedNames.insert(name.lowercased())
                try? data.write(to: dir.appendingPathComponent(name + ".png"))
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
