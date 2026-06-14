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
    /// E22.3: goedkope live-preview (alleen canvas) voor de color-sliders.
    var onPreview: (NSImage) -> Void = { _ in }
    /// E24.14: commit van de niet-destructieve Adjust-laag (params persisteren
    /// op het portret + canvas hercomputeren). Undo loopt via dezelfde closure.
    var onCommitAdjust: (PortraitAdjust) -> Void = { _ in }
    /// Images-tool is geen bottom-paneel maar de sidebar-toggle (E05.4):
    /// de lime ring volgt de sidebar-staat, het paneel blijft leeg.
    @Binding var isSidebarVisible: Bool
    @State private var activeTool: EditorTool?
    /// E24.12: open canvas-toolbar-dropdown (caret-loze DS-kaart). Hier zodat
    /// een klik op de canvas 'm sluit — net als de bottom-panelen.
    @State private var canvasMenu: CanvasToolbarMenu?
    /// E24.8: efemere VIEW-zoom (1×–maxViewZoom). Hier zodat de zoom-HUD búiten
    /// de frame-clip (24.16) rendert; de canvas zelf gebruikt 'm voor scaleEffect
    /// + pinch/scroll.
    @State private var canvasViewZoom: Double = 1
    private let canvasMaxViewZoom: Double = 4
    /// E06.2: tijdens indrukken toont het canvas de originele importfoto.
    @State private var isComparing = false
    /// E10.3: loopt tijdens de cloud-upscale ("Boost resolution").
    @State private var isBoosting = false
    /// E18.12: lokale (gratis, omkeerbare) enhances zijn aan/uit-knoppen —
    /// One-click retouch + Improve lighting. Key = actietitel; waarde = de foto
    /// van vóór het toepassen (om naar terug te keren). Aanwezig = aan. 2e klik
    /// herstelt i.p.v. stapelen. Cloud/generatief en uitlijnen blijven gewone
    /// "pas toe"-acties (toggle-logica is daar niet logisch: kosten credits /
    /// niet zuiver omkeerbaar).
    @State private var localToggleBaselines: [String: NSImage] = [:]
    @Environment(\.undoManager) private var undoManager
    /// UndoManager is niet observable; deze tick (gebumpt op undo-
    /// notificaties) forceert her-evaluatie van de enabled-state.
    @State private var undoTick = 0

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
    private var originalImage: NSImage? {
        guard let data = portraitModel?.originalData else { return nil }
        return NSImage(data: data)
    }

    /// E24.14: de RAUWE cutout (zonder Adjust-laag). `portrait` is het
    /// canvasbeeld (mét Adjust); destructieve ops + de Adjust-sliders moeten op
    /// de rauwe pixels werken, zodat de Adjust-laag orthogonaal blijft en niet
    /// dubbel telt. Zonder model is er geen Adjust → het canvasbeeld is rauw.
    private var rawCutout: NSImage {
        if let portraitModel, let raw = NSImage(data: portraitModel.cutoutData) { return raw }
        return portrait
    }

    /// E24.16: de clip-vorm voor het canvas, volgend op `Portrait2.frameShape`
    /// (default circle). Square = de normale kaart-rechthoek (de kaart rondt de
    /// hoeken zelf al af).
    private var frameClipShape: AnyShape {
        (portraitModel?.frameShape ?? .circle) == .circle ? AnyShape(Circle()) : AnyShape(Rectangle())
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

    /// E07.1: is er een achtergrond ingesteld (dan dot-grid uit).
    private var hasBackground: Bool {
        portraitModel?.backgroundColorHex != nil || portraitModel?.backgroundImageData != nil
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let data = portraitModel?.backgroundImageData, let image = NSImage(data: data) {
            // E24.23-fix: vul een NEUTRAAL-GROOT (Color.clear) container via een
            // overlay i.p.v. `scaledToFill().frame(maxWidth:.infinity)`. Bij dat
            // laatste lekte de INTRINSIEKE pixelmaat van een grote upload de
            // layout in → het hele canvas (en zo de UI) zoomde onherstelbaar in.
            // Color.clear neemt de aangeboden (begrensde) maat; het beeld is puur
            // een overlay en beïnvloedt de layout niet. clipped() snijdt overvul.
            Color.clear
                .overlay { Image(nsImage: image).resizable().scaledToFill() }
                .clipped()
        } else if let hex = portraitModel?.backgroundColorHex, let color = Color(hexRGB: hex) {
            color
        }
    }

    // E24.4: de bottom-toolbar is puur de PERSOON (Effects/Face/Clothing/Hair).
    // Images → app-bar (E22.1); Edit (kleur) → Adjust-popover + AI-dropdown in
    // de canvas-toolbar; Background → canvas-toolbar (E24.1).
    private static let toolbarItems: [DSToolbarItem<EditorTool>] =
        EditorTool.allCases
            .filter { ![.images, .edit, .background].contains($0) }
            .map { DSToolbarItem(id: $0, icon: $0.icon, label: $0.label) }

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
            // E06.2: undo/redo + hold-to-compare. Frame App / Edit zet undo/
            // redo ín de toolbar-strip (x344/x400) en de compare-thumb
            // top-right; integratie in DSBottomToolbar is DS-werk (E03.19).
            // Tot die landt staan ze als glass-cirkels rechtsonder, op één
            // lijn met de toolbar — gedocumenteerde tijdelijke plaatsing.
            .overlay(alignment: .bottomTrailing) { editorControls }
            // UndoManager publiceert geen state → luister op de
            // change-notificaties en bump de tick zodat de knoppen
            // enable/disablen.
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { _ in undoTick += 1 }
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in undoTick += 1 }
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in undoTick += 1 }
            // E22.1: de sidebar (nu via de app-bar) en een open paneel sluiten
            // elkaar uit — opent de sidebar, dan klapt het paneel dicht.
            .onChange(of: isSidebarVisible) { _, visible in
                if visible { activeTool = nil }
            }
    }

    @ViewBuilder
    private var editorControls: some View {
        HStack(spacing: DSSpacing.gap2) {
            DSToolButton(Image(systemName: "arrow.uturn.backward"), label: "Undo") {
                undoManager?.undo()
            }
            .disabled(undoManager?.canUndo != true)
            DSToolButton(Image(systemName: "arrow.uturn.forward"), label: "Redo") {
                undoManager?.redo()
            }
            .disabled(undoManager?.canRedo != true)
            if originalImage != nil {
                DSToolButton(Image(systemName: "rectangle.2.swap"), label: "Hold to compare original", isActive: isComparing) {}
                    .opacity(isComparing ? 0.85 : 1)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in isComparing = true }
                            .onEnded { _ in isComparing = false }
                    )
            }
        }
        .padding(.trailing, DSSpacing.gap3)
        .padding(.bottom, DSSpacing.gap4)
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
            isPro: entitlement?.isProActive ?? false,
            showAutoEnhance: false
        )
    }

    private var editorBody: some View {
        DSEditPanelContainer(tools: Self.toolbarItems, activeTool: toolSelection) {
            // Canvas-kaart (bevinding 6/7): cutout gevuld op de kaart, met
            // dot-grid eronder zolang er geen achtergrond is ingesteld
            // (E07 zet showsDotGrid uit zodra een achtergrond actief is) —
            // transparante delen tonen het raster: achtergrond verwijderd.
            DSCanvasCard(showsDotGrid: !hasBackground) {
                ZStack {
                    // E07.1: gekozen achtergrond achter de cutout (preview;
                    // exportkwaliteit-compositing volgt in E07.2).
                    // E24.16: clip de achtergrond tot de frame-vorm (cirkel =
                    // transparante hoeken die het dot-grid eronder tonen).
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
                        // E06.4: pan/zoom/snap-canvas i.p.v. statische fill.
                        // E24.8: view-zoom (binding) + subject-schaal via handles.
                        // E24.16: het cutout-beeld clipt EditorCanvasView zelf tot
                        // de frame-vorm, zodat de selectie-handles eromheen niet
                        // mee-geclipt worden.
                        EditorCanvasView(
                            image: portrait, portrait: portraitModel,
                            viewZoom: $canvasViewZoom, maxViewZoom: canvasMaxViewZoom,
                            frameShape: portraitModel?.frameShape ?? .circle
                        )
                    }
                }
            }
            // E04.7: altijd 1:1 en responsief — de kaart vult de foto-slot
            // (aspect-fit, dus nooit clippen) en groeit/krimpt met venster
            // en geopend paneel; de 3.16-garantie houdt paneel en toolbar
            // buiten schot. 456 was de Figma-maat bij 1000×700, geen cap.
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, DSSpacing.gap8)
            // E18.17: staat er een paneel/sidebar open, dan sluit een klik
            // buiten dat paneel (op de foto/canvas) het — net als een dropdown.
            .overlay {
                if activeTool != nil || isSidebarVisible || canvasMenu != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toolSelection.wrappedValue = nil
                            canvasMenu = nil
                        }
                }
            }
            // E24.1: canvas action-toolbar (scène/beeld) bovenaan het portret —
            // vervangt de losse rechter-cluster. Boven de tap-dismiss zodat de
            // knoppen/popovers klikbaar blijven.
            .overlay(alignment: .top) {
                CanvasActionToolbar(
                    onAutoFrame: runAutomaticFraming,
                    onFlip: flipHorizontally,
                    frameShape: portraitModel?.frameShape ?? .circle,
                    onSetFrameShape: setFrameShape,
                    onRestoreBody: { _ = entitlement?.allowCloudFeature() },
                    onImproveLighting: { toggleLocalEnhance("Improve lighting") { PortraitEnhancer.improveLighting($0) } },
                    onColorise: { _ = entitlement?.allowCloudFeature() },
                    onBoost: runBoostResolution,
                    isPro: entitlement?.isProActive ?? false,
                    activeMenu: $canvasMenu,
                    adjust: { editColorPanel },
                    background: { BackgroundPanel(portrait: portraitModel) }
                )
                .padding(.top, DSSpacing.gap4)
            }
            // E24.17: de losse −/+ zoom-HUD is verwijderd (overbodig). View-zoom
            // gaat nu alléén via pinch (+ dubbelklik = terug naar fit/1×).
            // E24.8: een vers portret opent op 1× view-zoom.
            .onChange(of: portraitModel?.persistentModelID) { _, _ in canvasViewZoom = 1 }
        } panel: { tool in
            if tool == .images {
                // Sidebar-toggle: geen bottom-paneel, foto blijft groot.
                EmptyView()
            } else if tool == .edit {
                // E06.3: volledige actielijst (zakelijk boven beauty); de
                // auto-frame-actie (E06.5) is "Auto-crop & center".
                DSEditPanel(title: tool.label, maxContentHeight: editPanelMaxHeight) {
                    // E22.3: live color-sliders + Auto-enhance-dropdown.
                    EditColorPanel(
                        source: rawCutout,
                        initial: portraitModel?.adjust ?? .neutral,
                        onPreview: onPreview,
                        onCommit: { before, after in
                            onCommitAdjust(after)
                            if let portraitModel {
                                AdjustUndo.register(
                                    undoManager, target: portraitModel, apply: onCommitAdjust,
                                    undoTo: before, redoTo: after, actionName: "Adjust"
                                )
                            }
                        },
                        onImproveLighting: { toggleLocalEnhance("Improve lighting") { PortraitEnhancer.improveLighting($0) } },
                        onColorise: { _ = entitlement?.allowCloudFeature() },
                        onBoost: runBoostResolution,
                        isPro: entitlement?.isProActive ?? false
                    )
                }
            } else if tool == .face {
                // E21.1: beauty-acties, gesplitst uit Edit.
                DSEditPanel(title: tool.label) {
                    FaceActionsPanel(
                        onRetouch: { toggleLocalEnhance("One click retouch") { PortraitEnhancer.magicRetouch($0) } },
                        onProFeature: { _ = entitlement?.allowCloudFeature() },
                        isPro: entitlement?.isProActive ?? false,
                        activeToggles: Set(localToggleBaselines.keys)
                    )
                }
            } else if tool == .background {
                // E07.1: achtergrond-paneel (kleur/brand/eyedropper/upload).
                BackgroundPanel(portrait: portraitModel)
            } else if tool == .clothing, let entitlement {
                // E10.4: kleding-paneel gewired op de clothes-intent van
                // /v1/stylize (nano-banana instruction-edit).
                ClothesPanel(baseImage: rawCutout, entitlement: entitlement, onApply: undoableApply("Change clothes"))
            } else if tool == .effects, let entitlement {
                // E09.2: stijl-kaarten op het productie-/v1/stylize.
                EffectsPanel(baseImage: rawCutout, entitlement: entitlement, onApply: undoableApply("Apply effect"))
            } else if tool == .hair, let entitlement {
                // E11.2: kapsel-chips + vrije prompt op de hair-intent van
                // /v1/stylize (nano-banana instruction-edit, E11.1-route).
                HairPanel(baseImage: rawCutout, entitlement: entitlement, onApply: undoableApply("Change hair"))
            } else {
                DSEditPanel(title: tool.label) {
                    Text("\(tool.label) tools land here (\(tool.pendingStory)).")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
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
                localToggleBaselines["Improve lighting"] = portrait
            }
            // E24.8: smoke-haak — forceer een view-zoom-niveau.
            if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "--seed-viewzoom"),
               ProcessInfo.processInfo.arguments.indices.contains(i + 1),
               let z = Double(ProcessInfo.processInfo.arguments[i + 1]) {
                canvasViewZoom = min(canvasMaxViewZoom, max(1, z))
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

    /// E10.3: cloud-upscale van het huidige portret (Real-ESRGAN, 1 credit).
    /// Vervangt canvas + cutout via `onApplyResult`, undo'baar; 402 → paywall.
    private func runBoostResolution() {
        guard !isBoosting, let entitlement, let portraitModel,
              let png = Self.pngData(from: rawCutout) else { return }
        // E18.2: contextuele gate (online uit → login → upgrade).
        guard entitlement.allowCloudFeature() else { return }
        let before = rawCutout
        Task {
            isBoosting = true
            defer { isBoosting = false }
            do {
                let (data, _) = try await entitlement.backend.upscale(imagePNG: png)
                guard let after = NSImage(data: data) else { return }
                onApplyResult(after)
                ImageEnhanceUndo.register(
                    undoManager, target: portraitModel, apply: onApplyResult,
                    undoTo: before, redoTo: after, actionName: "Boost resolution"
                )
                await entitlement.refresh()
            } catch BackendError.noCredits {
                entitlement.handleOutOfCredits()
            } catch {
                // E18.3: fout als toast.
                entitlement.presentError("Couldn't boost the resolution. Please try again.")
            }
        }
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
