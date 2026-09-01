// Editor-framework (E06.1, Figma: App / Edit 4008:7340). Het raamwerk waar
// alle feature-panelen in hangen: DSEditPanelContainer (E03.3) regelt
// toolbar, actief paneel en het centrale foto-verkleint-gedrag. De zes
// tools volgen het frame; iconen benaderen de gerenderde Figma-glyphs met
// SF Symbols (de icon-lagen in Figma heten nog allemaal
// "square.and.arrow.up" — namen zijn stale, de render is de bron).
// Panelen zelf zijn latere stories (6.3 Edit, E07 Background, E09 Effects,
// E10 Clothes, E11 Hair, E05.4 Images/sidebar) en tonen tot die landen een
// lege paneel-chrome. Undo/redo naast de toolbar komen met E06.2.

import AppKit
import AvatarKit
import AvatarUI
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    // E21.1: Face-tool tussen Effects en Clothing (beauty-acties uit Edit).
    case edit, effects, face, clothing, hair, background, images

    var id: String { rawValue }

    var label: String {
        switch self {
        case .edit: "Edit"
        case .effects: "Effects"
        case .face: "Face"
        case .clothing: "Clothing"
        case .hair: "Hair"
        case .background: "Background"
        case .images: "Images"
        }
    }

    /// E20.1: semantisch DSIcon per tool (de toolbar schakelt hierop in 21.2).
    var dsSymbol: DSIcon.Symbol {
        switch self {
        case .edit: .edit
        case .effects: .effects
        case .face: .face
        case .clothing: .clothing
        case .hair: .hair
        case .background: .background
        case .images: .images
        }
    }

    /// SF-benadering van de toolbar-glyphs (tot 21.2 de toolbar op DSIcon zet).
    var icon: Image {
        switch self {
        case .edit: Image(systemName: "paintpalette")  // E22.3: kleur-glyph
        case .effects: Image(systemName: "sparkles")
        case .face: Image(systemName: "face.smiling")
        case .clothing: Image(systemName: "tshirt.fill")
        case .hair: Image(systemName: "comb.fill")
        case .background: Image(systemName: "person.and.background.dotted")
        case .images: Image(systemName: "photo.on.rectangle.angled")
        }
    }

    /// De story die het echte paneel levert (zichtbaar in de stub-copy
    /// zolang het paneel er niet is).
    var pendingStory: String {
        switch self {
        case .edit: "E06.3"
        case .effects: "E09.2"
        case .face: "E21.1"
        case .clothing: "E10.2"
        case .hair: "E11.2"
        case .background: "E07.1"
        case .images: "E05.4"
        }
    }
}

struct EditorView: View {
    /// E-fix (bug: een nieuwe foto verving het hele scherm): tijdens een
    /// VERVANGENDE import (er staat al een portret op het canvas) blijft de
    /// editor-scaffold (toolbar + naam-frame) staan en speelt de isolating-reveal
    /// ÍN het frame i.p.v. het hele scherm te vervangen. nil = normale
    /// result-modus (cutout klaar). De `original`/`cutout` komen rechtstreeks uit
    /// de ShellModel-canvasstaat, niet uit het (nog) geselecteerde portret.
    enum IsolatingPhase {
        case processing(NSImage)
        case revealing(original: NSImage, cutout: NSImage)

        var original: NSImage {
            switch self {
            case .processing(let original): original
            case .revealing(let original, _): original
            }
        }
        var cutout: NSImage? {
            switch self {
            case .processing: nil
            case .revealing(_, let cutout): cutout
            }
        }
    }

    let portrait: NSImage
    /// Model-referentie voor de persistente canvas-transform (E06.4);
    /// nil = transform alleen in-memory (komt in de praktijk niet voor).
    var portraitModel: Portrait2?
    /// E09.2: Effects-paneel heeft het entitlement nodig voor de gegate
    /// stylize-call (credits/402); nil = paneel valt terug op de stub.
    var entitlement: EntitlementModel?
    /// E09.2: een bewerkt portret-beeld terug naar de ShellModel (canvas +
    /// opgeslagen cutout vervangen).
    var onApplyResult: (NSImage) -> Void = { _ in }
    /// Effects/face-edits: zelfde als onApplyResult maar bewaart de bestaande
    /// cutout-alpha als masker i.p.v. Vision opnieuw te draaien op een
    /// artistiek gestyled beeld (→ ShellModel.applyEffectResult preserveSourceAlpha).
    var onApplyAlphaPreserving: (NSImage) -> Void = { _ in }
    /// Restore body: re-run cutout engine on the original photo; throws so the
    /// caller can show an error rather than silently leaking the background.
    var onIsolateSubject: (NSImage) async throws -> NSImage = { $0 }
    /// E22.3: goedkope live-preview (alleen canvas) voor de color-sliders.
    var onPreview: (NSImage) -> Void = { _ in }
    /// E24.14: commit van de niet-destructieve Adjust-laag (params persisteren
    /// op het portret + canvas hercomputeren). Undo loopt via dezelfde closure.
    var onCommitAdjust: (PortraitAdjust) -> Void = { _ in }
    /// E33: dubbelklik op de naam-chip opent de rename-modal (ShellView levert de
    /// closure die `model.isShowingRename` zet — zoals de oude PortraitHeader-knop).
    var onRename: () -> Void = {}
    /// E-fix: niet-nil → render de isolating-reveal ín het frame en zet de
    /// onderwerp-afhankelijke bediening (feature-tools, frame-acties) inert.
    var isolating: IsolatingPhase? = nil
    /// Images-tool is geen bottom-paneel maar de sidebar-toggle (E05.4):
    /// de lime ring volgt de sidebar-staat, het paneel blijft leeg.
    @Binding var isSidebarVisible: Bool
    @State private var activeTool: EditorTool?
    /// E24.12: open canvas-toolbar-dropdown (caret-loze DS-kaart). Hier zodat
    /// een klik op de canvas 'm sluit — net als de bottom-panelen.
    @State private var canvasMenu: CanvasToolbarMenu?
    // Perf (P2): cutout/original/achtergrond één keer gedecodeerd per edit
    // (gekeyd op updatedAt + id) i.p.v. bij élke body-pass — zie refreshDecodedImages().
    @State private var decodedCutout: NSImage?
    @State private var decodedOriginal: NSImage?
    @State private var decodedBackground: NSImage?
    /// E27.1: de canvas-camera (VIEW-zoom + pan over de HELE scène). Vervangt de
    /// per-onderwerp `canvasViewZoom` uit 24.8/24.17. Efemeer (geen persist) en
    /// hier zodat de transform BUITEN EditorCanvasView op de DSCanvasCard hangt.
    @State private var camera = CanvasCamera()
    /// E-fix: cursor staat boven een open menu/paneel → de canvas-catcher laat
    /// scroll/pinch dóór (anders scrollt het canvas i.p.v. het menu).
    @State private var pointerOverChrome = false
    /// E24.26: grid/thirds-overlay aan/uit (toolbar-toggle).
    @State private var canvasGridEnabled = false
    /// E24.29: onderwerp geselecteerd (gelift uit EditorCanvasView) zodat het
    /// dot-grid tijdens transform gedimd kan worden. E28.1: dit is de single
    /// source of truth van de editor-selectie — standaard TRUE (bij openen is het
    /// portret geselecteerd zodat de toolbars meteen zichtbaar zijn) en het
    /// E28.5: in de enkel-portret-editor is het portret altijd "het actieve
    /// canvas" → de toolbars zijn ALTIJD zichtbaar (selectie-gestuurd verbergen
    /// hoort bij meerdere canvassen, de board). Deze vlag stuurt nu enkel nog de
    /// transform-HANDLES (klik op het onderwerp → handles; klik op lege canvas /
    /// ESC → handles weg). Default false (geen handles tot je het onderwerp kiest).
    @State private var canvasSubjectSelected = false
    /// E33: frame-selectie (FigJam) — APART van de onderwerp-selectie. Default
    /// TRUE: het frame opent geselecteerd → top-toolbar zichtbaar + zachte ring
    /// rond de kaart + active-stijl van de naam-chip. Een klik op het onderwerp
    /// of de lege canvas houdt 'm aan; alléén een klik búíten het frame (of de
    /// chip→reselect) schakelt 'm. Onderwerp-handles volgen `canvasSubjectSelected`.
    @State private var canvasFrameSelected = true
    /// E27.3: pan-drag bezig (gelift uit EditorCanvasView) zodat de screen-space
    /// transform-overlay de handles tijdens het pannen even verbergt.
    @State private var canvasSubjectPanning = false
    /// E06.2: tijdens indrukken toont het canvas de originele importfoto.
    @State private var isComparing = false
    /// E10.3: loopt tijdens de cloud-upscale ("Boost resolution").
    @State private var isBoosting = false
    /// Loopt tijdens de cloud-colourisatie ("Colorise"). Voorkomt dubbele calls.
    @State private var isColorising = false
    /// Loopt tijdens Fill in Body (FLUX.1). Voorkomt dubbele calls.
    @State private var isFillingBody = false
    /// E18.12: lokale (gratis, omkeerbare) enhances zijn aan/uit-knoppen —
    /// One-click retouch + Studio Light. Key = actietitel; waarde = de foto
    /// van vóór het toepassen (om naar terug te keren). Aanwezig = aan. 2e klik
    /// herstelt i.p.v. stapelen. Cloud/generatief en uitlijnen blijven gewone
    /// "pas toe"-acties (toggle-logica is daar niet logisch: kosten credits /
    /// niet zuiver omkeerbaar).
    @State private var localToggleBaselines: [String: NSImage] = [:]
    @Environment(\.undoManager) private var undoManager
    /// E-fix: reduced-motion valt de blur-fade tussen isolating-laag en
    /// result-canvas terug op een pure opacity-crossfade (geen blur/scale).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if DEBUG
    /// Smoke-run-haak (--open-panel <tool>): direct uit de proces-argumenten
    /// gelezen (geen race met een setter); één keer geconsumeerd in onAppear.
    @MainActor static var debugInitialTool: EditorTool? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--open-panel"), args.indices.contains(i + 1) else { return nil }
        return EditorTool(rawValue: args[i + 1])
    }()
    #endif

    /// Edit-paneel-cap. Smoke-haak (`--expand-panel`, alleen DEBUG) toont alle
    /// rijen zonder scrollen zodat de toggle-staten te capturen zijn.
    private var editPanelMaxHeight: CGFloat {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--expand-panel") { return 700 }
        #endif
        return 280
    }

    /// Originele importfoto (hold-to-compare); nil voor rijen van vóór E06.2.
    /// Perf (P2): gememoïseerd (originalData is na import onveranderlijk).
    private var originalImage: NSImage? { decodedOriginal }

    /// E24.14: de RAUWE cutout (zonder Adjust-laag). `portrait` is het
    /// canvasbeeld (mét Adjust); destructieve ops + de Adjust-sliders moeten op
    /// de rauwe pixels werken, zodat de Adjust-laag orthogonaal blijft en niet
    /// dubbel telt. Zonder model is er geen Adjust → het canvasbeeld is rauw.
    private var rawCutout: NSImage { decodedCutout ?? portrait }

    /// Perf (P2): decodeer cutout/original/achtergrond één keer per edit i.p.v.
    /// bij élke body-pass (pan/zoom/hover/selectie). Invalidatie via updatedAt +
    /// id — dezelfde aanname als ThumbnailStore (alle edit-paden roepen `touch()`;
    /// `originalData` is na import onveranderlijk).
    private func refreshDecodedImages() {
        decodedCutout = portraitModel.flatMap { NSImage(data: $0.cutoutData) }
        decodedOriginal = portraitModel?.originalData.flatMap { NSImage(data: $0) }
        decodedBackground = portraitModel?.backgroundImageData.flatMap { NSImage(data: $0) }
    }

    /// E24.16: de clip-vorm voor het canvas, volgend op `Portrait2.frameShape`
    /// (default circle). Square = de normale kaart-rechthoek (de kaart rondt de
    /// hoeken zelf al af).
    private var frameClipShape: AnyShape {
        (portraitModel?.frameShape ?? .circle) == .circle ? AnyShape(Circle()) : AnyShape(Rectangle())
    }

    /// E24.26: clip-vorm voor de KAART-surface + dot-grid. Cirkel = Circle
    /// (hoeken puur zwart); square = de afgeronde kaart (xl4) zoals altijd.
    private var cardSurfaceClip: AnyShape {
        (portraitModel?.frameShape ?? .circle) == .circle
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: DSRadius.xl4))
    }

    /// E24.16: persisteer de gekozen frame-vorm op het portret (canvas + export
    /// volgen reactief). `touch()` zet "laatst bewerkt" bij.
    private func setFrameShape(_ shape: ExportShape) {
        guard let portraitModel else { return }
        withAnimation(.spring(duration: 0.3)) {
            portraitModel.frameShape = shape
        }
        portraitModel.touch()
    }

    /// E33/R4: neutraal-grijze frame-selectiekleur (macOS-stijl), gedeeld door de
    /// OUTER ring en de naam-chip-actiefrand. Vast grijs → appearance-stabiel.
    /// CanvasFrameChip gebruikt dezelfde waarde (houd ze gelijk).
    static let frameSelectionGrey = Color(white: 0.6)

    /// E33: selecteer alléén het frame (toolbar + ring terug) en laat het
    /// onderwerp los (handles weg) — gebruikt door de naam-chip en als
    /// gemeenschappelijke ingang voor "klik op de lege canvas".
    private func selectFrameOnly() {
        DSMotion.animate(DSMotion.base) {
            canvasFrameSelected = true
            canvasSubjectSelected = false
        }
    }

    /// E07.1: is er een achtergrond-laag (dan dot-grid uit)? Origineel, custom
    /// afbeelding, kleur, óf Portrait-op-transparant (valt op origineel terug).
    private var hasBackground: Bool {
        backgroundLayerImage != nil || portraitModel?.backgroundColorHex != nil
    }

    /// Portrait-modus (achtergrond-blur) actief op dit portret.
    private var portraitBlurOn: Bool { portraitModel?.portraitBlur == true }

    /// Het beeld dat als achtergrondLAAG achter het scherpe onderwerp tekent:
    /// custom upload, óf de originele foto (Original-modus, of Portrait zonder
    /// expliciete achtergrond). nil = vlakke kleur of geen achtergrond.
    private var backgroundLayerImage: NSImage? {
        if let custom = decodedBackground { return custom }                     // .image
        if portraitModel?.backgroundColorHex != nil { return nil }              // .color → geen beeld-laag
        if portraitModel?.useOriginalBackground == true { return originalImage } // .original
        if portraitBlurOn { return originalImage }                             // .transparent + Portrait → origineel
        return nil                                                              // .transparent
    }

    /// E24.31-fix (2026-06-23): de achtergrondlaag-afbeelding ÍS de originele foto
    /// (Original-modus, of Portrait-blur zonder eigen achtergrond) — géén custom
    /// upload/gradient/kleur. Dan tekent de originele foto op DEZELFDE cutout-
    /// transform (gelijk gekadreerd), niet aspect-fill over het hele frame; anders
    /// verschijnt het onderwerp dubbel (origineel groot achter de uitgelijnde cutout).
    /// Spiegelt de precedentie van `backgroundLayerImage` (custom upload wint).
    private var backgroundIsAlignedOriginal: Bool {
        if decodedBackground != nil { return false }                  // .image → aspect-fill
        if portraitModel?.backgroundColorHex != nil { return false }  // .color → geen beeld-laag
        if portraitModel?.useOriginalBackground == true { return true }
        if portraitBlurOn { return true }                             // .transparent + Portrait → origineel
        return false
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let image = backgroundLayerImage {
            if backgroundIsAlignedOriginal {
                // De originele foto als achtergrondLAAG, EXACT op de cutout-transform
                // (zelfde plaatsing als EditorCanvasView): het originele onderwerp valt
                // achter het scherpe cutout-onderwerp → niet dubbel; de echte achtergrond
                // vult eromheen (en wordt door Portrait vervaagd). De rect komt uit de
                // CUTOUT-maat (`portrait.size`) + de gedeelde resolver, dus het origineel
                // registreert ook bij een licht afwijkende pixelmaat (`.frame` dwingt het
                // in dezelfde rect; cutout en origineel delen de aspect-ratio).
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    let t = AutoFramer.resolvedTransform(
                        offsetX: portraitModel?.offsetX ?? 0,
                        offsetY: portraitModel?.offsetY ?? 0,
                        scale: portraitModel?.scale ?? 0,
                        cutoutSize: portrait.size
                    )
                    let factor = side / FramingConstants.editCanvas.width
                    let imgW = portrait.size.width * t.scale * factor
                    let imgH = portrait.size.height * t.scale * factor
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: imgW, height: imgH)
                        .position(
                            x: (t.offsetX + portrait.size.width * t.scale / 2) * factor,
                            y: (t.offsetY + portrait.size.height * t.scale / 2) * factor
                        )
                        .frame(width: side, height: side)
                        .blur(radius: portraitBlurOn ? BackgroundBlur.canvasRadius(side: side) : 0)
                }
            } else {
                // E24.23-fix: custom upload/gradient als echte backdrop — aspect-fill via
                // een NEUTRAAL-GROOT (Color.clear) container i.p.v.
                // `scaledToFill().frame(maxWidth:.infinity)`. Bij dat laatste lekte de
                // INTRINSIEKE pixelmaat van een grote upload de layout in → het hele canvas
                // (en zo de UI) zoomde onherstelbaar in. Color.clear neemt de aangeboden
                // (begrensde) maat; het beeld is puur een overlay en beïnvloedt de layout
                // niet. clipped() snijdt overvul. Portrait: vervaag de achtergrond-laag
                // (fractie van de zijde, zodat de preview de export-blur volgt).
                GeometryReader { geo in
                    Color.clear
                        .overlay { Image(nsImage: image).resizable().scaledToFill() }
                        .clipped()
                        .blur(radius: portraitBlurOn
                              ? BackgroundBlur.canvasRadius(side: min(geo.size.width, geo.size.height))
                              : 0)
                }
            }
        } else if let hex = portraitModel?.backgroundColorHex, let color = Color(hexRGB: hex) {
            color
        }
    }

    // E31.1: de onderste toolbar is de Figma-capsule (4114:978) — gelabelde
    // icoon+label-pillen Enhance · Effects · Face · Hair · Shirt + een
    // overflow `⋯`. Eigen labels i.p.v. EditorTool.label: `.edit` heet hier
    // "Enhance" (31.2 verhuist het Adjust/Light-paneel hierheen) en `.clothing`
    // heet "Shirt" (Figma-capsule). Face is een bewuste toevoeging t.o.v. Figma
    // (besluit 31.6). Images → app-bar (E22.1).
    // E31.7: gedeeld met de board (BoardView) zodat single-editor én board
    // dezelfde capsule-items tonen. Label "Clothing" (besluit Thierry: canoniek
    // voor beide views — verving "Shirt").
    static let toolbarItems: [DSToolbarItem<EditorTool>] = [
        DSToolbarItem(id: .edit, icon: EditorTool.edit.icon, label: "Enhance"),
        DSToolbarItem(id: .effects, icon: EditorTool.effects.icon, label: "Effects"),
        DSToolbarItem(id: .face, icon: EditorTool.face.icon, label: "Face"),
        DSToolbarItem(id: .hair, icon: EditorTool.hair.icon, label: "Hair"),
        DSToolbarItem(id: .clothing, icon: EditorTool.clothing.icon, label: "Clothing"),
    ]

    /// GTM-cut: Face is compile-time uit. Effects blijft de USP.
    static func isToolbarToolVisible(_ tool: EditorTool) -> Bool {
        switch tool {
        case .face: return AppFeatureFlags.faceEnabled
        default: return true
        }
    }

    static var visibleToolbarItems: [DSToolbarItem<EditorTool>] {
        toolbarItems.filter { isToolbarToolVisible($0.id) }
    }

    // E31.5: de capsule-overflow `⋯` is leeg. Background (dat Figma in deze
    // overflow zette) verhuisde — bewuste afwijking, besluit Thierry — naar de
    // frame-lokale toolbar (canvas-gerelateerd). Geen andere secundaire tools →
    // de `⋯`-knop verschijnt niet (DSBottomToolbar toont 'm alleen bij inhoud).
    // Zodra er wél overflow-tools komen, keert de `⋯` automatisch terug.
    private static let overflowItems: [DSToolbarItem<EditorTool>] = []

    /// Onderschept .images: ring aan = sidebar open; andere tools sluiten de
    /// sidebar en openen hun paneel. E18.20: GEEN eigen withAnimation meer —
    /// activeTool en isSidebarVisible hebben elk al een impliciete spring
    /// (DSEditPanelContainer resp. ShellView, identieke duur), dus die veren
    /// samen. De extra withAnimation dreef dezelfde wijziging dubbel → de
    /// eerste paneel-open sprong/snelde (de tweede was wél goed).
    private var toolSelection: Binding<EditorTool?> {
        Binding(
            get: { isSidebarVisible ? .images : activeTool },
            set: { newValue in
                switch newValue {
                case .images:
                    isSidebarVisible = true
                    activeTool = nil
                case nil:
                    isSidebarVisible = false
                    activeTool = nil
                default:
                    isSidebarVisible = false
                    activeTool = newValue
                }
            }
        )
    }

    var body: some View {
        editorBody
            // E06.6: undo/redo + hold-to-compare hangen nu ín de toolbar-strip
            // (DSBottomToolbar-accessoireslot, E03.19) op de 56-pitch zoals
            // frame App / Edit 4008:7340 — zie `toolbarAccessories`. De
            // tijdelijke bottomTrailing-overlay is hiermee weg.
            // Zoom-bediening zit nu in het View-menu (macOS-menubalk) i.p.v. een
            // zwevende HUD op de canvas — publiceer de acties als focused scene
            // value zodat de menu-items werken zolang deze editor in beeld is.
            .focusedSceneValue(\.canvasZoom, CanvasZoomActions(
                zoomIn: { zoomCamera(by: 1.25) },
                zoomOut: { zoomCamera(by: 0.8) },
                zoomTo100: { withAnimation(.spring(duration: 0.3)) { camera.resetToActualSize() } },
                zoomToFit: { withAnimation(.spring(duration: 0.3)) { camera.reset() } }
            ))
            // E22.1: de sidebar (nu via de app-bar) en een open paneel sluiten
            // elkaar uit — opent de sidebar, dan klapt het paneel dicht.
            .onChange(of: isSidebarVisible) { _, visible in
                if visible { activeTool = nil }
            }
    }

    @ViewBuilder
    private var toolbarAccessories: some View {
        if originalImage != nil {
            // E-fix: hold-to-compare hangt op een Button — de eigen tap-gesture
            // van de Button won het van een gewone `.gesture`, dus de drag vuurde
            // nooit. `.simultaneousGesture` laat de press-down/up wél door zodat
            // ingedrukt-houden het origineel toont.
            DSToolButton(Image(systemName: "rectangle.2.swap"), label: "Hold to compare original", isActive: isComparing, surface: .ghost) {}
                .opacity(isComparing ? 0.85 : 1)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isComparing = true }
                        .onEnded { _ in isComparing = false }
                )
        }
    }

    /// E-fix: de capsule-overflow (`⋯`, Figma Bottom toolbar 4114:983) — acties
    /// die geen eigen paneel hebben. "Restore to original" verschijnt zodra er een
    /// origineel is opgeslagen.
    private var overflowActions: [DSToolbarAction] {
        guard originalImage != nil else { return [] }
        return [
            DSToolbarAction(
                id: "restore-original",
                icon: Image(systemName: "arrow.counterclockwise"),
                label: "Restore to original",
                action: restoreToOriginal
            ),
        ]
    }

    /// Restore body: re-run cutout engine on the original photo so that body parts
    /// clipped during initial segmentation are recovered. Uses a dedicated async path
    /// (onIsolateSubject) instead of routing through applyEffectResult, which has a
    /// silent ?? fallback that would leak the original background on failure.
    private func restoreToOriginal() {
        guard let original = originalImage, let portraitModel else { return }
        let before = NSImage(data: portraitModel.cutoutData)
        Task { @MainActor in
            do {
                let restored = try await onIsolateSubject(original)
                onApplyResult(restored)
                if let before {
                    ImageEnhanceUndo.register(
                        undoManager, target: portraitModel, apply: onApplyResult,
                        undoTo: before, redoTo: restored, actionName: "Restore body"
                    )
                }
            } catch {
                entitlement?.presentError("Could not restore body — subject isolation failed.")
            }
        }
    }

    /// E24.3: color-sliders voor de Adjust-popover (de AI-dropdown staat apart
    /// in de canvas-toolbar, dus hier zonder Auto-enhance-menu).
    private var editColorPanel: some View {
        EditColorPanel(
            source: rawCutout,
            initial: portraitModel?.adjust ?? .neutral,
            onPreview: onPreview,
            onCommit: { before, after in
                // E24.14: niet-destructief — persisteer alléén de params; het
                // canvas hercomputeert (adjust(raw)). cutoutData blijft rauw.
                onCommitAdjust(after)
                if let portraitModel {
                    AdjustUndo.register(
                        undoManager, target: portraitModel, apply: onCommitAdjust,
                        undoTo: before, redoTo: after, actionName: "Adjust"
                    )
                }
            },
            onRetouch: { toggleLocalEnhance("One click retouch") { PortraitEnhancer.magicRetouch($0) } },
            onStudioLight: { toggleLocalEnhance("Studio Light") { PortraitEnhancer.improveLighting($0) } },
            onPortrait: { togglePortraitBlur() },
            onColorise: runColorise,
            onBoost: runBoostResolution,
            // E31.3: Restore body → FLUX.1 Fill Pro outpaints missing body parts
            // (arms, shoulders) into the current cutout; BiRefNet re-extracts alpha.
            onRestoreBody: runFillBody,
            isPro: entitlement?.isProActive ?? false,
            // E24.28: toon de active-state van de lokale toggles.
            studioLightOn: localToggleBaselines["Studio Light"] != nil,
            portraitOn: portraitModel?.portraitBlur == true,
            retouchOn: localToggleBaselines["One click retouch"] != nil,
            showRetouch: true,
            // E24.27: AI-één-tik-acties zitten nu IN het Light & color-paneel.
            showAutoEnhance: true
        )
    }

    // E27.1: verborgen sneltoets-knoppen voor ⌘+/⌘−/⌘0(fit)/⌘1(100%). ⌘= vangt
    // de toets zonder shift; alles animeert soepel. Geen UI, geen hit-test.
    private func zoomCamera(by factor: CGFloat) {
        withAnimation(.spring(duration: 0.25)) { camera.zoomCentered(by: factor) }
    }

    private var editorBody: some View {
        // E28.5: de toolbars zijn altijd zichtbaar in de editor (één portret =
        // altijd het actieve canvas).
        DSEditPanelContainer(
            tools: Self.visibleToolbarItems,
            activeTool: toolSelection,
            overflowTools: Self.overflowItems,
            overflowActions: overflowActions,
            // E-fix: de feature-tools werken op de afgewerkte cutout — tijdens de
            // isolating-fase is die er nog niet, dus dim ze tot het resultaat staat.
            toolsEnabled: isolating == nil
        ) {
            // Canvas-kaart (bevinding 6/7): cutout gevuld op de kaart, met
            // dot-grid eronder zolang er geen achtergrond is ingesteld
            // (E07 zet showsDotGrid uit zodra een achtergrond actief is) —
            // transparante delen tonen het raster: achtergrond verwijderd.
            DSCanvasCard(showsDotGrid: !hasBackground,
                         dotGridDimmed: canvasSubjectSelected,
                         backgroundColor: hasBackground ? DSColor.Background.card : DSColor.Background.canvasIsolated,
                         surfaceClip: cardSurfaceClip) {
                ZStack {
                    if let isolating {
                        // E-fix: bij een vervangende import speelt de isolating-reveal
                        // ÍN het frame — de scaffold (toolbar + naam-frame) blijft staan
                        // i.p.v. plaats te maken voor een full-screen IsolatingCanvas.
                        // Houd de ingestelde achtergrond tijdens het hele proces onder
                        // de importlaag. Zodra het origineel wegfadet, onthult de alpha
                        // van de cutout direct deze achtergrond in plaats van tijdelijk
                        // de algemene transparante/app-achtergrond te tonen.
                        backgroundLayer
                            .clipShape(frameClipShape)
                        IsolatingFrameLayer(
                            original: isolating.original,
                            cutout: isolating.cutout,
                            clipShape: frameClipShape
                        )
                        .transition(reduceMotion ? .opacity : .blurFade)
                    } else {
                        // Achtergrond-laag achter het onderwerp: gekozen achtergrond,
                        // origineel (Original-modus), of Portrait-blur — zie backgroundLayer.
                        // Sinds 2026-06-23 tekent het scherpe onderwerp ALTIJD bovenop (ook
                        // in Original-modus), zodat Portrait de echte achtergrond kan
                        // vervagen. E24.16: clip tot de frame-vorm (cirkel = transparante
                        // hoeken die het dot-grid eronder tonen).
                        backgroundLayer
                            .clipShape(frameClipShape)
                        // E06.2: hold-to-compare toont de originele importfoto
                        // (aspect-fit, geen transform) bovenop het cutout-canvas.
                        if isComparing, let original = originalImage {
                            Image(nsImage: original)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            // E06.4: pan/snap-canvas + subject-schaal via handles.
                            // E27.1: de VIEW-zoom zit niet meer hier maar als camera
                            // op de DSCanvasCard (scène-niveau). Deze view doet alleen
                            // nog onderwerp-transform + selectie.
                            // E24.16: het cutout-beeld clipt EditorCanvasView zelf tot
                            // de frame-vorm, zodat de selectie-handles eromheen niet
                            // mee-geclipt worden.
                            EditorCanvasView(
                                image: portrait, portrait: portraitModel,
                                gridEnabled: canvasGridEnabled,
                                isSelected: $canvasSubjectSelected,
                                isPanning: $canvasSubjectPanning,
                                frameSelected: $canvasFrameSelected,
                                frameShape: portraitModel?.frameShape ?? .circle,
                                // E27.3: de uitlijn-gids constant houden onder de camera-zoom.
                                cameraScale: camera.scale
                            )
                            .transition(reduceMotion ? .opacity : .blurFade)
                        }
                    }
                }
                // E-fix: animeer de overstap isolating ↔ result-canvas (snappy
                // easeOut ~220ms — het systeem antwoordt; de trage reveal-fade
                // zit al ín IsolatingFrameLayer). De blur in .blurFade maskeert de
                // vorm/positie-sprong tussen gevuld origineel en gekadreerde cutout.
                .animation(.easeOut(duration: 0.22), value: isolating == nil)
            }
            // (E33: de frame-selectie-ring is verhuisd naar de SCREEN-SPACE chrome-
            // overlay hieronder — vóór de scaleEffect kromp hij mee met de camera-
            // zoom; nu blijft hij 2pt en plakt aan de zichtbare kaart.)
            // E27.1: de camera (VIEW-zoom + pan) op de HELE scène — render-only
            // (scaleEffect/offset beïnvloeden de layout niet, dus de toolbar-
            // overlay + tap-dismiss blijven in screen-space staan). Pinch zoomt
            // om het midden.
            .scaleEffect(camera.scale, anchor: .center)
            .offset(camera.offset)
            // E27.3: de selectie-handles + kader als SCREEN-SPACE overlay op de
            // (camera-getransformeerde) kaart — vaste schermgrootte, en doordat ze
            // buiten de camera-clip vallen worden grote-onderwerp-hoeken zichtbaar
            // door uit te zoomen. Posities volgen onderwerp-transform + camera.
            .overlay {
                if canvasSubjectSelected, !isComparing, let portraitModel {
                    GeometryReader { geo in
                        CanvasTransformOverlay(
                            side: min(geo.size.width, geo.size.height),
                            image: portrait,
                            portrait: portraitModel,
                            camera: camera,
                            isPanning: canvasSubjectPanning,
                            isSelected: $canvasSubjectSelected,
                            undoManager: undoManager
                        )
                    }
                }
            }
            // E33: frame-chrome (selectie-RING + naam-CHIP + frame-TOOLBAR) als
            // SCREEN-SPACE overlay — exact het CanvasTransformOverlay-recept: posities
            // via de camera-mapping (scherm = midden + scale·(p−midden) + offset) maar
            // met VASTE schermmaten. Zo PLAKKEN ze aan de (camera-gezoomde) zichtbare
            // kaart i.p.v. op de niet-gezoomde layout-hoek te blijven hangen, én blijft
            // de ring 2pt dik op élk zoomniveau (i.p.v. mee te krimpen). `side` = de
            // (inset-verkleinde) kaartzijde; `s`/`offset` = de camera.
            .overlay {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    let s = camera.scale
                    let cx = side / 2 + camera.offset.width        // zichtbaar kaartmidden
                    let cy = side / 2 + camera.offset.height
                    let vis = side * s                             // zichtbare kaartzijde
                    let visTop = cy - vis / 2
                    let visLeft = cx - vis / 2
                    ZStack(alignment: .topLeading) {
                        // E-fix: klik-buiten-sluit voor de frame-dropdown. Ligt ÓNDER
                        // de toolbar (laatste ZStack-kind) zodat klikken op het menu de
                        // menu-knoppen bereiken; klikken elders op de kaart sluiten 'm.
                        // Vervangt de blanket-overlay die het menu afdekte.
                        if canvasMenu != nil {
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(width: side, height: side)
                                .onTapGesture { canvasMenu = nil }
                        }

                        // OUTER grijze ring op de zichtbare kaartrand — vaste 2pt,
                        // radius = kaartradius·zoom + 2 (concentrisch met de xl4-hoek).
                        RoundedRectangle(cornerRadius: DSRadius.xl4 * s + 2, style: .continuous)
                            .stroke(Self.frameSelectionGrey, lineWidth: 2)
                            .frame(width: vis + 4, height: vis + 4)
                            .position(x: cx, y: cy)
                            .opacity(canvasFrameSelected ? 1 : 0)
                            .allowsHitTesting(false)

                        // Naam-chip: links uitgelijnd op de kaart-linkerrand, net
                        // erboven (FigJam-label dat aan het frame plakt). Single =
                        // frame selecteren, dubbelklik = hernoemen.
                        CanvasFrameChip(
                            name: portraitModel?.name,
                            isActive: canvasFrameSelected,
                            onSelect: { selectFrameOnly() },
                            onRename: onRename
                        )
                        .fixedSize()
                        // 28pt chip-hoogte + ~10pt lucht boven de kaartrand.
                        .offset(x: visLeft, y: visTop - 38)

                        // Frame-toolbar: gecentreerd op de kaart, NET BINNEN de
                        // bovenrand (over de portret-top). Tracking → blijft ín het
                        // frame op élk zoomniveau (i.p.v. erboven te zweven).
                        if canvasFrameSelected {
                            CanvasActionToolbar(
                                onAutoFrame: runAutomaticFraming,
                                onFlip: flipHorizontally,
                                frameShape: portraitModel?.frameShape ?? .circle,
                                onSetFrameShape: setFrameShape,
                                activeMenu: $canvasMenu,
                                gridEnabled: $canvasGridEnabled,
                                // E31.2/31.3: Adjust + AI-acties zijn uit de frame-toolbar — nu
                                // de capsule-knop "Enhance" (sliders + one-tap incl. Restore body).
                                background: { BackgroundPanel(portrait: portraitModel, onApply: undoableSetBackground).onHover { pointerOverChrome = $0 } }
                            )
                            .fixedSize()
                            .position(x: cx, y: visTop + DSSpacing.gap6)
                            // Emil: nooit vanaf scale(0); scale-vanuit-0.96 + opacity, origin top.
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                            // E-fix: auto-frame/flip/frame-vorm/achtergrond werken op
                            // de cutout — inert (zichtbaar voor continuïteit) tijdens
                            // de isolating-fase. De naam-chip (hernoemen) en de
                            // camera-pan/-zoom blijven wél actief.
                            .disabled(isolating != nil)
                        }
                    }
                    .frame(width: side, height: side)
                }
            }
            // E04.7: altijd 1:1 en responsief — de kaart vult de foto-slot
            // (aspect-fit, dus nooit clippen) en groeit/krimpt met venster
            // en geopend paneel; de 3.16-garantie houdt paneel en toolbar
            // buiten schot. 456 was de Figma-maat bij 1000×700, geen cap.
            .aspectRatio(1, contentMode: .fit)
            // E33/R3: licht uitgezoomde default — een ECHTE layout-marge rond de
            // kaart zodat het naam-label er bij camera=1 nét boven past (de chrome-
            // overlay tilt 'm 38pt op → marge ≥ 38 voorkomt afkappen door `.clipped()`)
            // en de OUTER ring vrij van de slotrand blijft. Zoomt de gebruiker verder
            // uit, dan volgt de chrome de camera (zie de screen-space overlay).
            .padding(DSSpacing.gap8 + DSSpacing.gap3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // E27.1: ingezoomde scène binnen de canvas-slot houden (niet over de
            // panelen/toolbar lekken). De catcher vangt scroll/⌘-scroll/spatie-
            // drag (clicks vallen door); de zoom-shortcuts (⌘+/⌘−/⌘0/⇧1) komen
            // nu uit het View-menu in de menubalk.
            .clipped()
            .background {
                // chromeHovered telt alléén als er ook echt een menu/paneel open
                // is → een stale hover-true kan canvas-scroll nooit blokkeren.
                CanvasInteractionCatcher(
                    camera: $camera,
                    chromeHovered: pointerOverChrome && (canvasMenu != nil || activeTool != nil)
                )
            }
            .padding(.top, DSSpacing.gap8)
            // E18.17: staat er een paneel/sidebar open, dan sluit een klik
            // buiten dat paneel (op de foto/canvas) het — net als een dropdown.
            .overlay {
                // E-fix: het frame-menu (canvasMenu) sluit nu via een catcher die
                // ÓNDER het menu ligt (in de frame-chrome-overlay hieronder) — deze
                // blanket-overlay lag eróver en at de menu-klikken op. Hier nog
                // alléén het bottom-paneel/sidebar (die buiten deze overlay leven).
                if activeTool != nil || isSidebarVisible {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toolSelection.wrappedValue = nil
                            canvasMenu = nil
                        }
                }
            }
            // (E33/R1: de frame-toolbar is verhuisd naar card-space hierboven —
            // plakt nu aan de kaart-bovenrand i.p.v. in de slot-band te zweven.)
            // E33: ring-fade + toolbar enter/exit samen animeren (reduced-motion-
            // bewust). Eén bron i.p.v. losse withAnimation-sites; de initiële
            // `true` ziet geen change → geen intro-animatie.
            .dsMotion(DSMotion.base, value: canvasFrameSelected)
            // E27.1: een vers portret opent op de fit-camera (1×, geen pan).
            // E33: een ander portret opent frame-geselecteerd (toolbar/ring terug),
            // onderwerp gedeselecteerd (handles weg).
            .onChange(of: portraitModel?.persistentModelID) { _, _ in
                camera.reset()
                canvasFrameSelected = true
                canvasSubjectSelected = false
                refreshDecodedImages()
            }
            // Perf (P2): her-decodeer bij een edit (cutout/achtergrond bumpen
            // `updatedAt`) en bij eerste verschijnen; pan/zoom/hover raken het niet.
            .onChange(of: portraitModel?.updatedAt) { _, _ in refreshDecodedImages() }
            .onAppear { refreshDecodedImages() }
            // E-fix: zodra de isolating-fase begint, klap een open bottom-paneel in
            // en laat het onderwerp los (handles weg) — er valt niets te bewerken
            // tot de cutout staat. Het frame blijft geselecteerd (ring + naam-chip).
            .onChange(of: isolating != nil) { _, active in
                if active {
                    activeTool = nil
                    canvasSubjectSelected = false
                    canvasFrameSelected = true
                }
            }
            // E28.4: betrouwbare deselect op een klik op de LEGE canvas. Bug-
            // oorzaak: de enige klik-deselect (EditorCanvasView's Color.clear) dekt
            // alleen het canvas-VIERKANT, niet de marge eromheen — en de camera-
            // catcher/overlays zitten nu in die ruimte. Deze laag ligt áchter de
            // kaart (de catcher laat clicks door via hitTest→nil), vult de hele
            // foto-slot en deselecteert elke klik die niet op het onderwerp,
            // de handles of een toolbar landt. Onderwerp-tap (selecteren) en
            // EditorCanvasView's eigen deselect liggen erbóven → ongemoeid.
            // E33: deze klik valt búíten het frame → deselecteert BEIDE (frame +
            // onderwerp): toolbar + ring + handles weg. Altijd actief zolang er
            // iets geselecteerd is (frame is default geselecteerd).
            .background {
                if canvasFrameSelected || canvasSubjectSelected {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            DSMotion.animate(DSMotion.base) {
                                canvasFrameSelected = false
                                canvasSubjectSelected = false
                            }
                        }
                }
            }
        } panel: { tool in
            // E-fix: cursor boven het bottom-paneel → de catcher laat scroll dóór
            // (het paneel scrollt i.p.v. de canvas).
            Group {
            if tool == .images {
                // Sidebar-toggle: geen bottom-paneel, foto blijft groot.
                EmptyView()
            } else if tool == .edit {
                // E31.2: de capsule-knop "Enhance" opent het volledige Light &
                // color / Adjust-paneel (E24.27: sliders + Auto-enhance-acties),
                // functioneel ongewijzigd verhuisd uit de frame-toolbar. Gebruikt
                // `editColorPanel` (showAutoEnhance + studioLightOn-state) i.p.v.
                // een uitgeklede inline-variant.
                DSEditPanel(title: "Enhance", maxContentHeight: editPanelMaxHeight) {
                    editColorPanel
                }
            } else if tool == .face, AppFeatureFlags.faceEnabled, let entitlement {
                // E21.1: beauty-acties, gesplitst uit Edit. E32.1: de Beauty-
                // acties zijn gewired op de face-intent van /v1/stylize
                // (nano-banana instruction-edit) i.p.v. een stub-gate. `.id` op
                // het portret zodat het paneel-model herbouwt bij portret-wissel.
                DSEditPanel(title: tool.label, credits: CreditMeter.chipLabel(for: .generativeStandard)) {
                    FaceActionsPanel(
                        baseImage: rawCutout,
                        entitlement: entitlement,
                        onApply: undoableApplyPreservingAlpha("Face edit"),
                        isPro: entitlement.isProActive
                    )
                    .id(portraitModel?.persistentModelID)
                }
            } else if tool == .background {
                // E07.1: achtergrond-paneel (kleur/brand/eyedropper/upload).
                BackgroundPanel(portrait: portraitModel, onApply: undoableSetBackground)
            } else if tool == .clothing, let entitlement {
                // E10.4: kleding-paneel gewired op de clothes-intent van
                // /v1/stylize (nano-banana instruction-edit). `.id` op het portret:
                // de panel-view-models seeden hun basisbeeld eenmalig via @State —
                // bij een portret-wissel moet het paneel herbouwen (anders stale).
                ClothesPanel(baseImage: rawCutout, entitlement: entitlement, onApply: undoableApply("Change clothes"))
                    .id(portraitModel?.persistentModelID)
            } else if tool == .effects, let entitlement {
                // E09.2: stijl-kaarten op het productie-/v1/stylize. E24.33: het
                // portret levert de effect-cache (instant schakelen, geen regen).
                EffectsPanel(baseImage: rawCutout, entitlement: entitlement, portrait: portraitModel, onApply: undoableApplyPreservingAlpha("Apply effect"))
                    .id(portraitModel?.persistentModelID)
            } else if tool == .hair, let entitlement {
                // E11.2: kapsel-chips + vrije prompt op de hair-intent van
                // /v1/stylize (nano-banana instruction-edit, E11.1-route).
                HairPanel(baseImage: rawCutout, entitlement: entitlement, onApply: undoableApply("Change hair"))
                    .id(portraitModel?.persistentModelID)
            } else {
                DSEditPanel(title: tool.label) {
                    Text("\(tool.label) tools land here (\(tool.pendingStory)).")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            }
            .onHover { pointerOverChrome = $0 }
        } toolbarAccessory: {
            // E06.6: undo/redo + compare hangen in de toolbar-strip i.p.v. een
            // losse bottomTrailing-overlay.
            toolbarAccessories
        }
        .padding(.horizontal, DSSpacing.gap3)
        .padding(.bottom, DSSpacing.gap2)
        #if DEBUG
        .onAppear {
            if let tool = Self.debugInitialTool {
                activeTool = tool
                Self.debugInitialTool = nil
            }
            // E18.12: smoke-haak — toon de aan-staat van de lokale toggles.
            if ProcessInfo.processInfo.arguments.contains("--retouch-on") {
                localToggleBaselines["One click retouch"] = portrait
                localToggleBaselines["Studio Light"] = portrait
            }
            // Portrait-smoke-haak: zet de originele achtergrond + Portrait-blur aan,
            // zodat de blur (scherp onderwerp over vervaagde achtergrond) zichtbaar is.
            if ProcessInfo.processInfo.arguments.contains("--portrait-on") {
                portraitModel?.useOriginalBackground = true
                portraitModel?.portraitBlur = true
            }
            // E24.26: smoke-haak — grid-toggle aan.
            if ProcessInfo.processInfo.arguments.contains("--grid-on") { canvasGridEnabled = true }
            // E27.1: smoke-haken — forceer een camera-zoomniveau (om het midden)
            // of de fit-camera, zodat de zoomniveaus te screenshotten zijn.
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--cam-fit") { camera.reset() }
            if let i = args.firstIndex(of: "--cam-zoom"),
               args.indices.contains(i + 1),
               let z = Double(args[i + 1]) {
                camera.scale = camera.clampScale(CGFloat(z))
            }
        }
        #endif
    }

    /// E06.5: AutoFramer op het huidige portret; zonder model of CGImage
    /// is er niets te kadreren (knop is dan een no-op).
    private func runAutomaticFraming() {
        guard let portraitModel,
              let cg = portrait.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        Task { await AutoFramer.apply(to: portraitModel, image: cg, undoManager: undoManager) }
    }

    /// E12.1: lokale Core Image-enhance op het huidige portret. Niet-
    /// destructief — het origineel (`originalData`) blijft, hold-to-compare
    /// toont het, en de wissel is undo'baar. Vervangt canvas + cutout via
    /// `onApplyResult`. No-op zonder model/CGImage of bij renderfout.
    /// E18.12: generieke aan/uit voor lokale enhances. Aan → bewaar de huidige
    /// foto en pas de transform toe; uit → herstel de bewaarde foto. Beide
    /// stappen zijn undo'baar; undo/redo houden de toggle-staat in sync.
    private func toggleLocalEnhance(_ key: String, _ transform: (CGImage) -> CGImage?) {
        guard let portraitModel else { return }
        if let baseline = localToggleBaselines[key] {
            // Uit: terug naar de foto van vóór deze enhance.
            let current = rawCutout
            onApplyResult(baseline)
            ImageEnhanceUndo.register(
                undoManager, target: portraitModel,
                apply: { img in
                    onApplyResult(img)
                    localToggleBaselines[key] = (img === current) ? baseline : nil
                },
                undoTo: current, redoTo: baseline, actionName: "Undo \(key)"
            )
            localToggleBaselines[key] = nil
        } else {
            // Aan: enhance toepassen op de huidige (rauwe) foto.
            let base = rawCutout
            guard let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let outCG = transform(cg) else { return }
            let before = base
            let after = NSImage(cgImage: outCG, size: base.size)
            onApplyResult(after)
            ImageEnhanceUndo.register(
                undoManager, target: portraitModel,
                apply: { img in
                    onApplyResult(img)
                    localToggleBaselines[key] = (img === after) ? before : nil
                },
                undoTo: before, redoTo: after, actionName: key
            )
            localToggleBaselines[key] = before
        }
    }

    /// Portrait-modus (achtergrond-blur) aan/uit. Niet-destructief: zet alléén de
    /// `portraitBlur`-vlag op het portret (canvas/export/board hercomputeren de
    /// achtergrond-laag), undo'baar via de gedeelde ReversibleChange-motor — net
    /// als de Adjust-laag, niet via toggleLocalEnhance (dat cutout-bytes vervangt).
    private func togglePortraitBlur() {
        guard let portraitModel else { return }
        let before = portraitModel.portraitBlur
        let after = !before
        portraitModel.portraitBlur = after
        portraitModel.touch()
        ReversibleChange.register(
            undoManager, target: portraitModel, from: before, to: after, actionName: "Portrait"
        ) { model, value in
            model.portraitBlur = value
            model.touch()
        }
    }

    /// E22.2: spiegel het portret horizontaal (undo'baar via onApplyResult).
    private func flipHorizontally() {
        let base = rawCutout
        guard let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return }
        ctx.translateBy(x: CGFloat(cg.width), y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let out = ctx.makeImage() else { return }
        undoableApply("Flip")(NSImage(cgImage: out, size: base.size))
    }

    /// E18.4: maak cloud-resultaten (Effects/Clothing/Hair) undo'baar. De
    /// before-foto wordt vers uit het model gelezen op het moment van toepassen
    /// (referentietype → niet stale), vóór `onApplyResult` 'm overschrijft.
    /// Undo/redo lopen via `onApplyResult` zodat canvas + cutout meebewegen.
    private func undoableApply(_ name: String) -> (NSImage) -> Void {
        { newImage in
            guard let portraitModel,
                  let before = NSImage(data: portraitModel.cutoutData) else {
                onApplyResult(newImage)
                return
            }
            onApplyResult(newImage)
            ImageEnhanceUndo.register(
                undoManager, target: portraitModel, apply: onApplyResult,
                undoTo: before, redoTo: newImage, actionName: name
            )
        }
    }

    /// Zelfde als `undoableApply` maar via `onApplyAlphaPreserving` — voor
    /// Effects en Face-edits die de lichaamsvorm moeten bewaren.
    private func undoableApplyPreservingAlpha(_ name: String) -> (NSImage) -> Void {
        { newImage in
            guard let portraitModel,
                  let before = NSImage(data: portraitModel.cutoutData) else {
                onApplyAlphaPreserving(newImage)
                return
            }
            onApplyAlphaPreserving(newImage)
            ImageEnhanceUndo.register(
                undoManager, target: portraitModel, apply: onApplyAlphaPreserving,
                undoTo: before, redoTo: newImage, actionName: name
            )
        }
    }

    private func undoableSetBackground(_ background: PortraitBackground) {
        guard let portraitModel else { return }
        let before = portraitModel.background
        guard before != background else { return }
        portraitModel.setBackground(background)
        ReversibleChange.register(
            undoManager, target: portraitModel,
            from: before, to: background, actionName: "Background"
        ) { p, bg in p.setBackground(bg) }
    }

    /// E10.3: cloud-upscale van het huidige portret (Real-ESRGAN, 1 credit).
    /// Vervangt canvas + cutout via `onApplyResult`, undo'baar; 402 → paywall.
    private func runBoostResolution() {
        guard !isBoosting, let entitlement, let portraitModel,
              let png = rawCutout.pngData() else { return }
        // E18.2: contextuele gate (online uit → login → upgrade).
        guard entitlement.allowCloudFeature() else { return }
        let before = rawCutout
        entitlement.presentWorking(
            title: "Boosting resolution",
            messages: [
                "Upscaling the pixels…",
                "Sharpening the details…",
                "Counting every pixel…",
                "Polishing the edges…",
                "Almost crisp…",
            ]
        )
        Task {
            isBoosting = true
            defer { isBoosting = false }
            do {
                let (data, _) = try await entitlement.backend.upscale(imagePNG: png)
                guard let after = NSImage(data: data) else {
                    entitlement.dismissWorkingToast()
                    return
                }
                entitlement.dismissWorkingToast()
                onApplyResult(after)
                ImageEnhanceUndo.register(
                    undoManager, target: portraitModel, apply: onApplyResult,
                    undoTo: before, redoTo: after, actionName: "Boost resolution"
                )
                await entitlement.refresh()
            } catch BackendError.noCredits {
                entitlement.dismissWorkingToast()
                entitlement.handleOutOfCredits()
            } catch {
                entitlement.dismissWorkingToast()
                entitlement.presentError("Couldn't boost the resolution. Please try again.")
            }
        }
    }

    /// Cloud-colourisatie van het huidige portret (DeOldify, 1 credit). Vervangt
    /// canvas + cutout via `onApplyResult`, undo'baar; 402 → paywall. Spiegelt
    /// `runBoostResolution`.
    private func runColorise() {
        guard !isColorising, let entitlement, let portraitModel,
              let png = rawCutout.pngData() else { return }
        // E18.2: contextuele gate (online uit → login → upgrade).
        guard entitlement.allowCloudFeature() else { return }
        let before = rawCutout
        entitlement.presentWorking(
            title: "Colorising",
            messages: [
                "Bringing back the colour…",
                "Mixing the palette…",
                "Painting in the details…",
                "Warming up the tones…",
                "Almost vivid…",
            ]
        )
        Task {
            isColorising = true
            defer { isColorising = false }
            do {
                let (data, _) = try await entitlement.backend.colorize(imagePNG: png)
                guard let after = NSImage(data: data) else {
                    entitlement.dismissWorkingToast()
                    return
                }
                entitlement.dismissWorkingToast()
                onApplyResult(after)
                ImageEnhanceUndo.register(
                    undoManager, target: portraitModel, apply: onApplyResult,
                    undoTo: before, redoTo: after, actionName: "Colorise"
                )
                await entitlement.refresh()
            } catch BackendError.noCredits {
                entitlement.dismissWorkingToast()
                entitlement.handleOutOfCredits()
            } catch {
                entitlement.dismissWorkingToast()
                entitlement.presentError("Couldn't colorise this portrait. Please try again.")
            }
        }
    }

    /// Fill in Body — FLUX.1 Fill Pro outpaints missing body parts (arms, shoulders)
    /// into the current cutout; BiRefNet re-extracts alpha. 2 credits per call.
    private func runFillBody() {
        guard !isFillingBody, let entitlement, let portraitModel,
              let png = rawCutout.pngData() else { return }
        guard entitlement.allowCloudFeature() else { return }
        let before = rawCutout
        entitlement.presentWorking(
            title: "Filling in body",
            messages: [
                "Extending the shoulders…",
                "Sketching in the arms…",
                "Filling in the details…",
                "Touching up the edges…",
                "Almost there…",
            ]
        )
        Task {
            isFillingBody = true
            defer { isFillingBody = false }
            do {
                let (data, _) = try await entitlement.backend.fillBody(imagePNG: png)
                guard let after = NSImage(data: data) else {
                    entitlement.dismissWorkingToast()
                    return
                }
                entitlement.dismissWorkingToast()
                onApplyResult(after)
                ImageEnhanceUndo.register(
                    undoManager, target: portraitModel, apply: onApplyResult,
                    undoTo: before, redoTo: after, actionName: "Fill body"
                )
                await entitlement.refresh()
            } catch BackendError.noCredits {
                entitlement.dismissWorkingToast()
                entitlement.handleOutOfCredits()
            } catch {
                entitlement.dismissWorkingToast()
                entitlement.presentError("Couldn't fill in the body. Please try again.")
            }
        }
    }

}

// MARK: - Blur-fade transition (E-fix)

/// Emil: een blur+opacity-crossfade maskeert de vorm/positie-sprong tussen de
/// gevulde isolating-laag en het gekadreerde result-canvas — het oog ziet één
/// transformatie i.p.v. twee overlappende beelden. Reduced-motion valt terug op
/// pure opacity (geen blur). Blur ≤ 6pt → goedkoop op de GPU.
private extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(
            active: BlurFadeModifier(radius: 6, opacity: 0),
            identity: BlurFadeModifier(radius: 0, opacity: 1)
        )
    }
}

private struct BlurFadeModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity)
    }
}
