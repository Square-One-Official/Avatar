// Main shell — importstate (E05.2). Drag-drop/bestandskiezer → PipelineRouter
// (Vision-engine als enige geregistreerde arm; ORMBG/cloud haken aan zodra
// hun settings-/entitlement-stories landen). De isolating-animatie met
// klaar- en faalstaat is E05.3 — hier alleen een minimale processing-staat.

import AppKit
import AvatarKit
import Observation
import SwiftData
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

    /// Sidebar/set (E05.4): Images-tool of avatar-toggle opent het paneel.
    var isSidebarVisible = false

    /// In-window Settings (visuele pass punt 14): vervangt de canvas-
    /// weergave als view-state; de topbar (quota + gear) blijft staan.
    /// Gear toggelt, Esc sluit.
    var isShowingSettings = false

    /// Geselecteerd portret in de set (E05.4); naam/rol schrijven door.
    private(set) var selectedPortrait: Portrait2?
    /// ModelContext komt uit de environment (ShellView .task) — SwiftData
    /// is pas ná init beschikbaar.
    @ObservationIgnored var modelContext: ModelContext?

    /// Naam/rol van het huidige portret (E05.5) — sinds E05.4 doorgeschreven
    /// naar het SwiftData-model Portrait2. Alleen een échte wijziging telt
    /// als bewerking voor updatedAt (punt 13): select() zet deze velden
    /// óók, en dat mag de sorteervolgorde niet verstoren.
    var portraitName = "" {
        didSet {
            guard let selectedPortrait, selectedPortrait.name != portraitName else { return }
            selectedPortrait.name = portraitName
            selectedPortrait.touch()
        }
    }
    var portraitRole = "" {
        didSet {
            guard let selectedPortrait, selectedPortrait.role != portraitRole else { return }
            selectedPortrait.role = portraitRole
            selectedPortrait.touch()
        }
    }

    private let entitlement: EntitlementModel

    /// Vision + ORMBG (E15.2): de voorkeur uit PrivacyPreferences2 bepaalt
    /// per import welk lokaal pad de router probeert; zonder geïnstalleerd
    /// model valt hij terug op Vision (eerste beschikbare).
    @ObservationIgnored
    private let router = PipelineRouter(engines: [VisionCutoutEngine(), OrmbgEngine()])

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
            let preferred: CutoutEngineKind =
                PrivacyPreferences2.shared.engine == .downloadedModel ? .ormbg : .vision
            let cutoutCG = try await router.cutout(cgImage, preferring: preferred)
            let cutout = nsImage(from: cutoutCG)
            // Reveal-fase (E05.3): achtergrond fadet naar donker; de view
            // animeert, het model wacht dezelfde duur en stapt dan door.
            canvas = .revealing(original: original, cutout: cutout)
            try? await Task.sleep(
                for: .seconds(IsolatingTiming.backgroundFade + IsolatingTiming.settle)
            )
            canvas = .result(cutout)
            // Eerste geslaagde cutout → quota mag zichtbaar worden (E05.1).
            entitlement.markFirstCutoutCompleted()
            persist(cutout: cutout, original: original)
            // E05.6: eenmalige nudge als de Vision-rand rafelig oogt en het
            // hifi-model nog niet binnen is.
            evaluateHairNudge(cutout: cutoutCG, usedEngine: preferred)
        } catch {
            canvas = .failed("Couldn't find a person in that photo. Try another portrait.")
        }
    }

    // MARK: - Set/sidebar (E05.4)

    /// Geslaagde cutout → nieuw portret in de set; wordt meteen de selectie.
    /// De originele importfoto gaat mee voor hold-to-compare (E06.2).
    private func persist(cutout: NSImage, original: NSImage) {
        guard let modelContext, let png = pngData(from: cutout) else { return }
        let portrait = Portrait2(cutoutData: png, originalData: pngData(from: original))
        modelContext.insert(portrait)
        select(portrait)
    }

    /// Selectie uit de sidebar: portret op canvas, naam/rol in de header.
    /// De selectie wordt onthouden (punt 13c) zodat een herstart hem kan
    /// herstellen.
    func select(_ portrait: Portrait2) {
        selectedPortrait = portrait
        portraitName = portrait.name
        portraitRole = portrait.role
        if let image = NSImage(data: portrait.cutoutData) {
            canvas = .result(image)
        }
        if let data = try? JSONEncoder().encode(portrait.persistentModelID) {
            UserDefaults.standard.set(data, forKey: Self.lastSelectedKey)
        }
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    // MARK: - Hifi-haar-nudge (E05.6)

    /// Subtiele, eenmalige nudge onder het resultaat.
    private(set) var showHairNudge = false
    private static let hairNudgeShownKey = "nudge.hifiHairShown"

    /// Toon de nudge alleen als: Vision-engine gebruikt, ORMBG niet
    /// geïnstalleerd, rand rafelig, en nog niet eerder getoond.
    private func evaluateHairNudge(cutout: CGImage, usedEngine: CutoutEngineKind) {
        guard usedEngine == .vision,
              !UserDefaults.standard.bool(forKey: Self.hairNudgeShownKey),
              OrmbgModelStore.shared.installedModelURL() == nil,
              HairEdgeHeuristic.isLikelyRagged(cutout: cutout)
        else { return }
        showHairNudge = true
    }

    #if DEBUG
    /// Smoke-run-haak: forceer de nudge zichtbaar.
    func debugForceHairNudge() { showHairNudge = true }

    /// Smoke-run-haak (E05.7): zorg voor ≥2 portretten door het geselecteerde
    /// te dupliceren, en open de sidebar.
    func debugSeedSecondPortraitAndOpenSidebar() {
        if let modelContext, let p = selectedPortrait {
            let copy = Portrait2(name: p.name, cutoutData: p.cutoutData, originalData: p.originalData)
            copy.backgroundColorHex = p.backgroundColorHex
            modelContext.insert(copy)
        }
        isSidebarVisible = true
    }
    #endif

    /// Wegklikken (×) — eenmalig, komt niet terug.
    func dismissHairNudge() {
        showHairNudge = false
        UserDefaults.standard.set(true, forKey: Self.hairNudgeShownKey)
    }

    /// "Download" op de nudge: start de achtergrond-download (gedeelde
    /// OrmbgModelStore-state met E04.6/E15.2), kies het model als engine,
    /// en sluit de nudge eenmalig af.
    func acceptHairNudge() {
        UserDefaults.standard.set(true, forKey: Self.hairNudgeShownKey)
        showHairNudge = false
        Task {
            _ = try? await OrmbgModelStore.shared.download()
            PrivacyPreferences2.shared.engine = .downloadedModel
        }
    }

    /// Er valt te exporteren zodra er een portret op het canvas staat.
    var canExport: Bool {
        if case .result = canvas { return selectedPortrait != nil }
        return false
    }

    /// E08.2: exporteer het huidige portret als vierkante PNG (1024) en open
    /// het share sheet. Free-tier krijgt een watermerk.
    func exportCurrentPortrait() {
        guard let selectedPortrait else { return }
        let watermark = !entitlement.isProActive
        guard let data = PortraitExporter.makePNG(for: selectedPortrait, watermark: watermark) else { return }
        PortraitExporter.share(data, from: nil)
    }

    // MARK: - Launch-selectie (visuele pass punt 13)

    private static let lastSelectedKey = "shell.lastSelectedPortraitID"

    /// Bij launch met een niet-lege set: herstel de laatst geselecteerde
    /// (persistentModelID uit UserDefaults, punt 13c), val terug op het
    /// portret met de jongste updatedAt (13b). De first-use-empty-state is
    /// uitsluitend voor een écht lege store. Doet onderweg de eenmalige
    /// migratie-fixup: rijen van vóór het updatedAt-veld (sentinel
    /// .distantPast) krijgen hun createdAt — de bedoelde default, die
    /// SwiftData's lichtgewicht migratie niet zelf kan invullen.
    func restoreSelectionAtLaunch() {
        guard case .empty = canvas, let modelContext else { return }
        let portraits = (try? modelContext.fetch(FetchDescriptor<Portrait2>())) ?? []
        guard !portraits.isEmpty else { return }

        for portrait in portraits where portrait.updatedAt == .distantPast {
            portrait.updatedAt = portrait.createdAt
        }

        var restored: Portrait2?
        if let data = UserDefaults.standard.data(forKey: Self.lastSelectedKey),
           let id = try? JSONDecoder().decode(PersistentIdentifier.self, from: data) {
            restored = portraits.first { $0.persistentModelID == id }
        }
        let fallback = portraits.max { $0.updatedAt < $1.updatedAt }
        if let target = restored ?? fallback {
            select(target)
        }
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    private func nsImage(from cgImage: CGImage) -> NSImage {
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
