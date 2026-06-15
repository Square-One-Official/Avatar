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

    /// E19.1: Share/export-popup (DS) i.p.v. direct het macOS share-sheet.
    var isShowingExport = false

    /// E24.21: gedeelde rename-modal (Name + Role), geopend vanuit de
    /// Name/Role-knop op het canvas (sidebar gebruikt z'n eigen renameTarget).
    var isShowingRename = false

    /// E27.4: board-modus — toont alle portretten op één canvas (BoardView)
    /// i.p.v. de enkel-portret-editor. Toggle via de app-bar; klik een portret op
    /// het board → editor (deze vlag weer uit).
    var isBoardMode = false

    func toggleBoard() { isBoardMode.toggle() }

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
        #if DEBUG
        // Smoke-run-haak (`--show-settings [pagina]`): zet de settings-view
        // vóór de first render i.p.v. in ShellView's .task. Een post-render
        // state-write hier raakte onder .windowStyle(.hiddenTitleBar) in een
        // venster-presentatie-race zodra een tweede launch-conditie (bv.
        // --dev-advanced) de opstart-timing verschoof. Pre-render = geen race.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--show-settings") {
            isShowingSettings = true
            if args.indices.contains(i + 1),
               let page = SettingsPage(rawValue: args[i + 1]) {
                SettingsRootView.debugInitialPage = page
            }
        }
        #endif
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
        // E14.2: free-tier importgate (3 lifetime, source-agnostic) vóór elke
        // import. Cap bereikt → paywall is getoond, geen canvas-wijziging.
        guard await entitlement.claimImport() else { return }
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
        if let raw = NSImage(data: portrait.cutoutData) {
            // E24.14: canvas toont de rauwe cutout mét de niet-destructieve
            // Adjust-laag erbovenop (WYSIWYG).
            canvas = .result(adjustedImage(raw, portrait.adjust))
        }
        if let data = try? JSONEncoder().encode(portrait.persistentModelID) {
            UserDefaults.standard.set(data, forKey: Self.lastSelectedKey)
        }
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    /// E09.2: een door een feature-paneel bewerkt portret-beeld (Effects-
    /// stijl, later kleding/haar) vervangt het canvas-resultaat én het
    /// opgeslagen cutout. Het canvas toont de NSImage uit `canvas`, niet uit
    /// het model — beide moeten dus mee, anders blijft de oude foto staan.
    /// E24.14: destructieve ops bewerken de RAUWE cutout; de Adjust-laag blijft
    /// orthogonaal en wordt opnieuw bovenop gerenderd (canvas = adjust(raw)).
    func applyEffectResult(_ image: NSImage) {
        guard let portrait = selectedPortrait else {
            canvas = .result(image)
            return
        }
        // E24.30: een generatieve stylize (nano-banana) levert een VOL beeld
        // mét achtergrond → de alpha is weg. Was de bron vrijstaand (transparante
        // hoeken op de huidige cutout) én heeft het resultaat een dichte
        // achtergrond (opake hoeken) → isoleer het onderwerp opnieuw zodat de
        // transparantie terugkomt. Niet-genererende ops (flip/enhance/boost)
        // behouden hun alpha → resultaat al transparant → geen her-isolatie.
        let sourceFreestanding = Self.hasTransparentCorners(NSImage(data: portrait.cutoutData))
        let resultHasBackground = !Self.hasTransparentCorners(image)
        if sourceFreestanding && resultHasBackground {
            Task { @MainActor in
                let restored = (try? await self.reIsolateSubject(image)) ?? image
                self.storeEffectResult(restored, on: portrait)
            }
        } else {
            storeEffectResult(image, on: portrait)
        }
    }

    /// E24.30: schrijf het bewerkte beeld weg als nieuwe rauwe cutout en
    /// her-render het canvas met de niet-destructieve Adjust-laag erbovenop.
    private func storeEffectResult(_ image: NSImage, on portrait: Portrait2) {
        if let png = pngData(from: image) {
            portrait.cutoutData = png
            portrait.touch()
        }
        canvas = .result(adjustedImage(image, portrait.adjust))
    }

    /// E24.30: her-isoleer het onderwerp uit een styled (vol) beeld met de
    /// lokale router (zelfde engine-voorkeur als import) → transparantie terug.
    private func reIsolateSubject(_ image: NSImage) async throws -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let preferred: CutoutEngineKind =
            PrivacyPreferences2.shared.engine == .downloadedModel ? .ormbg : .vision
        let cut = try await router.cutout(cg, preferring: preferred)
        return nsImage(from: cut)
    }

    /// E24.30: heuristiek "is dit beeld vrijstaand?" — sample de 4 hoeken; een
    /// cutout heeft (vrijwel) transparante hoeken, een vol beeld opake.
    nonisolated static func hasTransparentCorners(_ image: NSImage?) -> Bool {
        guard let image,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return false }
        let bytesPerRow = w * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * h)
        guard let ctx = CGContext(
            data: &buffer, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        func alpha(_ x: Int, _ y: Int) -> UInt8 { buffer[y * bytesPerRow + x * 4 + 3] }
        let corners = [alpha(0, 0), alpha(w - 1, 0), alpha(0, h - 1), alpha(w - 1, h - 1)]
        // vrijstaand als minstens 3 van de 4 hoeken (bijna) transparant zijn
        return corners.filter { $0 < 16 }.count >= 3
    }

    /// E22.3: goedkope live-preview voor de color-sliders — alléén het canvas,
    /// niet cutoutData (geen PNG-encode per tick). De commit gaat via
    /// `commitAdjust` (+ undo). Het paneel levert hier al de geadjusteerde
    /// NSImage aan.
    func previewCanvas(_ image: NSImage) {
        canvas = .result(image)
    }

    /// E24.14: commit de Adjust-laag op het geselecteerde portret (niet-
    /// destructief) en hercomputeer het canvas. Undo/redo loopt via dezelfde
    /// closure (AdjustUndo). cutoutData blijft ongemoeid.
    func commitAdjust(_ adjust: PortraitAdjust) {
        guard let portrait = selectedPortrait else { return }
        portrait.adjust = adjust
        portrait.touch()
        if let raw = NSImage(data: portrait.cutoutData) {
            canvas = .result(adjustedImage(raw, adjust))
        }
    }

    /// E18.4: her-afleidt het canvas uit de cutoutData van het geselecteerde
    /// portret. Set-brede edits (Match lighting, Align Set) wijzigen alleen
    /// cutoutData via CutoutDataUndo — niet het canvas. Wordt aangeroepen na
    /// elke undo/redo zodat zo'n wijziging (en het terugdraaien ervan) ook op
    /// het canvas zichtbaar wordt. No-op buiten de result-staat.
    /// E24.14: render altijd mét de Adjust-laag erbovenop.
    func refreshCanvasFromSelection() {
        guard case .result = canvas,
              let portrait = selectedPortrait,
              let raw = NSImage(data: portrait.cutoutData) else { return }
        canvas = .result(adjustedImage(raw, portrait.adjust))
    }

    /// E24.14: pas de niet-destructieve Adjust-laag toe op een rauwe cutout.
    /// Neutraal → het origineel ongewijzigd (geen render-overhead).
    private func adjustedImage(_ raw: NSImage, _ adjust: PortraitAdjust) -> NSImage {
        guard !adjust.isNeutral,
              let cg = raw.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let out = PortraitEnhancer.colorAdjust(
                cg, brightness: adjust.brightness, contrast: adjust.contrast,
                saturation: adjust.saturation, temperatureShift: adjust.temperature
              ) else { return raw }
        return NSImage(cgImage: out, size: raw.size)
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

    /// E24.14 smoke-haak: zet een zichtbare niet-destructieve Adjust-stand op
    /// het geselecteerde portret (warm + helder) en hercomputeer het canvas.
    /// Bewijst dat cutoutData rauw blijft terwijl canvas/export de laag tonen.
    func debugSeedAdjust() {
        commitAdjust(PortraitAdjust(brightness: 0.18, contrast: 1.15, saturation: 1.4, temperature: 0.6))
    }

    /// E24.14 smoke-haak: zet de Adjust-laag terug op neutraal (inverse van
    /// debugSeedAdjust) — laat de dev-store schoon achter voor andere smokes.
    func debugResetAdjust() { commitAdjust(.neutral) }

    /// E24.16 smoke-haak: zet de frame-vorm op het geselecteerde portret.
    func debugSetFrameShape(_ shape: ExportShape) {
        selectedPortrait?.frameShape = shape
        selectedPortrait?.touch()
    }

    /// E24.26 smoke-haak: wis de achtergrond (→ dot-grid actief) om te checken
    /// dat card-surface + dot-grid naar de frame-vorm clippen (hoeken zwart).
    func debugClearBackground() {
        selectedPortrait?.backgroundColorHex = nil
        selectedPortrait?.backgroundImageData = nil
        selectedPortrait?.touch()
    }

    /// E24.31 smoke-haak: zet de Original-achtergrondmodus (toont de originele
    /// foto vol) of terug naar transparant (vrijstaande cutout).
    func debugSetOriginalBackground(_ on: Bool) {
        guard let p = selectedPortrait else { return }
        p.useOriginalBackground = on
        if on { p.backgroundColorHex = nil; p.backgroundImageData = nil }
        p.touch()
    }

    /// E24.18 smoke-haak: reset de canvas-transform naar "geen transform"
    /// (scale 0) zodat de padded fit-fallback (frame-ademruimte) zichtbaar is —
    /// de staat van een vers geïmporteerd portret.
    func debugResetTransform() {
        guard let p = selectedPortrait else { return }
        p.offsetX = 0; p.offsetY = 0; p.scale = 0
        p.touch()
    }

    /// E27.3 smoke-haak: schaal het ONDERWERP groot (factor × de fit-schaal,
    /// gecentreerd) zodat de transform-hoeken buiten het frame vallen — om te
    /// tonen dat je via de camera kunt uitzoomen om ze weer te zien.
    func debugScaleSubject(factor: Double) {
        guard let p = selectedPortrait, let img = NSImage(data: p.cutoutData) else { return }
        let canvas = FramingConstants.editCanvas
        guard img.size.width > 0, img.size.height > 0 else { return }
        let fit = min(canvas.width / img.size.width, canvas.height / img.size.height)
            * FramingConstants.frameFitPadding
        let scale = fit * factor
        p.offsetX = (canvas.width - img.size.width * scale) / 2
        p.offsetY = (canvas.height - img.size.height * scale) / 2
        p.scale = scale
        p.touch()
    }

    /// E24.23 smoke-haak: zet een achtergrond-afbeelding vanaf een pad (zoals
    /// uploadCustom, maar zonder de NSOpenPanel) om de upload-bug te reproduceren
    /// + de fix te verifiëren met grote/kleine afbeeldingen.
    func debugSetBackgroundImage(path: String) {
        guard let p = selectedPortrait,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
        p.backgroundImageData = data
        p.backgroundColorHex = nil
        p.touch()
    }

    /// E24.24 smoke-haak: simuleer uploadCustom via de persistente kit (zonder
    /// NSOpenPanel) — voegt een swatch toe én zet 'm als achtergrond.
    func debugUploadBackground(path: String) {
        guard let p = selectedPortrait,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
        let stored = BackgroundImageKit.shared.add(data) ?? data
        p.backgroundImageData = stored
        p.backgroundColorHex = nil
        p.touch()
    }

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
    /// E19.1: opent de DS-export-popup (vorm/maat + Save/Share).
    func exportCurrentPortrait() {
        guard selectedPortrait != nil else { return }
        isShowingExport = true
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
