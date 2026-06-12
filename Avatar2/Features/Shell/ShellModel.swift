// Main shell — importstate (E05.2). Drag-drop/bestandskiezer → PipelineRouter
// (Vision-engine als enige geregistreerde arm; ORMBG/cloud haken aan zodra
// hun settings-/entitlement-stories landen). De isolating-animatie met
// klaar- en faalstaat is E05.3 — hier alleen een minimale processing-staat.

import AppKit
import AvatarKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ShellModel {
    enum CanvasState {
        case empty
        /// Fase 1 (E05.3): origineel op canvas, cutout rekent —
        /// "Removing background...".
        case processing(NSImage)
        /// Fase 2 (E05.3): cutout klaar, achtergrond fadet naar donker —
        /// "Cutting out hair...".
        case revealing(original: NSImage, cutout: NSImage)
        case result(NSImage)
        case failed(String)
    }

    private(set) var canvas: CanvasState = .empty
    var isDropTargeted = false

    /// Naam/rol van het huidige portret (E05.5). Verhuist naar het
    /// SwiftData-model Portrait2 zodra E05.4 landt.
    var portraitName = ""
    var portraitRole = ""

    private let entitlement: EntitlementModel

    @ObservationIgnored
    private let router = PipelineRouter(engines: [VisionCutoutEngine()])

    init(entitlement: EntitlementModel) {
        self.entitlement = entitlement
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importImage(from: url) }
    }

    func importImage(from url: URL) async {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            canvas = .failed("That file doesn't look like an image we can read.")
            return
        }
        await runCutout(on: cgImage)
    }

    func importImage(data: Data) async {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            canvas = .failed("That file doesn't look like an image we can read.")
            return
        }
        await runCutout(on: cgImage)
    }

    private func runCutout(on cgImage: CGImage) async {
        let original = nsImage(from: cgImage)
        canvas = .processing(original)
        do {
            let cutout = nsImage(from: try await router.cutout(cgImage))
            // Reveal-fase (E05.3): achtergrond fadet naar donker; de view
            // animeert, het model wacht dezelfde duur en stapt dan door.
            canvas = .revealing(original: original, cutout: cutout)
            try? await Task.sleep(
                for: .seconds(IsolatingTiming.backgroundFade + IsolatingTiming.settle)
            )
            canvas = .result(cutout)
            // Eerste geslaagde cutout → quota mag zichtbaar worden (E05.1).
            entitlement.markFirstCutoutCompleted()
        } catch {
            canvas = .failed("Couldn't find a person in that photo. Try another portrait.")
        }
    }

    private func nsImage(from cgImage: CGImage) -> NSImage {
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
