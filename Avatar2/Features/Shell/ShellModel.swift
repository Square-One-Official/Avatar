// Main shell — importstate (E05.2). Drag-drop/bestandskiezer → PipelineRouter
// (Vision-engine als enige geregistreerde arm; ORMBG/cloud haken aan zodra
// hun settings-/entitlement-stories landen). De isolating-animatie met
// klaar- en faalstaat is E05.3 — hier alleen een minimale processing-staat.

import AppKit
import AvatarKit
import CoreImage
import Observation
import SwiftData
import UniformTypeIdentifiers

/// De Finder-stijl "lens" op de Portraits-collectie. Alleen actief op de
/// Portraits-surface; Home blijft een vaste, lens-vrije dashboard.
enum LibraryViewMode: String, CaseIterable, Identifiable {
    // Volgorde = de switcher-volgorde (allCases). Grid is de default → staat links.
    case grid, canvas, list, gallery
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .canvas:  "rectangle.3.group"
        case .grid:    "square.grid.2x2"
        case .list:    "list.bullet"
        case .gallery: "rectangle.split.3x1"
        }
    }
    var label: String {
        switch self {
        case .canvas:  "Canvas"
        case .grid:    "Grid"
        case .list:    "List"
        case .gallery: "Gallery"
        }
    }
}

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

    /// E27.7-fix: bij launch staat `canvas` op `.empty` tot `restoreSelectionAtLaunch`
    /// heeft bepaald wat te tonen, en een herstelde selectie decodeert daarna nog
    /// OFF-MAIN (`decodeCanvas`, ~1s). In beide vensters is er een portret op komst —
    /// geen first-use. Pas als de restore is geprobeerd én er geen (ladende) selectie
    /// is, weten we zeker dat de store leeg is.
    private(set) var didAttemptLaunchRestore = false

    /// Toont de view de first-use-empty-state (cirkels + dropzone)? Alleen bij een
    /// écht lege store — niet tijdens de launch-restore of een off-main select-decode,
    /// die `canvas` weliswaar even `.empty` laten maar wél een portret op komst hebben.
    var showsFirstUseEmptyState: Bool {
        guard case .empty = canvas else { return false }
        return didAttemptLaunchRestore && selectedPortrait == nil
    }

    /// E27.7: generatie-token voor het canvas. Élke nieuwe canvas-intentie
    /// (select/import/edit) bumpt 'm via `setCanvas`; een lopende async select-load
    /// (`decodeCanvas`) past z'n resultaat alléén toe als z'n generatie nog actueel
    /// is. Zo kan een trage decode geen nieuwere staat (een edit, een nieuwe selectie,
    /// een import) overschrijven.
    @ObservationIgnored private var canvasGeneration = 0
    /// De lopende off-main select-decode; bij een nieuwe selectie geannuleerd.
    @ObservationIgnored private var selectionLoadTask: Task<Void, Never>?

    /// Enige schrijf-pad naar `canvas` (op één na: `applyCanvasIfCurrent`): bumpt de
    /// generatie zodat een verouderde async load z'n resultaat niet meer toepast.
    private func setCanvas(_ state: CanvasState) {
        canvasGeneration += 1
        canvas = state
    }

    /// Past het resultaat van een async select-load toe, maar alléén als er geen
    /// nieuwere canvas-intentie tussendoor kwam.
    private func applyCanvasIfCurrent(_ state: CanvasState, generation: Int) {
        guard canvasGeneration == generation else { return }
        setCanvas(state)
    }

    /// Sidebar/set (E05.4): Images-tool of avatar-toggle opent het paneel.
    var isSidebarVisible = false

    // MARK: - App-navigatie (PoC: Granola-stijl left-nav)

    /// Top-level secties die de left-nav aanstuurt.
    /// `home` = overzicht (laatste + eerdere portretten / first-use), default;
    /// `portraits` = de map-grid (via de inklapbare Portraits-sectie in de nav);
    /// `editor` = één portret bewerken (de bestaande canvas). De top-right-
    /// iconen tonen alléén in `editor`.
    enum AppSection { case home, portraits, banners, editor }
    var section: AppSection = .home

    /// Welke map de Portraits-grid toont (nil = alle beelden).
    var selectedFolderID: PersistentIdentifier?

    /// Of de Portraits-sectie in de nav is uitgeklapt (toont de mappen).
    var isPortraitsExpanded = true

    /// De left-nav staat standaard open (Granola-stijl); inklapbaar.
    var isLeftNavVisible = true

    /// "Manage backgrounds"-sheet vanuit het gebruikersmenu in de left-nav.
    var isShowingManageBackgrounds = false

    func toggleLeftNav() { isLeftNavVisible.toggle() }
    func togglePortraitsExpanded() { isPortraitsExpanded.toggle() }

    /// Naar het overzicht (Home).
    func showHome() {
        isShowingSettings = false
        clearPortraitSelection()
        section = .home
    }

    /// Naar de Portraits-grid van een map (nil = alle beelden).
    func showPortraits(folderID: PersistentIdentifier? = nil) {
        isShowingSettings = false
        clearPortraitSelection()
        selectedFolderID = folderID
        section = .portraits
    }

    /// E35.2: naar de Banners-bibliotheek.
    func showBanners() {
        isShowingSettings = false
        clearPortraitSelection()
        section = .banners
    }

    /// Waar de editor vandaan geopend is — bepaalt waar "terug" (breadcrumb /
    /// back-chevron) naartoe keert.
    enum OpenOrigin: Equatable { case home; case portraits(PersistentIdentifier?) }
    private(set) var openOrigin: OpenOrigin = .home

    /// Open één portret in de editor (vanuit Home of een map-grid). Onthoudt de
    /// herkomst zodat `goBack()` naar de juiste surface terugkeert.
    func openPortrait(_ portrait: Portrait2) {
        isShowingSettings = false
        clearPortraitSelection()
        openOrigin = (section == .portraits) ? .portraits(selectedFolderID) : .home
        select(portrait)
        section = .editor
    }

    /// Terug vanuit de editor naar de herkomst-surface (Home of Portraits+map).
    func goBack() {
        switch openOrigin {
        case .home: showHome()
        case .portraits(let folderID): showPortraits(folderID: folderID)
        }
    }

    // MARK: - Multi-selectie (Finder-stijl, gedeeld over Home + Portraits-lenzen)

    /// Geselecteerde portretten — los van de canvas-selectie (`selectedPortrait`).
    /// Gedeeld over Home en alle Portraits-lenzen zodat rechtermuis + bulk-acties
    /// overal werken; wordt gewist bij navigatie (Home/Portraits/openen).
    var selectedPortraitIDs: Set<PersistentIdentifier> = []
    @ObservationIgnored private var selectionAnchorID: PersistentIdentifier?

    func isPortraitSelected(_ portrait: Portrait2) -> Bool {
        selectedPortraitIDs.contains(portrait.persistentModelID)
    }

    func clearPortraitSelection() {
        selectedPortraitIDs.removeAll()
        selectionAnchorID = nil
    }

    /// Klik op een tegel/rij: plain = openen (single-click-open blijft); ⌘ =
    /// toggle; ⇧ = bereik vanaf het anker in `ordered` (de zichtbare volgorde).
    func handlePortraitClick(_ portrait: Portrait2, ordered: [PersistentIdentifier], mods: NSEvent.ModifierFlags) {
        let id = portrait.persistentModelID
        if mods.contains(.command) {
            if selectedPortraitIDs.contains(id) { selectedPortraitIDs.remove(id) } else { selectedPortraitIDs.insert(id) }
            selectionAnchorID = id
        } else if mods.contains(.shift), let anchor = selectionAnchorID,
                  let from = ordered.firstIndex(of: anchor), let to = ordered.firstIndex(of: id) {
            for pid in ordered[min(from, to)...max(from, to)] { selectedPortraitIDs.insert(pid) }
        } else {
            openPortrait(portrait)
        }
    }

    /// Set-brede voortgang (Align/Match/Export) als toast; ShellView toont 'm.
    var setBusyMessage: String?

    /// Pro-status voor het bulk-export-watermerk (`entitlement` is privé).
    var isPro: Bool { entitlement.isProActive }

    // MARK: - Portraits view-mode (Finder-stijl lens; alleen op de Portraits-surface)

    /// De gekozen lens op de Portraits-grid. Persistent (UserDefaults), globaal
    /// (niet per map). Default `.grid` — wat er nu staat. Home is lens-vrij.
    /// Default-lens op de Portraits-surface = grid (besluit Thierry). NIET meer
    /// cross-launch persistent — elke start opent in grid; binnen de sessie
    /// onthoudt het model je gekozen lens.
    var portraitsViewMode: LibraryViewMode = .grid

    func setPortraitsViewMode(_ mode: LibraryViewMode) {
        portraitsViewMode = mode
    }

    /// In-window Settings (visuele pass punt 14): vervangt de canvas-
    /// weergave als view-state; de topbar (quota + gear) blijft staan.
    /// Gear toggelt, Esc sluit.
    var isShowingSettings = false

    /// E19.1: Share/export-popup (DS) i.p.v. direct het macOS share-sheet.
    var isShowingExport = false

    /// E34.5: social-preview-overlay (LinkedIn/X/Instagram-in-context + banner).
    /// Vervangt — met een crossfade — de editor; de ✕ in de preview sluit 'm.
    var isShowingSocialPreview = false

    /// E24.21: gedeelde rename-modal (Name + Role), geopend vanuit de
    /// Name/Role-knop op het canvas (sidebar gebruikt z'n eigen renameTarget).
    var isShowingRename = false

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
            setCanvas(.failed("That file doesn't look like an image we can read."))
            return
        }
        await runCutout(on: cgImage)
    }

    func importImage(data: Data) async {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            setCanvas(.failed("That file doesn't look like an image we can read."))
            return
        }
        await runCutout(on: cgImage)
    }

    private func runCutout(on cgImage: CGImage) async {
        // E14.2: free-tier importgate (3 lifetime, source-agnostic) vóór elke
        // import. Cap bereikt → paywall is getoond, geen canvas-wijziging.
        guard await entitlement.claimImport() else { return }
        let original = nsImage(from: cgImage)
        setCanvas(.processing(original))
        do {
            let preferred: CutoutEngineKind =
                PrivacyPreferences2.shared.engine == .downloadedModel ? .ormbg : .vision
            let cutoutCG = try await router.cutout(cgImage, preferring: preferred)
            let cutout = nsImage(from: cutoutCG)
            // Reveal-fase (E05.3): achtergrond fadet naar donker; de view
            // animeert, het model wacht dezelfde duur en stapt dan door.
            setCanvas(.revealing(original: original, cutout: cutout))
            try? await Task.sleep(
                for: .seconds(IsolatingTiming.backgroundFade + IsolatingTiming.settle)
            )
            setCanvas(.result(cutout))
            // Eerste geslaagde cutout → quota mag zichtbaar worden (E05.1).
            entitlement.markFirstCutoutCompleted()
            persist(cutout: cutout, original: original)
            // E05.6: eenmalige nudge als de Vision-rand rafelig oogt en het
            // hifi-model nog niet binnen is.
            evaluateHairNudge(cutout: cutoutCG, usedEngine: preferred)
        } catch {
            setCanvas(.failed("Couldn't find a person in that photo. Try another portrait."))
        }
    }

    // MARK: - Set/sidebar (E05.4)

    /// Geslaagde cutout → nieuw portret in de set; wordt meteen de selectie.
    /// De originele importfoto gaat mee voor hold-to-compare (E06.2).
    private func persist(cutout: NSImage, original: NSImage) {
        guard let modelContext, let png = cutout.pngData() else { return }
        let portrait = Portrait2(cutoutData: png, originalData: original.pngData())
        modelContext.insert(portrait)
        select(portrait)
        // PoC (left-nav): een verse import opent meteen de editor (top-right-
        // chrome verschijnt) i.p.v. op Home/Portraits te blijven; "terug" → Home.
        openOrigin = .home
        section = .editor
    }

    /// Selectie uit de sidebar: portret op canvas, naam/rol in de header.
    /// De selectie wordt onthouden (punt 13c) zodat een herstart hem kan
    /// herstellen.
    func select(_ portrait: Portrait2) {
        // E27.7: de canvas-onafhankelijke selectie-state zet meteen → de sidebar-/
        // board-highlight + de naam/rol-header reageren DIRECT. De zware full-res
        // decode + Adjust-laag draait OFF-MAIN (decodeCanvas), zodat de main-thread
        // niet ~1s blokkeert; het canvas volgt async (generatie-getoetst).
        selectedPortrait = portrait
        portraitName = portrait.name
        portraitRole = portrait.role
        if let data = try? JSONEncoder().encode(portrait.persistentModelID) {
            UserDefaults.standard.set(data, forKey: Self.lastSelectedKey)
        }

        canvasGeneration += 1
        let generation = canvasGeneration
        let data = portrait.cutoutData
        let adjust = portrait.adjust
        selectionLoadTask?.cancel()
        selectionLoadTask = Task { [weak self] in
            let boxed = await Self.decodeCanvas(data: data, adjust: adjust)
            guard !Task.isCancelled, let self, let image = boxed?.image else { return }
            // E24.14: canvas toont de rauwe cutout mét de niet-destructieve
            // Adjust-laag erbovenop (WYSIWYG).
            self.applyCanvasIfCurrent(.result(image), generation: generation)
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
    func applyEffectResult(_ image: NSImage, preserveSourceAlpha: Bool = false) {
        guard let portrait = selectedPortrait else {
            setCanvas(.result(image))
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
                let restored: NSImage
                if preserveSourceAlpha,
                   let cutout = NSImage(data: portrait.cutoutData),
                   let masked = Self.applyAlphaMask(from: cutout, to: image) {
                    // Effects/face-edits veranderen uiterlijk maar niet de vorm →
                    // gebruik de huidige cutout-alpha als masker i.p.v. Vision
                    // opnieuw te draaien op een geschilderd/artistiek beeld.
                    restored = masked
                } else {
                    restored = (try? await self.reIsolateSubject(image)) ?? image
                }
                self.storeEffectResult(restored, on: portrait)
            }
        } else {
            storeEffectResult(image, on: portrait)
        }
    }

    /// Past de alpha-laag van een bestaande cutout toe op een opaque (vol-achtergrond)
    /// beeld. Gebruikt door Effects/Face-edits zodat de lichaamsvorm bewaard blijft
    /// zonder Vision opnieuw op een artistiek gestyled beeld te draaien.
    nonisolated static func applyAlphaMask(from cutout: NSImage, to rgbImage: NSImage) -> NSImage? {
        guard let cutoutCG = cutout.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rgbCG = rgbImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let cutoutCI = CIImage(cgImage: cutoutCG)
        var rgbCI = CIImage(cgImage: rgbCG)

        // Schaal het gestylede beeld naar de afmetingen van de cutout (backend
        // rendert op ~1 MP, de cutout kan een andere resolutie hebben).
        let sw = cutoutCI.extent.width / rgbCI.extent.width
        let sh = cutoutCI.extent.height / rgbCI.extent.height
        if abs(sw - 1) > 0.005 || abs(sh - 1) > 0.005 {
            rgbCI = rgbCI.transformed(by: CGAffineTransform(scaleX: sw, y: sh))
        }

        // Pas de alpha van de cutout toe als masker op de gestylede RGB-pixels.
        // CIBlendWithAlphaMask: inputImage * mask.alpha + background * (1 - mask.alpha)
        let masked = rgbCI.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            "inputMaskImage": cutoutCI
        ])

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        let size = CGSize(width: cutoutCG.width, height: cutoutCG.height)
        guard let out = ctx.createCGImage(masked, from: CGRect(origin: .zero, size: size)) else {
            return nil
        }
        return NSImage(cgImage: out, size: NSSize(width: size.width, height: size.height))
    }

    /// E24.30: schrijf het bewerkte beeld weg als nieuwe rauwe cutout en
    /// her-render het canvas met de niet-destructieve Adjust-laag erbovenop.
    private func storeEffectResult(_ image: NSImage, on portrait: Portrait2) {
        // E24.36: de opgeslagen transform (offsetX/offsetY/scale) is in absolute
        // bronpixels uitgedrukt. Een generatieve edit (nano-banana) houdt wél de RATIO
        // aan (aspect_ratio: match_input_image) maar niet de exacte pixelmaat
        // (Gemini rendert op ~1 MP) → dezelfde transform op een ander formaat
        // verspringt het beeld. Hybride correctie:
        //   • ratio (vrijwel) gelijk → schaal terug naar de exacte oude pixelmaat;
        //     de transform blijft geldig, de gebruiker behoudt zijn positie.
        //   • model gaf een echt andere ratio → reset + her-kadreer op het gezicht.
        let oldCG = NSImage(data: portrait.cutoutData)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
        let newCG = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        var stored = image
        var didReset = false
        if let oldCG, let newCG, oldCG.width > 0, oldCG.height > 0,
           oldCG.width != newCG.width || oldCG.height != newCG.height {
            let oldRatio = Double(oldCG.width) / Double(oldCG.height)
            let newRatio = Double(newCG.width) / Double(newCG.height)
            let drift = abs(newRatio - oldRatio) / oldRatio
            let oldSize = CGSize(width: oldCG.width, height: oldCG.height)
            if drift < 0.02, let resized = Self.resized(newCG, to: oldSize) {
                stored = resized
            } else {
                portrait.offsetX = 0; portrait.offsetY = 0; portrait.scale = 0
                didReset = true
            }
        }
        if let png = stored.pngData() {
            portrait.cutoutData = png
            portrait.touch()
        }
        setCanvas(.result(Self.adjustedImage(stored, portrait.adjust)))
        // Alleen her-kadreren bij een echte ratio-wijziging (transform gereset);
        // het resize-pad behoudt bewust de handmatige positie. Stille correctie,
        // geen undo-stap. (Randgeval: een undo ná de reset-tak her-kadreert i.p.v.
        // de exacte pre-edit-transform te herstellen — zeldzaam, de cutout zelf
        // wordt wél correct teruggedraaid.)
        if didReset, let cg = stored.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let p = portrait
            Task { await AutoFramer.apply(to: p, image: cg) }
        }
    }

    /// Schaal een CGImage naar exacte pixelafmetingen (alpha behouden). Houdt een
    /// generatief resultaat met dezelfde ratio maar andere pixelmaat op de oude
    /// afmetingen, zodat de bestaande canvas-transform geldig blijft.
    /// `nonisolated` (zoals `hasTransparentCorners`) → unit-testbaar buiten de actor.
    nonisolated static func resized(_ cg: CGImage, to size: CGSize) -> NSImage? {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: w, height: h))
    }

    /// Restore-body path: explicit re-isolation without fallback — throws on failure
    /// so callers can surface an error instead of silently applying the background.
    func isolateSubject(_ image: NSImage) async throws -> NSImage {
        try await reIsolateSubject(image)
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
        // Perf: voorheen werd de héle bitmap uitgepakt (bytesPerRow×h, ~16MB bij
        // 2048px) om 4 hoek-alpha's te lezen. Sample nu elke hoek via een
        // 1×1-context (zelfde truc als isOpaqueAtNormalizedPoint) → constante tijd.
        func cornerAlpha(_ x: Int, _ y: Int) -> UInt8 {
            var pixel: [UInt8] = [0, 0, 0, 0]
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(
                    data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return 255 }
            ctx.interpolationQuality = .none
            // CG-origin = linksonder; rij y (van boven) ligt op CG-y = h-1-y.
            ctx.draw(cg, in: CGRect(x: -x, y: -(h - 1 - y), width: w, height: h))
            return pixel[3]
        }
        let corners = [cornerAlpha(0, 0), cornerAlpha(w - 1, 0),
                       cornerAlpha(0, h - 1), cornerAlpha(w - 1, h - 1)]
        // vrijstaand als minstens 3 van de 4 hoeken (bijna) transparant zijn
        return corners.filter { $0 < 16 }.count >= 3
    }

    /// E22.3: goedkope live-preview voor de color-sliders — alléén het canvas,
    /// niet cutoutData (geen PNG-encode per tick). De commit gaat via
    /// `commitAdjust` (+ undo). Het paneel levert hier al de geadjusteerde
    /// NSImage aan.
    func previewCanvas(_ image: NSImage) {
        setCanvas(.result(image))
    }

    /// E24.14: commit de Adjust-laag op het geselecteerde portret (niet-
    /// destructief) en hercomputeer het canvas. Undo/redo loopt via dezelfde
    /// closure (AdjustUndo). cutoutData blijft ongemoeid.
    func commitAdjust(_ adjust: PortraitAdjust) {
        guard let portrait = selectedPortrait else { return }
        portrait.adjust = adjust
        portrait.touch()
        if let raw = NSImage(data: portrait.cutoutData) {
            setCanvas(.result(Self.adjustedImage(raw, adjust)))
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
        setCanvas(.result(Self.adjustedImage(raw, portrait.adjust)))
    }

    /// E24.14: pas de niet-destructieve Adjust-laag toe op een rauwe cutout.
    /// Neutraal → het origineel ongewijzigd (geen render-overhead). `nonisolated
    /// static` (pure functie) zodat zowel de main-actor-paden als de off-main
    /// `decodeCanvas` 'm kunnen aanroepen.
    nonisolated static func adjustedImage(_ raw: NSImage, _ adjust: PortraitAdjust) -> NSImage {
        guard !adjust.isNeutral,
              let cg = raw.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let out = PortraitEnhancer.colorAdjust(
                cg, brightness: adjust.brightness, contrast: adjust.contrast,
                saturation: adjust.saturation, temperatureShift: adjust.temperature
              ) else { return raw }
        return NSImage(cgImage: out, size: raw.size)
    }

    /// E27.7: off-main full-res decode + Adjust-laag voor het select-canvas. Draait
    /// op de coöperatieve pool (`nonisolated async`), niet op de main-thread.
    /// Behoudt exact de oude semantiek: `NSImage(data:)` (zelfde maat) + `adjustedImage`.
    private nonisolated static func decodeCanvas(data: Data, adjust: PortraitAdjust) async -> SendableNSImage? {
        guard let raw = NSImage(data: data) else { return nil }
        return SendableNSImage(image: adjustedImage(raw, adjust))
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
        selectedPortrait?.setBackground(.transparent)
    }

    /// E24.31 smoke-haak: zet de Original-achtergrondmodus (toont de originele
    /// foto vol) of terug naar transparant (vrijstaande cutout).
    func debugSetOriginalBackground(_ on: Bool) {
        selectedPortrait?.setBackground(on ? .original : .transparent)
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
        p.setBackground(.image(data))
    }

    /// E24.24 smoke-haak: simuleer uploadCustom via de persistente kit (zonder
    /// NSOpenPanel) — voegt een swatch toe én zet 'm als achtergrond.
    func debugUploadBackground(path: String) {
        guard let p = selectedPortrait,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
        let stored = BackgroundImageKit.shared.add(data) ?? data
        p.setBackground(.image(stored))
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

    /// E34.5: previewen kan zodra er een afgewerkt portret op het canvas staat
    /// (dezelfde voorwaarde als exporteren).
    var canPreview: Bool { canExport }

    /// E34.5: open de social-preview-overlay.
    func showSocialPreview() {
        guard selectedPortrait != nil else { return }
        isShowingSocialPreview = true
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
        // E27.7-fix: markeer de restore als geprobeerd → de view mag de first-use-
        // empty-state pas tonen zodra hieruit blijkt dat de store leeg is. Vóór dit
        // punt (en tijdens de off-main select-decode) toont de view een neutrale
        // canvas-achtergrond i.p.v. de cirkels (zie `showsFirstUseEmptyState`).
        didAttemptLaunchRestore = true
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

    private func nsImage(from cgImage: CGImage) -> NSImage {
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

/// E27.7: `NSImage` is niet Sendable. `decodeCanvas` maakt 'm OFF-MAIN en reikt 'm
/// via deze box terug; daarna wordt 'ie alléén op de main-actor gelezen (geen
/// gedeelde mutatie) → veilig over de actor-grens onder `targeted` strict-concurrency.
private struct SendableNSImage: @unchecked Sendable {
    let image: NSImage
}
