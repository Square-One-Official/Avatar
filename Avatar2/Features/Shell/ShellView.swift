// Main shell-wortel (E05). 5.1 = first-use-empty-state, 5.2 = import
// (drag-drop over het hele venster + bestandskiezer → PipelineRouter).
// E04.5-fix (bevindingen 2/3/6): tijdens een drag vervangt de Figma-
// dropzone de first-use-inhoud (gedrag: heel venster blijft droptarget);
// de status-pill hangt op vensterniveau rechtsonder (positie uit de
// frames); de Name/Role-header staat in de flow bóven de canvas-kaart —
// nooit over de foto.

import AvatarUI
import SwiftUI
import UniformTypeIdentifiers

struct ShellView: View {
    let entitlement: EntitlementModel
    @State private var model: ShellModel

    init(entitlement: EntitlementModel) {
        self.entitlement = entitlement
        _model = State(initialValue: ShellModel(entitlement: entitlement))
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// E25.1 smoke-haak: standalone DSColorPicker tonen voor de screenshot.
    @State private var debugShowColorPicker = false
    @State private var debugPickerColor: Color = Color(hue: 0.55, saturation: 0.7, brightness: 0.9)

    var body: some View {
        // Sidebar (E05.4) schuift rechts in; het canvas centreert mee in de
        // resterende ruimte (één spring, geen layoutshift).
        HStack(spacing: 0) {
            // PoC (left-nav): Granola-stijl app-navigatie als de enige sidebar
            // (de oude rechter set-sidebar is verwijderd).
            if model.isLeftNavVisible {
                LeftNavView(model: model, entitlement: entitlement)
                    // Flush aan top/left/bottom van het venster (macOS knipt de
                    // venstercorners zelf af); alleen rechts een gap naar de content.
                    .padding(.trailing, LeftNavView.edgeInset)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
            }
            mainArea
        }
        .dsMotion(DSMotion.springTransform, value: model.isLeftNavVisible)
        .background(DSColor.Background.app)
        // PoC (left-nav): de sidebar-toggle staat op VENSTERNIVEAU náást de
        // traffic-lights en blijft ALTIJD zichtbaar — of de nav nu open of
        // dicht is (gebruikersfeedback). Over de nav heen wanneer open, over de
        // hoofdweergave wanneer dicht; dezelfde positie in beide gevallen.
        .overlay(alignment: .topLeading) { sidebarToggle }
        // E34.5: social-preview is FULL-SCREEN — een crossfade-overlay op
        // VENSTERNIVEAU (over de left-nav + content + sidebar-toggle heen) zodat
        // de hele editor wegvalt. De eigen ✕ in de preview sluit 'm.
        .overlay {
            if model.isShowingSocialPreview, let portrait = model.selectedPortrait {
                SocialPreviewView(
                    portrait: portrait,
                    isPro: entitlement.isProActive,
                    onClose: { model.isShowingSocialPreview = false },
                    onManageBanners: {
                        model.isShowingSocialPreview = false
                        model.showBanners()
                    }
                )
                .transition(.opacity)
            }
        }
        .dsMotion(DSMotion.base, value: model.isShowingSocialPreview)
        // E23: geen forced .dark meer — de hoofdshell volgt de
        // AppearancePreference (default Dark) zodat Light/System werken.
        // E18.4: set-brede edits (Match lighting) wijzigen alleen cutoutData;
        // ververs het canvas na elke undo/redo zodat zulke stappen — en het
        // terugdraaien — ook op het canvas zichtbaar zijn.
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in
            model.refreshCanvasFromSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in
            model.refreshCanvasFromSelection()
        }
        // E19.1: Share/export-popup (DS).
        .sheet(isPresented: $model.isShowingExport) {
            if let portrait = model.selectedPortrait {
                ExportSheet(portrait: portrait, isPro: entitlement.isProActive)
            }
        }
        // E24.21: gedeelde rename-modal vanuit de Name/Role-knop op het canvas.
        .sheet(isPresented: $model.isShowingRename) {
            if let portrait = model.selectedPortrait {
                RenameSheet(portrait: portrait)
            }
        }
        // PoC (left-nav): "Manage backgrounds" vanuit het gebruikersmenu.
        .sheet(isPresented: $model.isShowingManageBackgrounds) {
            ManageBackgroundsSheet()
        }
        // E25.1 smoke-haak: standalone DSColorPicker.
        .sheet(isPresented: $debugShowColorPicker) {
            DSColorPicker(color: $debugPickerColor)
                .padding(DSSpacing.gap8)
                .background(DSColor.Background.app)
        }
        // E19.5: voortgangs-toast voor de set-acties (Align/Match/Export).
        .overlay(alignment: .bottomTrailing) {
            if let message = model.setBusyMessage {
                DSToast(title: message) {}
                    .padding(DSSpacing.gap5)
                    .transition(.dsSlide(.trailing, reduceMotion: reduceMotion))
            }
        }
        .dsMotion(DSMotion.enter, value: model.setBusyMessage)
        .task {
            model.modelContext = modelContext
            // Punt 13: niet-lege store → laatst bewerkte/geselecteerde
            // portret direct op canvas; first-use alleen bij écht leeg.
            model.restoreSelectionAtLaunch()
            #if DEBUG
            // E19.1 smoke-haak: open de export-popup ná de selectie-restore.
            if ProcessInfo.processInfo.arguments.contains("--show-export") {
                model.exportCurrentPortrait()
            }
            // E34.5 smoke-haak: open de social-preview-overlay ná de restore.
            if ProcessInfo.processInfo.arguments.contains("--show-social-preview") {
                model.showSocialPreview()
            }
            // Smoke-run-haak: `--show-settings [pagina]` wordt in
            // ShellModel.init gelezen (vóór first render, geen venster-race);
            // zie de toelichting daar. Compiled out of Release.
            let args = ProcessInfo.processInfo.arguments
            // E04.7/E07.1: `--open-panel <tool>` wordt door EditorView zelf
            // uit de proces-argumenten gelezen (geen race).
            // E05.6: `--force-hair-nudge` toont de nudge voor de smoke.
            if args.contains("--force-hair-nudge") { model.debugForceHairNudge() }
            // E05.7: `--seed-set` dupliceert het portret en opent de sidebar.
            if args.contains("--seed-set") { model.debugSeedSecondPortraitAndOpenSidebar() }
            // E24.14: `--seed-adjust` zet een zichtbare Adjust-laag (canvas +
            // export tonen 'm; cutoutData blijft rauw).
            if args.contains("--seed-adjust") { model.debugSeedAdjust() }
            if args.contains("--reset-adjust") { model.debugResetAdjust() }
            // E24.16: forceer de frame-vorm voor de smoke.
            if args.contains("--frame-square") { model.debugSetFrameShape(.square) }
            if args.contains("--frame-circle") { model.debugSetFrameShape(.circle) }
            if args.contains("--clear-bg") { model.debugClearBackground() }
            // E24.31: forceer de Original- of Transparent-achtergrondmodus.
            if args.contains("--bg-original") { model.debugSetOriginalBackground(true) }
            if args.contains("--bg-transparent") { model.debugSetOriginalBackground(false) }
            // E24.18: reset transform → padded fit-fallback (frame-ademruimte).
            if args.contains("--reset-transform") { model.debugResetTransform() }
            // E27.3: schaal het onderwerp groot (hoeken buiten het frame) om de
            // "uitzoomen om de hoeken te zien"-flow te tonen.
            if let i = args.firstIndex(of: "--scale-subject"), args.indices.contains(i + 1),
               let f = Double(args[i + 1]) {
                model.debugScaleSubject(factor: f)
            }
            // E27.4: open de board-view (alle portretten op één canvas).
            if args.contains("--board") { model.showPortraits(); model.setPortraitsViewMode(.canvas) }
            // PoC (left-nav): open de Portraits-galerij direct voor de smoke.
            if args.contains("--portraits") { model.section = .portraits }
            // PoC (left-nav): forceer de left-nav dicht (collapsed-screenshot).
            if args.contains("--hide-leftnav") { model.isLeftNavVisible = false }
            // PoC (left-nav): open "Manage backgrounds" direct voor de smoke.
            if args.contains("--manage-backgrounds") { model.isShowingManageBackgrounds = true }
            // E24.23: zet een achtergrond-afbeelding vanaf een pad (reproductie).
            if let i = args.firstIndex(of: "--seed-bg"), args.indices.contains(i + 1) {
                model.debugSetBackgroundImage(path: args[i + 1])
            }
            // E24.21: open de rename-modal voor de smoke.
            if args.contains("--show-rename") { model.isShowingRename = true }
            // E25.1: open de standalone DSColorPicker voor de smoke.
            if args.contains("--show-colorpicker") { debugShowColorPicker = true }
            // E24.24: simuleer een persistente upload (kit + achtergrond).
            if let i = args.firstIndex(of: "--upload-bg"), args.indices.contains(i + 1) {
                model.debugUploadBackground(path: args[i + 1])
            }
            // E08.2: `--export-png <pad> [pro]` schrijft de export-PNG van het
            // huidige portret weg voor visuele verificatie (free = watermerk).
            if let i = args.firstIndex(of: "--export-png"), args.indices.contains(i + 1),
               let portrait = model.selectedPortrait {
                let pro = args.contains("pro")
                // Sandbox: schrijf in de container-tmp en log het pad.
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(URL(fileURLWithPath: args[i + 1]).lastPathComponent)
                if let data = PortraitExporter.makePNG(for: portrait, watermark: !pro, shape: portrait.frameShape) {
                    try? data.write(to: url)
                    NSLog("EXPORT_PNG_WRITTEN \(url.path)")
                }
            }
            #endif
        }
    }

    /// PoC (left-nav): persistente sidebar-toggle náást de OS traffic-lights —
    /// altijd zichtbaar, of de nav nu open of dicht is. Subtiel (geen 48pt
    /// tool-knop), Granola-stijl. Op vensterniveau zodat de positie identiek
    /// blijft over de nav (open) of de hoofdweergave (dicht).
    private var sidebarToggle: some View {
        Button { model.toggleLeftNav() } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DSColor.Foreground.muted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.isLeftNavVisible ? "Hide sidebar" : "Show sidebar")
        .padding(.leading, ShellMetrics.topBarLeadingAfterWindowControls)
        .frame(height: ShellMetrics.windowControlsRowHeight)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            if model.isShowingSettings {
                // Settings vervangt de hoofdweergave; Esc sluit (verborgen
                // cancel-knop, venster-breed) of de ✕ in de topbar.
                SettingsRootView(entitlement: entitlement)
                    .background(
                        Button("") { model.isShowingSettings = false }
                            .keyboardShortcut(.cancelAction)
                            .opacity(0)
                            .accessibilityHidden(true)
                    )
            } else if model.section == .home {
                // PoC (left-nav): Home — het overzicht (laatste + eerdere /
                // first-use). De top-right-chrome blijft hier weg.
                HomeView(model: model, entitlement: entitlement)
                    .transition(.opacity)
            } else if model.section == .portraits {
                // PoC (left-nav): de Portraits-grid van de geselecteerde map.
                PortraitsGalleryView(model: model, entitlement: entitlement)
                    .transition(.opacity)
            } else if model.section == .banners {
                // E35.3: Banners-bibliotheek.
                BannersGalleryView(model: model)
                    .transition(.opacity)
            } else {
                // E31.x (besluit Thierry): de Name/Role-kop zweeft als overlay in
                // de topstrook (zie de overlays hieronder).
                // Besluit Thierry (2026-06-24): GEEN top-inset meer — het canvas
                // loopt door tot de bovenrand van het venster (symmetrisch met de
                // onderkant), met de top-chrome (topbar + naam-chip + Frame/Background)
                // erover zwevend i.p.v. in een aparte Background.app-band.
                canvas
                    // Tijdens een drag fade't de hele canvas-inhoud (foto +
                    // Name/Role-chip + editor-toolbar) uit naar de app-
                    // achtergrond, zodat alleen de dropzone-overlay overblijft —
                    // een schone lei, net als first-use (bevinding: drag toont
                    // dropzone óver de avatar i.p.v. leeg scherm).
                    .opacity(model.isDropTargeted ? 0 : 1)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
            }
        }
        // Phase 4: drill-in (en terug) animeert als zoom-in + cross-fade op
        // section-wissels; reduce-motion → kale fade. (Een precieze
        // matchedGeometry-hero is een follow-up om samen met Thierry te tunen.)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.85), value: model.section)
        // Punt 19: top-uitlijning — de VStack centreerde verticaal,
        // waardoor de kaart bij lage vensters onder de quota-rij kroop;
        // header hoort vast bovenaan (Figma y=32), de foto is het enige
        // flexibele element.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Heel het venster is droptarget (Fitts, review-besluit); de
        // Figma-dropzone (App / Dropzone, 4017:1622) is puur visueel.
        .onDrop(of: [.fileURL, .image], isTargeted: $model.isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            // Geen dropzone bovenop Settings (punt 14): de drop zelf wordt
            // in handleDrop genegeerd zolang Settings open staat.
            if model.isDropTargeted && !model.isShowingSettings {
                DropzoneOverlay()
                    .allowsHitTesting(false)
            }
        }
        // PoC (left-nav): uitgeklede topbar — alleen, tijdens het bewerken, de
        // Share-knop (+ ✕ in Settings). De sidebar-toggle staat los op
        // vensterniveau (zie `sidebarToggle`). Settings/credits/board/library
        // zitten nu in de left-nav.
        .overlay(alignment: .top) {
            ShellTopBar(
                isSettingsActive: model.isShowingSettings,
                onToggleSettings: { model.isShowingSettings.toggle() },
                // Top-right-chrome alléén in de editor (niet op Home/Portraits).
                isEditing: model.section == .editor,
                canExport: model.canExport,
                onExport: { model.exportCurrentPortrait() },
                canPreview: model.canPreview,
                onPreview: { model.showSocialPreview() }
            )
        }
        // Phase 4: drill-in-breadcrumb linksboven — alleen tijdens het bewerken.
        .overlay(alignment: .topLeading) {
            if model.section == .editor && !model.isShowingSettings {
                LibraryBreadcrumb(model: model)
                    .padding(.leading, model.isLeftNavVisible ? DSSpacing.gap5 : 96)
                    .padding(.top, DSSpacing.gap3)
                    .transition(.opacity)
            }
        }
        // Status-pill op vensterniveau (bevinding 3): de frames zetten
        // hem rechtsonder in het venster (Isolating 4017:1862 x816–988,
        // Image added 4017:1849), niet aan de foto geplakt.
        .overlay(alignment: .bottomTrailing) {
            if let label = isolatingStatusLabel {
                IsolatingStatusPill(label: label)
                    .padding(DSSpacing.gap4)
            }
        }
        // E05.6: eenmalige hifi-haar-nudge — subtiel onderin, geen modal.
        .overlay(alignment: .bottom) {
            if model.showHairNudge && !model.isShowingSettings {
                HairNudgeBanner(
                    onDownload: { model.acceptHairNudge() },
                    onDismiss: { model.dismissHairNudge() }
                )
                .padding(.bottom, DSSpacing.gap4)
                .transition(.dsSlide(.bottom, reduceMotion: reduceMotion))
            }
        }
        .dsMotion(DSMotion.enter, value: model.showHairNudge)
        .dsMotion(DSMotion.fast, value: model.isDropTargeted)
    }

    private var isolatingStatusLabel: String? {
        switch model.canvas {
        case .processing: "Removing background..."
        case .revealing: "Cutting out hair..."
        default: nil
        }
    }

    @ViewBuilder
    private var canvas: some View {
        // De board/canvas is nu een Portraits-LENS (LibraryViewMode.canvas), geen
        // studio-modus meer → de studio toont altijd de enkel-portret-editor.
        editorCanvas
    }

    @ViewBuilder
    private var editorCanvas: some View {
        // E-fix (bug: een nieuwe foto verving het hele scherm): zodra er een
        // portret op het canvas hoort te staan (result, óf een VERVANGENDE import
        // die nog isoleert), rendert ÉÉN persistente EditorView. Over de fasen
        // heen dezelfde view-identiteit → z'n @State (camera, selectie) blijft
        // bewaard en de scaffold (toolbar + naam-frame) breekt niet af/herbouwt;
        // de isolating-reveal speelt ín het frame. Alleen de éérste import (lege
        // store, geen selectie → editorContent == nil) valt terug op de
        // full-screen IsolatingCanvas hieronder.
        if let content = editorContent {
            EditorView(
                portrait: content.cutout,
                portraitModel: model.selectedPortrait,
                entitlement: entitlement,
                onApplyResult: { model.applyEffectResult($0) },
                onApplyAlphaPreserving: { model.applyEffectResult($0, preserveSourceAlpha: true) },
                onIsolateSubject: { try await model.isolateSubject($0) },
                onPreview: { model.previewCanvas($0) },
                onCommitAdjust: { model.commitAdjust($0) },
                onRename: { model.isShowingRename = true },
                isolating: content.isolating,
                isSidebarVisible: $model.isSidebarVisible
            )
        } else {
            switch model.canvas {
            case .empty:
                // Drag-fade (first-use-inhoud weg, alleen dropzone over) wordt nu
                // centraal door de `.opacity(isDropTargeted)` op de canvas geregeld,
                // zodat álle states uniform faden i.p.v. alleen first-use.
                if model.showsFirstUseEmptyState {
                    FirstUseEmptyState(onChooseFile: { model.presentOpenPanel() }, entitlement: entitlement)
                } else {
                    // E27.7-fix: launch-restore loopt nog, of een herstelde selectie
                    // decodeert off-main (~1s) → neutrale canvas-achtergrond i.p.v. de
                    // first-use-cirkels, die een lege store zouden suggereren.
                    DSColor.Background.app
                }
            case .processing(let original):
                // Éérste import (geen bestaand portret) → full-screen reveal.
                IsolatingCanvas(original: original, cutout: nil)
            case .revealing(let original, let cutout):
                IsolatingCanvas(original: original, cutout: cutout)
            case .result:
                // Afgehandeld door `editorContent` hierboven.
                EmptyView()
            case .failed(let message):
                VStack(spacing: DSSpacing.gap4) {
                    Text(message)
                        .dsTextStyle(.bodyMedium)
                        .foregroundStyle(DSColor.Foreground.subtle)
                        .multilineTextAlignment(.center)
                    DSNeutralButton("Choose another file…") {
                        model.presentOpenPanel()
                    }
                }
                .padding(DSSpacing.gap8)
            }
        }
    }

    /// E-fix: het beeld + de isolating-fase die de persistente EditorView voedt.
    /// Niet-nil zodra er een portret te tonen is:
    ///   • `.result` → de cutout, geen isolating-fase (normale editor);
    ///   • `.processing`/`.revealing` mét een al-geselecteerd portret (een
    ///     VERVANGENDE import) → de vorige cutout als drager + de isolating-fase
    ///     die ín het frame speelt.
    /// Bij de éérste import is er nog geen selectie (`previousCutout == nil`) →
    /// nil, zodat de full-screen IsolatingCanvas het overneemt ("alleen bij
    /// vervangen", besluit Thierry).
    private var editorContent: (cutout: NSImage, isolating: EditorView.IsolatingPhase?)? {
        switch model.canvas {
        case .result(let cutout):
            return (cutout, nil)
        case .processing(let original):
            guard let previous = previousCutout else { return nil }
            return (previous, .processing(original))
        case .revealing(let original, let cutout):
            guard let previous = previousCutout else { return nil }
            return (previous, .revealing(original: original, cutout: cutout))
        case .empty, .failed:
            return nil
        }
    }

    /// De cutout van het momenteel geselecteerde portret (de "vorige" foto tijdens
    /// een vervangende import). nil = geen selectie → dit is een eerste import.
    private var previousCutout: NSImage? {
        model.selectedPortrait.flatMap { NSImage(data: $0.cutoutData) }
    }

    /// Figma App / Dropzone (4017:1622): Frame 11 465×456 gecentreerd,
    /// r-4xl, dashed b-medium in lime, vulling lime ~5% (gesampled — het
    /// frame exposeert er geen variabele voor), "Drop it" in H3 primary.
    private struct DropzoneOverlay: View {
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: DSRadius.xl4)
                    .fill(DSColor.Action.primary.opacity(0.05))
                RoundedRectangle(cornerRadius: DSRadius.xl4)
                    .strokeBorder(
                        DSColor.Action.primary,
                        style: StrokeStyle(lineWidth: DSBorderWidth.medium, dash: [2, 4])
                    )
                Text("Drop it")
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
            }
            .frame(width: 465, height: 456)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // Punt 14: tijdens Settings geen imports — de canvas-weergave is
        // niet zichtbaar, een stille import zou verwarren.
        guard !model.isShowingSettings else { return false }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                Task { @MainActor in
                    await model.importImage(from: url)
                }
            }
            return true
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    await model.importImage(data: data)
                }
            }
            return true
        }
        return false
    }
}
