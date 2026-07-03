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
                        BannerStudioView(doc: doc, entitlement: entitlement)
                    } else {
                        canvas
                            .opacity(model.isDropTargeted ? 0 : 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            }

            if studioFullBleed {
                HStack(alignment: .top, spacing: 0) {
                    leftNavSlot
                        .padding(.vertical, ShellMetrics.windowEdgeInset)
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: ShellMetrics.sidebarContentSpacing) {
                    leftNavSlot
                        .padding(.vertical, ShellMetrics.windowEdgeInset)
                    mainArea
                        .safeAreaPadding(.top, ShellMetrics.contentTopSafeArea)
                        .padding(.trailing, ShellMetrics.windowEdgeInset)
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
        // Vaste venster-chrome: traffic-light-strook + toggle schuiven niet mee
        // met de sidebar-animatie; de strip hoort visueel bij de nav wanneer open.
        .overlay(alignment: .topLeading) {
            ShellSidebarChrome(
                isSidebarVisible: model.isLeftNavVisible,
                studioFullBleed: studioFullBleed,
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
            ManageBackgroundsSheet(entitlement: entitlement)
        }
        .generateBackgroundSheet(entitlement: entitlement)
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
                DSToast(title: message) {}
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
            // E27.4: open de board-view (alle portretten op één canvas).
            if args.contains("--board") { model.showPortraits(); model.setPortraitsViewMode(.canvas) }
            // PoC (left-nav): open de Portraits-galerij direct voor de smoke.
            if args.contains("--portraits") { model.section = .portraits }
            // Smoke: forceer een specifieke lens op de Portraits-surface
            // (`--lens grid|list|gallery|canvas`) — deterministisch i.p.v. klikken.
            if let i = args.firstIndex(of: "--lens"), args.indices.contains(i + 1) {
                model.showPortraits()
                switch args[i + 1] {
                case "list": model.setPortraitsViewMode(.list)
                case "gallery": model.setPortraitsViewMode(.gallery)
                case "canvas": model.setPortraitsViewMode(.canvas)
                default: model.setPortraitsViewMode(.grid)
                }
            }
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
        .overlay {
            if model.isDropTargeted && !model.isShowingSettings && !model.isShowingSocialPreview && !model.isShowingBannerPreview {
                DropzoneOverlay()
                    .allowsHitTesting(false)
            }
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

    /// Sidebar-slot: altijd gemonteerd, onthult via leading-clip (zelfde spring als chrome).
    private var leftNavSlot: some View {
        LeftNavView(model: model, entitlement: entitlement)
            .padding(.leading, LeftNavView.edgeInset)
            .frame(width: LeftNavView.layoutWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .frame(width: model.isLeftNavVisible ? LeftNavView.layoutWidth : 0, alignment: .leading)
            .clipped()
            .allowsHitTesting(model.isLeftNavVisible)
            .accessibilityHidden(!model.isLeftNavVisible)
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            if model.isShowingSettings {
                // Settings vervangt de hoofdweergave; Esc sluit (verborgen
                // cancel-knop, venster-breed) of de ✕ in de topbar.
                SettingsRootView(entitlement: entitlement, page: $model.settingsPage)
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
                    // Tijdens een drag fade't de hele Home-inhoud uit zodat alleen
                    // de dropzone-overlay (op mainArea-niveau) zichtbaar blijft —
                    // zelfde gedrag als de editor-canvas.
                    .opacity(model.isDropTargeted ? 0 : 1)
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
                            .opacity(model.isDropTargeted ? 0 : 1)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.section)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.isShowingSocialPreview)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.isShowingBannerPreview)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.editingBanner != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var showsEditorTopChrome: Bool {
        model.section == .editor || model.isShowingSettings || model.editingBanner != nil
    }

    private var editorTopChromeBand: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: DSSpacing.gap2) {
                Group {
                    if model.editingBanner != nil && !model.isShowingSettings {
                        BannerBreadcrumb(model: model)
                            .transition(.opacity)
                    } else if model.section == .editor && !model.isShowingSettings {
                        LibraryBreadcrumb(model: model)
                            .transition(.opacity)
                    }
                }
                .padding(.leading, shellEditorBreadcrumbLeading)
                .padding(.top, ShellMetrics.breadcrumbTopInset)
                .dsMotion(DSMotion.springTransform, value: model.isLeftNavVisible)

                Spacer(minLength: DSSpacing.gap2)
            }

            ShellTopBar(
                isSettingsActive: model.isShowingSettings,
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
            .padding(.top, ShellMetrics.shellTopBarControlTopInset)
            .frame(maxWidth: .infinity, alignment: .topTrailing)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: ShellMetrics.editorTopChromeBandHeight, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Leading in vénster-space (de top-chrome-band overlayt de root-ZStack) —
    /// bewust onafhankelijk van `studioFullBleed` (UXS-28/UX35): de oude
    /// `gap3`-tak rekende alsof de band in de content-kolom leefde, waardoor de
    /// breadcrumb bij Edit↔Preview ~248pt versprong (tot óver de sidebar).
    /// Sidebar open → ná de sidebar-kaart; dicht → panel-inset (breadcrumb zit
    /// onder de traffic-light-rij, dus geen ruimte nodig voor toggle).
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
                onApplyResult: { await model.applyEffectResult($0) },
                onApplyAlphaPreserving: { await model.applyEffectResult($0, preserveSourceAlpha: true) },
                onApplyIsolated: { await model.applyIsolatedResult($0) },
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
