// Main shell-wortel (E05). 5.1 = first-use-empty-state, 5.2 = import
// (drag-drop over het hele venster + bestandskiezer → PipelineRouter).
// Drop-chrome framed de contentkolom (niet een zwevend 465×456-vlak);
// heel venster blijft droptarget. Status-pill hangt rechtsonder; de
// Name/Role-header staat in de flow bóven de canvas-kaart — nooit over
// de foto.

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

    /// Portrait- + banner-editor: canvas full-bleed; sidebar/chrome als overlay.
    private var studioFullBleed: Bool {
        guard !model.isShowingSettings else { return false }
        if model.section == .editor && !model.isShowingSocialPreview { return true }
        if model.editingBanner != nil && !model.isShowingBannerPreview { return true }
        return false
    }

    var body: some View {
        ZStack {
            if studioFullBleed {
                Group {
                    if let doc = model.editingBanner {
                        BannerStudioView(doc: doc, model: model, entitlement: entitlement)
                    } else {
                        canvas
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .opacity(showsFileDropzone ? DSOpacity.disabled : DSOpacity.strong)
                .overlay {
                    dropzoneLayer
                        .padding(.leading, model.isLeftNavVisible ? LeftNavView.layoutWidth : 0)
                        .padding(.trailing, ShellMetrics.windowEdgeInset)
                        .padding(.vertical, ShellMetrics.windowEdgeInset)
                }
            }

            if studioFullBleed {
                HStack(alignment: .top, spacing: 0) {
                    if model.isLeftNavVisible {
                        leftNavSlot
                            .padding(.vertical, ShellMetrics.windowEdgeInset)
                            .transition(.move(edge: .leading))
                    }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: ShellMetrics.sidebarContentSpacing) {
                    if model.isLeftNavVisible {
                        leftNavSlot
                            .padding(.vertical, ShellMetrics.windowEdgeInset)
                            .transition(.move(edge: .leading))
                    }
                    mainArea
                        .safeAreaPadding(.top, ShellMetrics.contentTopSafeArea)
                        .padding(.trailing, ShellMetrics.windowEdgeInset)
                        .opacity(showsFileDropzone ? DSOpacity.disabled : DSOpacity.strong)
                        .overlay { dropzoneLayer }
                }
            }
        }
        // UXS-29(v2): de unified toolbar (stabilise) geeft het venster een hoge
        // top-safe-area. De shell negeert die op root-niveau zodat de zwevende
        // sidebar-kaart op z'n gap3-inset vanaf de vénstertop blijft (met de
        // traffic-lights native gecentreerd ín de kaart); de content-kolom
        // krijgt de titelbalk-hoogte expliciet terug via safeAreaPadding.
        .ignoresSafeArea(.container, edges: .top)
        .dsMotion(DSMotion.springTransform, value: model.isLeftNavVisible)
        .background(studioFullBleed ? Color.clear : DSColor.Background.app)
        .background(WindowTrafficLightStabilizer().frame(width: 0, height: 0))
        // ⌘, opent de in-venster Settings (zie SettingsCommands in het app-menu).
        .focusedSceneValue(\.openSettings, OpenSettingsAction { model.isShowingSettings = true })
        // ⌘U opent het import-panel (zie UploadPortraitCommands in het File-menu).
        .focusedSceneValue(\.uploadPortrait, UploadPortraitAction { model.presentOpenPanel() })
        // Vaste venster-chrome: traffic-light-strook + toggle schuiven niet mee
        // met de sidebar-animatie; de strip hoort visueel bij de nav wanneer open.
        .overlay(alignment: .topLeading) {
            ShellSidebarChrome(
                isSidebarVisible: model.isLeftNavVisible,
                onToggleSidebar: { model.toggleLeftNav() }
            )
            .dsMotion(DSMotion.springTransform, value: model.isLeftNavVisible)
        }
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
        // E19.1: Share/export-popup (DS) — item-snapshot voorkomt dismiss/represent
        // bij shell layout-wissels (Edit↔Preview, studioFullBleed).
        .dsPersistentSheet(item: $model.exportSession) { session in
            ExportSheet(portraitID: session.id, isPro: entitlement.isProActive)
        }
        // E24.21: gedeelde rename-modal vanuit de Name/Role-knop op het canvas.
        .dsPersistentSheet(isPresented: $model.isShowingRename) {
            if let portrait = model.selectedPortrait {
                RenameSheet(portrait: portrait)
            }
        }
        // E53.7: board bulk-rename op stabiele host.
        .dsPersistentSheet(isPresented: Binding(
            get: { !model.renamePortraitIDs.isEmpty },
            set: { if !$0 { model.renamePortraitIDs = [] } }
        )) {
            RenameSheet(portraitIDs: model.renamePortraitIDs)
        }
        // PoC (left-nav): "Manage backgrounds" vanuit het gebruikersmenu.
        .dsPersistentSheet(isPresented: $model.isShowingManageBackgrounds) {
            ManageBackgroundsSheet(entitlement: entitlement)
        }
        // E53.7: pre-stylize gate — leeft op ShellModel, niet op EditorView.
        .dsPersistentSheet(isPresented: Binding(
            get: { model.stylizeQuality.preGate != nil },
            set: { _ in }
        )) {
            if let gate = model.stylizeQuality.preGate {
                PreStylizeQualitySheet(gate: gate) { model.stylizeQuality.resolvePreGate($0) }
            }
        }
        // E34: "Create effect"-modal (eigen effecten) — stabiele host, resultaat
        // gaat via de store terug naar het Effects-paneel.
        .dsPersistentSheet(isPresented: Binding(
            get: { model.presentation.createEffectSheetOpen },
            set: { model.presentation.createEffectSheetOpen = $0 }
        )) {
            CreateEffectSheet(entitlement: entitlement) { result in
                model.presentation.createdCustomEffect = result
            }
        }
        .generateBackgroundSheet(entitlement: entitlement)
        // E53.8: Apple-Intelligence-sheet op de stabiele host — presenteerde
        // eerder vanuit de chip in het Enhance-paneel, dus een tab-wissel gooide
        // een lopende generatie weg.
        .imagePlaygroundHost()
        // E53.7: contextmenu's + store-gedreven alerts/confirms.
        .overlay { FloatingOverlayHost(model: model, entitlement: entitlement) }
        // E25.1 smoke-haak: standalone DSColorPicker.
        .sheet(isPresented: $debugShowColorPicker) {
            DSColorPicker(color: $debugPickerColor)
                .padding(DSSpacing.gap8)
                .background(DSColor.Background.app)
                .appliedAppearancePreference()
        }
        // E19.5: voortgangs-toast voor de set-acties (Align/Match/Export).
        .overlay(alignment: .bottomTrailing) {
            if let message = model.setBusyMessage {
                // UXS-2: geen sluitknop — deze set-actie loopt tot 'ie klaar is
                // en heeft geen annuleer-pad. Een knop die niets doet is erger
                // dan geen knop.
                DSToast(title: message)
                    .padding(DSSpacing.gap5)
                    .transition(.dsSlide(.trailing, reduceMotion: reduceMotion))
            }
        }
        .dsMotion(DSMotion.enter, value: model.setBusyMessage)
        .onChange(of: entitlement.openSettingsPage) { _, page in
            if let page {
                model.openSettings(page: page)
                entitlement.openSettingsPage = nil
            }
        }
        .task {
            model.modelContext = modelContext
            // Punt 13: niet-lege store → laatst bewerkte/geselecteerde
            // portret direct op canvas; first-use alleen bij écht leeg.
            model.restoreSelectionAtLaunch()
            #if DEBUG
            // UXS-28 smoke-haak: open het herstelde portret direct in de editor
            // (de kaarten zijn nog niet AX-bedienbaar — zie UX28/UXS-7 — dus
            // smokes kunnen de editor anders niet bereiken).
            if ProcessInfo.processInfo.arguments.contains("--open-editor"),
               let portrait = model.selectedPortrait {
                model.openPortrait(portrait)
            }
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
            // Drop-import-smoke: `--import-after <pad> [sec]` — simuleert een
            // Finder-drop in de library (zelfde model-pad als handleDrop).
            if let i = args.firstIndex(of: "--import-after"), args.indices.contains(i + 1) {
                let path = args[i + 1]
                let delay = (args.indices.contains(i + 2) ? TimeInterval(args[i + 2]) : nil) ?? 3
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(delay))
                    await model.importImage(from: URL(fileURLWithPath: path))
                }
            }
            // Drop-import-smoke: `--record-states <logpad>` — logt ~15s lang elke
            // 50ms sectie + canvas-state + selectie, om de importflow-volgorde
            // te verifiëren zonder screen-recording-permissie.
            if let i = args.firstIndex(of: "--record-states"), args.indices.contains(i + 1) {
                let logURL = URL(fileURLWithPath: args[i + 1])
                Task { @MainActor in
                    let t0 = Date()
                    var lines: [String] = []
                    var last = ""
                    for _ in 0..<300 {
                        let ms = Int(Date().timeIntervalSince(t0) * 1000)
                        let canvasDesc: String
                        switch model.canvas {
                        case .empty: canvasDesc = "empty"
                        case .processing: canvasDesc = "processing"
                        case .revealing: canvasDesc = "revealing"
                        case .result: canvasDesc = "result"
                        case .failed(let msg): canvasDesc = "failed(\(msg))"
                        }
                        let line = "section=\(model.section) canvas=\(canvasDesc) " +
                            "selected=\(model.selectedPortrait?.name ?? "nil")"
                        if line != last {
                            lines.append(String(format: "%06dms %@", ms, line))
                            last = line
                            try? lines.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
                        }
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                }
            }
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
            // E27.4: `--board` opende de canvas-lens; de library is nu grid-only.
            if args.contains("--board") { model.showPortraits() }
            // PoC (left-nav): open de Portraits-galerij direct voor de smoke.
            if args.contains("--portraits") { model.section = .portraits }
            if args.contains("--lens") { model.showPortraits() }
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
            // Smoke: toon de grid, drill na een marge in het jongste portret.
            if args.contains("--drill-in-demo") {
                model.section = .portraits
                try? await Task.sleep(for: .seconds(3))
                model.debugDrillIntoFirstPortrait()
            }
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
        .refreshAppleIntelligenceAvailability {
            PrivacyPreferences2.shared.reapplyFingerprintPolicy()
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $model.isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay(alignment: .bottomTrailing) {
            if let label = isolatingStatusLabel, !model.isShowingSocialPreview {
                IsolatingStatusPill(label: label)
                    .padding(DSSpacing.gap4)
            }
        }
        .overlay(alignment: .bottom) {
            if model.showHairNudge && !model.isShowingSettings && !model.isShowingSocialPreview {
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
        .overlay(alignment: .top) {
            if showsEditorTopChrome {
                editorTopChromeBand
            }
        }
    }

    /// Sidebar-slot: insert/remove met slide — géén leading-width-clip (dat liet
    /// de top-leading hoekradius als los vlekje achter).
    private var leftNavSlot: some View {
        LeftNavView(model: model, entitlement: entitlement)
            .padding(.leading, LeftNavView.edgeInset)
            .frame(width: LeftNavView.layoutWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            if model.isShowingSettings {
                // Settings vervangt de hoofdweergave; Esc sluit (verborgen
                // cancel-knop, venster-breed) of de ✕ in de topbar.
                SettingsRootView(entitlement: entitlement, model: model, page: $model.settingsPage)
                    .background(
                        Button("") { model.isShowingSettings = false }
                            .keyboardShortcut(.cancelAction)
                            .opacity(0)
                            .accessibilityHidden(true)
                    )
            } else if let doc = model.editingBanner {
                Group {
                    if model.isShowingBannerPreview {
                        BannerPreviewView(doc: doc, isPro: entitlement.isProActive)
                    } else {
                        Color.clear
                    }
                }
                .transition(.opacity)
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
                BannersGalleryView(model: model, entitlement: entitlement)
                    .transition(.opacity)
            } else {
                Group {
                    if model.isShowingSocialPreview {
                        SocialPreviewView(
                            model: model,
                            isPro: entitlement.isProActive
                        )
                    } else if studioFullBleed {
                        Color.clear
                    } else {
                        canvas
                    }
                }
                .transition(.opacity)
            }
        }
        // E53.4: de reduce-motion-check zit in `dsMotion` zelf, niet in een
        // ternary per view — één plek die je kunt vertrouwen.
        .dsMotion(DSMotion.emphasis, value: model.section)
        .dsMotion(DSMotion.emphasis, value: model.isShowingSocialPreview)
        .dsMotion(DSMotion.emphasis, value: model.isShowingBannerPreview)
        .dsMotion(DSMotion.emphasis, value: model.editingBanner != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var showsEditorTopChrome: Bool {
        model.section == .editor || model.isShowingSettings || model.editingBanner != nil
    }

    private var editorTopChromeBand: some View {
        HStack(alignment: .top, spacing: DSSpacing.gap2) {
            if model.editingBanner != nil && !model.isShowingSettings {
                BannerBreadcrumb(model: model)
                    .padding(.leading, shellEditorBreadcrumbLeading)
                    .transition(.opacity)
                    .dsMotion(DSMotion.springTransform, value: model.isLeftNavVisible)
            } else if model.section == .editor && !model.isShowingSettings {
                LibraryBreadcrumb(model: model)
                    .padding(.leading, shellEditorBreadcrumbLeading)
                    .transition(.opacity)
                    .dsMotion(DSMotion.springTransform, value: model.isLeftNavVisible)
            }
            Spacer(minLength: DSSpacing.gap2)
            ShellTopBar(
                // UXS-11: de settings-✕ verbergen zolang de paywall (of een
                // andere sheet) ervoor staat — anders staan er twee ✕'en in
                // beeld en is niet duidelijk welke wát sluit.
                isSettingsActive: model.isShowingSettings && !entitlement.isPaywallPresented,
                onToggleSettings: { model.isShowingSettings.toggle() },
                isEditing: model.section == .editor || model.editingBanner != nil,
                canExport: model.editingBanner != nil ? model.canExportBanner : model.canExport,
                onExport: {
                    if model.editingBanner != nil {
                        model.exportCurrentBanner(isPro: entitlement.isProActive)
                    } else {
                        model.exportCurrentPortrait()
                    }
                },
                canPreview: model.editingBanner != nil ? model.canPreviewBanner : model.canPreview,
                isPreviewActive: model.editingBanner != nil
                    ? model.isShowingBannerPreview
                    : model.isShowingSocialPreview,
                onPreviewActiveChange: { active in
                    if model.editingBanner != nil {
                        model.isShowingBannerPreview = active
                    } else if active {
                        model.showSocialPreview()
                    } else {
                        model.isShowingSocialPreview = false
                    }
                }
            )
        }
        .padding(.top, ShellMetrics.shellTopBarControlTopInset)
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: ShellMetrics.editorTopChromeBandHeight, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Leading in vénster-space (de top-chrome-band overlayt de root-ZStack) —
    /// bewust onafhankelijk van `studioFullBleed` (UXS-28/UX35): de oude
    /// `gap3`-tak rekende alsof de band in de content-kolom leefde, waardoor de
    /// breadcrumb bij Edit↔Preview ~248pt versprong (tot óver de sidebar).
    /// Sidebar open → ná de sidebar-kaart; dicht → ná sidebar-toggle (zelfde rij
    /// als traffic-lights).
    private var shellEditorBreadcrumbLeading: CGFloat {
        if model.isLeftNavVisible {
            return LeftNavView.layoutWidth + DSSpacing.gap3
        }
        return ShellMetrics.editorBreadcrumbLeadingCollapsed
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
        // Studio toont altijd de enkel-portret-editor. De library is grid-only.
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
                model: model,
                portraitModel: model.selectedPortrait,
                entitlement: entitlement,
                onApplyResult: { await model.applyEffectResult($0) },
                onApplyAlphaPreserving: { await model.applyEffectResult($0, preserveSourceAlpha: true) },
                onApplyIsolated: { await model.applyIsolatedResult($0) },
                onIsolateSubject: { try await model.isolateSubject($0, preferring: $1) },
                onPreview: { model.previewCanvas($0) },
                onCommitAdjust: { model.commitAdjust($0) },
                onRename: { model.isShowingRename = true },
                isolating: content.isolating,
                isSidebarVisible: $model.isSidebarVisible
            )
        } else {
            switch model.canvas {
            case .empty:
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
    ///   • `.processing`/`.revealing` → de isolating-fase speelt ín het frame.
    ///     De drager is de vorige cutout (VERVANGENDE import in de editor) of —
    ///     bij een library-import, die de selectie wist (runCutout) — het
    ///     origineel zelf. De drager rendert niet zolang de isolating-laag
    ///     speelt; hij houdt alleen de EditorView-identiteit stabiel.
    private var editorContent: (cutout: NSImage, isolating: EditorView.IsolatingPhase?)? {
        switch model.canvas {
        case .result(let cutout):
            return (cutout, nil)
        case .processing(let original):
            return (previousCutout ?? original, .processing(original))
        case .revealing(let original, let cutout):
            return (previousCutout ?? original, .revealing(original: original, cutout: cutout))
        case .empty, .failed:
            return nil
        }
    }

    /// De cutout van het momenteel geselecteerde portret (de "vorige" foto tijdens
    /// een vervangende import). nil = geen selectie → dit is een eerste import.
    private var previousCutout: NSImage? {
        model.selectedPortrait.flatMap { NSImage(data: $0.cutoutData) }
    }

    /// File-drop chrome for the main column — pane frame, not a floating square.
    private var showsFileDropzone: Bool {
        model.isDropTargeted
            && !model.isShowingSettings
            && !model.isShowingSocialPreview
            && !model.isShowingBannerPreview
    }

    @ViewBuilder
    private var dropzoneLayer: some View {
        if showsFileDropzone {
            DropzoneOverlay()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }

    private struct DropzoneOverlay: View {
        /// Gallery/home pad at `gap6`; stroke sits just outside the tiles.
        private let inset: CGFloat = DSSpacing.gap5

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: DSRadius.xl4, style: .continuous)
            ZStack {
                DSColor.Background.app.opacity(DSOpacity.medium)
                shape
                    .fill(DSColor.Action.primary.opacity(0.05))
                    .overlay {
                        shape.strokeBorder(
                            DSColor.Action.primary,
                            style: StrokeStyle(lineWidth: DSBorderWidth.medium, dash: [2, 4])
                        )
                    }
                    .padding(inset)
                Text("Drop it")
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // Punt 14: tijdens Settings geen imports — de canvas-weergave is
        // niet zichtbaar, een stille import zou verwarren.
        guard !model.isShowingSettings, !model.isShowingSocialPreview else { return false }
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

// MARK: - Settings menu command (⌘,)

/// Door `ShellView` gepubliceerde actie om de in-venster Settings te openen;
/// nil tijdens onboarding (shell niet in beeld) → het menu-item grijst uit.
struct OpenSettingsAction {
    var open: () -> Void
}

private struct OpenSettingsKey: FocusedValueKey {
    typealias Value = OpenSettingsAction
}

extension FocusedValues {
    var openSettings: OpenSettingsAction? {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
    }
}

/// Vervangt het (standaard uitgegrijsde) "Settings…"-item in het app-menu door
/// ⌘, → opent de in-venster Settings. Mirror van `CanvasZoomCommands`:
/// een `View` met `@FocusedValue` zodat het item enable/disablet met de shell.
struct SettingsCommands: View {
    @FocusedValue(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") { openSettings?.open() }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(openSettings == nil)
    }
}
