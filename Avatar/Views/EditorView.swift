import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct EditorView: View {
    @Bindable var portrait: Portrait
    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    @Environment(AppState.self) private var appState
    @Query(sort: \BackgroundPreset.createdAt) private var backgrounds: [BackgroundPreset]
    @Query private var allPortraits: [Portrait]

    @State private var dragStart: CGSize? = nil
    @State private var dragUndoSnapshot: PortraitUndoManager.Snapshot? = nil
    /// Shared snapshot for any slider interaction (scale or adjustments).
    /// Captured on first change, committed when a different action starts.
    @State private var sliderUndoSnapshot: PortraitUndoManager.Snapshot? = nil
    @State private var sliderActionName: String? = nil
    @State private var showExport = false
    @State private var showBulkAlignConfirm = false
    @State private var bulkSkippedCount: Int? = nil

    /// Which pane the right-hand inspector is showing. Persisted across launches.
    @AppStorage("editorTab") private var editorTab: EditorTab = .portrait

    enum EditorTab: String, CaseIterable, Identifiable {
        case portrait, adjust
        var id: String { rawValue }
        var label: String {
            switch self {
            case .portrait: return Loc.tabPortrait
            case .adjust:   return Loc.tabAdjust
            }
        }
        var symbol: String {
            switch self {
            case .portrait: return "person.crop.square"
            case .adjust:   return "slider.horizontal.3"
            }
        }
    }

    /// Shows a semi-transparent alignment guide (eye markers + head oval)
    /// on the canvas so you can visually verify that all portraits share the
    /// same eye height and head size. Persisted across app launches.
    @AppStorage("showAlignmentGuide") private var showAlignmentGuide = false

    /// Labs flag — gates the "More" dropdown (Fill in Body etc.) behind
    /// the Settings → Labs toggle. Off by default while we tune quality.
    @AppStorage(kFillBodyEnabledKey) private var fillBodyEnabled: Bool = false

    // Drag/snap state
    @State private var isDragging = false
    @State private var snappedX = false
    @State private var snappedY = false
    /// Last haptic tick position in canvas units — used to emit a soft tick
    /// every `hapticStep` units during a drag (Premiere-Pro style continuous feel).
    @State private var lastHapticTickX: Double = 0
    @State private var lastHapticTickY: Double = 0
    private let hapticStep: Double = 24

    /// Canvas view-zoom multiplier. Pinch = zoom the editing canvas in/out
    /// without touching the underlying portrait transform. 1.0 = fit window.
    @State private var canvasZoom: Double = 1.0

    /// Tap the image to show bounding-box handles for proportional scaling.
    /// Tap elsewhere, press Escape, or start a drag to dismiss.
    @State private var imageSelected = false

    // Drag-and-drop of a NEW photo onto the editor: lets the user start a fresh
    // portrait without going back to an empty state. ImportFlow auto-selects
    // the new portrait, so the editor switches to it on completion.
    @State private var isDropping = false
    @State private var showInspector = true

    // "More magic edits" — hover reveals card chrome; click reveals a
    // floating dropdown 8pt below the trigger (overlay, not inline — must
    // not push siblings down).
    @State private var isMoreOpen = false
    @State private var isMoreHovering = false
    @State private var isFillBodyHovering = false
    #if os(macOS)
    private let haptics = NSHapticFeedbackManager.defaultPerformer
    #endif

    // Snap thresholds in canvas units (1024 = full canvas).
    private let snapEnter: Double = 12
    private let snapExit: Double = 24

    private var selectedBackground: BackgroundPreset? {
        if let id = portrait.backgroundPresetID,
           let bg = backgrounds.first(where: { $0.id == id }) {
            return bg
        }
        return backgrounds.first(where: { $0.isDefault }) ?? backgrounds.first
    }

    var body: some View {
        canvasArea
            .inspector(isPresented: $showInspector) {
                controlsPanel
                    .inspectorColumnWidth(min: 320, ideal: 340, max: 400)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        commitSliderUndo()
                        undoManager?.undo()
                    } label: {
                        Label(Loc.undo, systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!(undoManager?.canUndo ?? false) && sliderUndoSnapshot == nil)
                    .help(Loc.undoHelp)

                    Button {
                        commitSliderUndo()
                        undoManager?.redo()
                    } label: {
                        Label(Loc.redo, systemImage: "arrow.uturn.forward")
                    }
                    .disabled(!(undoManager?.canRedo ?? false))
                    .help(Loc.redoHelp)
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Toggle(isOn: $showAlignmentGuide) {
                            Label(Loc.alignmentShowGuide, systemImage: "rectangle.dashed")
                        }
                        Divider()
                        Button {
                            showBulkAlignConfirm = true
                        } label: {
                            Label(Loc.alignAllPortraits, systemImage: "rectangle.3.group")
                        }
                        .disabled(alignableCount < 2)
                    } label: {
                        Label(Loc.alignmentGuide, systemImage: "viewfinder")
                    }
                    .help(Loc.alignmentGuideHelp)

                    Button {
                        showInspector.toggle()
                    } label: {
                        Label(Loc.inspector, systemImage: "sidebar.trailing")
                    }
                    .help(Loc.inspectorHelp)
                    .keyboardShortcut("i", modifiers: [.command, .option])

                    Button {
                        showExport = true
                    } label: {
                        Label(Loc.export, systemImage: "square.and.arrow.up")
                    }
                    .help(Loc.exportHelp)
                    .keyboardShortcut("e", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $showExport) {
                ExportSheet(portrait: portrait, background: selectedBackground)
            }
            .onDrop(of: [.fileURL, .image], isTargeted: $isDropping) { providers in
                PortraitDropHandler.handle(providers: providers,
                                           existingPortraitCount: allPortraits.count,
                                           context: context,
                                           appState: appState)
            }
            .overlay {
                if isDropping {
                    NewPhotoDropOverlay()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                } else if appState.isProcessing {
                    ProcessingOverlay()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            // Banner overlay — `appState.note(...)` / `warn(...)` / `fail(...)`
            // set this. Previously only ImportDropZone rendered the banner,
            // so any toast triggered while the editor was on screen (e.g.
            // Fill in Body's "already complete" no-op) flipped silently.
            .overlay(alignment: .bottom) {
                if let banner = appState.errorBanner {
                    StatusChip(severity: banner.severity,
                               message: banner.message,
                               onDismiss: { appState.dismissBanner() })
                        .padding(.bottom, 24)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeOut(duration: 0.15), value: isDropping)
            .animation(.easeOut(duration: 0.15), value: appState.isProcessing)
            .animation(.easeOut(duration: 0.20), value: appState.errorBanner)
            // Floating "More" dropdown rendered at root so its dismiss-catcher
            // can cover the entire window. The catcher (Color.clear behind the
            // panel) closes the menu on any outside click; clicks on the
            // dropdown's button reach the button because it sits in front of
            // the catcher in the ZStack.
            .overlayPreferenceValue(MoreTriggerAnchorKey.self) { anchor in
                GeometryReader { proxy in
                    if isMoreOpen, let anchor {
                        let rect = proxy[anchor]
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.18)) { isMoreOpen = false }
                                }
                            fillBodyDropdown
                                .frame(width: rect.width)
                                .offset(x: rect.minX, y: rect.maxY + 8)
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .offset(y: -6)),
                                        removal: .opacity
                                    )
                                )
                        }
                    }
                }
            }
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        GeometryReader { geo in
            // Canvas padding scales down on small windows so the preview
            // doesn't shrink to nothing when the controls panel takes its share.
            let shortSide = min(geo.size.width, geo.size.height)
            let padding: CGFloat = shortSide > 420 ? 48 : 16
            let fitSide = max(40, shortSide - padding)
            // User-controlled canvas zoom (pinch) multiplies the fit-size.
            let side = max(40, fitSide * canvasZoom)
            ZStack {
                // Background tap = deselect (dismiss handles).
                Color.appCanvas
                    .contentShape(Rectangle())
                    .onTapGesture { imageSelected = false }

                ZStack {
                    ZStack {
                        CanvasPreview(
                            portrait: portrait,
                            background: selectedBackground
                        )
                        AlignmentGuideOverlay(isVisible: showAlignmentGuide)
                        GuideLinesOverlay(
                            isVisible: isDragging,
                            snappedX: snappedX,
                            snappedY: snappedY
                        )
                    }
                    // Editor always shows the square canvas; the circular crop
                    // is applied at export time based on the chosen preset.
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                    .contentShape(RoundedRectangle(cornerRadius: 4))
                    // Tap on image = select (show handles).
                    .onTapGesture { imageSelected = true }
                    .gesture(dragGesture(canvasSide: side))

                    // Bounding-box handles only visible+interactive when selected.
                    BoundingBoxOverlay(
                        portrait: portrait,
                        canvasSide: side,
                        cutoutSize: cutoutSize,
                        isVisible: imageSelected,
                        onCommit: { try? context.save() }
                    )
                }
                .frame(width: side, height: side)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(magnifyGesture)
            .onExitCommand { imageSelected = false }
        }
    }

    /// Current cutout pixel size (or zero if not yet loaded). Used by the
    /// bounding-box overlay to place handles.
    private var cutoutSize: CGSize {
        guard let cg = appState.cutout(for: portrait) else { return .zero }
        return CGSize(width: cg.width, height: cg.height)
    }

    private func dragGesture(canvasSide: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStart == nil {
                    commitSliderUndo()
                    dragStart = CGSize(width: portrait.offsetX, height: portrait.offsetY)
                    dragUndoSnapshot = PortraitUndoManager.snapshot(of: portrait)
                    isDragging = true
                    imageSelected = false   // dismiss bounding-box handles on drag
                    lastHapticTickX = portrait.offsetX
                    lastHapticTickY = portrait.offsetY
                }

                // Map screen-space delta to canvas-space (canvas is 1024 units wide).
                let factor = CanvasConstants.editCanvas.width / canvasSide
                var dx = value.translation.width * factor
                var dy = value.translation.height * factor

                // Shift = constrain to dominant axis (Figma/Instagram style).
                if NSEvent.modifierFlags.contains(.shift) {
                    if abs(value.translation.width) >= abs(value.translation.height) {
                        dy = 0
                    } else {
                        dx = 0
                    }
                }

                let rawX = dragStart!.width + dx
                let rawY = dragStart!.height + dy

                // Snap-to-center with hysteresis: enter at 12, release at 24 canvas units.
                let canvasCenter = CanvasConstants.editCanvas.width / 2
                var newX = rawX
                var newY = rawY
                var newSnappedX = snappedX
                var newSnappedY = snappedY

                if let cutout = appState.cutout(for: portrait) {
                    let imgW = Double(cutout.width) * portrait.scale
                    let imgH = Double(cutout.height) * portrait.scale
                    let rawCenterX = rawX + imgW / 2
                    let rawCenterY = rawY + imgH / 2

                    let thresholdX = snappedX ? snapExit : snapEnter
                    if abs(rawCenterX - canvasCenter) < thresholdX {
                        newX = canvasCenter - imgW / 2
                        newSnappedX = true
                    } else {
                        newSnappedX = false
                    }

                    let thresholdY = snappedY ? snapExit : snapEnter
                    if abs(rawCenterY - canvasCenter) < thresholdY {
                        newY = canvasCenter - imgH / 2
                        newSnappedY = true
                    } else {
                        newSnappedY = false
                    }
                }

                // Snap-zone transitions get the stronger .alignment tick (the
                // system "click into place" feel). Plain movement gets a soft
                // .generic tick every `hapticStep` canvas units so the drag has
                // the continuous texture Premiere Pro's timeline has.
                let snapChanged = (newSnappedX != snappedX) || (newSnappedY != snappedY)
                if snapChanged {
                    #if os(macOS)
                    haptics.perform(.alignment, performanceTime: .now)
                    #endif
                    lastHapticTickX = newX
                    lastHapticTickY = newY
                } else {
                    if abs(newX - lastHapticTickX) >= hapticStep ||
                       abs(newY - lastHapticTickY) >= hapticStep {
                        #if os(macOS)
                        haptics.perform(.generic, performanceTime: .now)
                        #endif
                        lastHapticTickX = newX
                        lastHapticTickY = newY
                    }
                }
                snappedX = newSnappedX
                snappedY = newSnappedY

                portrait.offsetX = newX
                portrait.offsetY = newY
                portrait.updatedAt = Date()
            }
            .onEnded { _ in
                if let before = dragUndoSnapshot {
                    try? context.save()
                    PortraitUndoManager.registerFromSnapshots(
                        before: before,
                        after: PortraitUndoManager.snapshot(of: portrait),
                        context: context,
                        undoManager: undoManager,
                        appState: appState,
                        actionName: Loc.moveAction
                    )
                } else {
                    try? context.save()
                }
                dragStart = nil
                dragUndoSnapshot = nil
                isDragging = false
                snappedX = false
                snappedY = false
            }
    }

    /// Pinch zooms the CANVAS viewport (not the portrait image). The portrait
    /// is scaled by dragging the bounding-box handles instead.
    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = Double(value) / max(0.0001, lastMag)
                canvasZoom = max(0.3, min(4.0, canvasZoom * delta))
                lastMag = Double(value)
            }
            .onEnded { _ in
                lastMag = 1.0
            }
    }
    @State private var lastMag: Double = 1.0

    // MARK: - Controls

    private var controlsPanel: some View {
        VStack(spacing: 0) {
            PillSegmentedControl(
                selection: $editorTab,
                segments: EditorTab.allCases.map {
                    .init(tag: $0, label: $0.label, symbol: $0.symbol)
                }
            )
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            Group {
                switch editorTab {
                case .portrait: portraitTab
                case .adjust:   adjustTabContainer
                }
            }
            .id(editorTab)
            .transition(
                .opacity.animation(.easeOut(duration: 0.18))
            )
        }
        .background(Color.appCanvas)
        .confirmationDialog(
            Loc.alignAllQuestion,
            isPresented: $showBulkAlignConfirm,
            titleVisibility: .visible
        ) {
            Button(Loc.alignButton(alignableCount), role: .destructive) { bulkAlign() }
            Button(Loc.cancel, role: .cancel) { }
        } message: {
            Text(Loc.alignConfirmMessage(alignableCount))
        }
        .alert(Loc.alignComplete, isPresented: Binding(
            get: { bulkSkippedCount != nil },
            set: { if !$0 { bulkSkippedCount = nil } }
        )) {
            Button(Loc.ok) { bulkSkippedCount = nil }
        } message: {
            if let n = bulkSkippedCount {
                Text(Loc.skippedPortraits(n))
            }
        }
    }

    // MARK: Portrait tab

    @ViewBuilder private var portraitTab: some View {
        ScrollView {
            VStack(spacing: 18) {
                inspectorSection(title: Loc.info) {
                    VStack(spacing: 0) {
                        infoRow(symbol: "person.crop.circle",
                                placeholder: Loc.employeeName,
                                text: $portrait.name)
                        Divider()
                            .padding(.vertical, 10)
                        infoRow(symbol: "tag",
                                placeholder: Loc.role,
                                text: $portrait.tags)
                    }
                }

                inspectorSection(title: Loc.background) {
                    BackgroundPicker(portrait: portrait, backgrounds: backgrounds)
                }

                inspectorSection(title: Loc.edit) {
                    enhanceSectionBody
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var adjustTabContainer: some View {
        Form { adjustTab }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func infoRow(symbol: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .onChange(of: text.wrappedValue) { _, _ in try? context.save() }
        }
    }

    /// Section card chrome: a subtle elevated surface (`appSurface`) above the
    /// sidebar's `appCanvas`, with a small uppercase header. Mirrors the layered
    /// look of `PillSegmentedControl` so the inspector reads as one family.
    @ViewBuilder
    private func inspectorSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            content()
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.appSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                )
        }
    }

    // MARK: Enhance section (lives inside the Portrait tab)

    /// True whenever this portrait still carries a free Apple-pipeline cutout.
    /// The card is a one-shot offer to re-cut via cloud Magic Cutout —
    /// independent of the persistent "Magic Cutout" import toggle. Clicking
    /// runs cloud regardless of the toggle, and surfaces the paywall if the
    /// user has neither Pro nor free-trial credit left.
    private var showMagicCutoutUpgradeCard: Bool {
        portrait.originalImageData != nil
            && !portrait.cutoutUsedMagic
    }

    @ViewBuilder private var enhanceSectionBody: some View {
        VStack(spacing: 10) {
            enhanceCard(
                title: Loc.autoAlignFace,
                systemImage: "face.smiling",
                disabled: portrait.faceRect == .zero,
                help: Loc.autoAlignFace
            ) {
                autoAlign()
            }

            enhanceCard(
                title: portrait.isMagicRetouched ? Loc.magicRetouchUndo : Loc.magicRetouch,
                systemImage: portrait.isMagicRetouched ? "arrow.uturn.backward" : "wand.and.sparkles",
                disabled: portrait.cutoutPNG == nil || appState.isProcessing,
                help: portrait.isMagicRetouched ? Loc.magicRetouchUndoHelp : Loc.magicRetouchHelp,
                active: portrait.isMagicRetouched
            ) {
                if portrait.isMagicRetouched {
                    ImportFlow.undoMagicRetouch(portrait: portrait, context: context, appState: appState)
                } else {
                    ImportFlow.magicRetouch(portrait: portrait, context: context, appState: appState)
                }
            }

            // Re-cutout is intentionally hidden by default — we promise the
            // initial cutout is right the first time. The single exception:
            // an existing cutout produced by the free Apple pipeline while the
            // user is now Pro with Magic Cutout enabled. In that case we
            // surface a one-shot "redo with Magic Cutout" affordance, which
            // disappears again once the upgraded cutout lands.
            if showMagicCutoutUpgradeCard {
                enhanceCard(
                    title: Loc.redoWithMagicCutout,
                    systemImage: "wand.and.stars",
                    disabled: appState.isProcessing,
                    help: Loc.redoWithMagicCutoutHelp
                ) {
                    ImportFlow.reprocess(portrait: portrait, context: context, appState: appState)
                }
            }

            // "More" — extensible dropdown for Pro AI edits, always pinned
            // to the bottom of the section. Currently houses Fill in Body
            // (gated behind Settings → Labs while we tune output quality);
            // future additions (Colorise, background swap, etc.) slot in
            // alongside without restructuring the inspector. Rendered as a
            // Menu using the same chrome as the regular enhance cards so
            // the section reads as one column of equally-weighted actions.
            if fillBodyEnabled {
                moreMagicEditsSection
            }
        }
    }

    /// "More" trigger only — the dropdown itself is rendered at the body
    /// level via `overlayPreferenceValue` (see `body`). Local overlay is
    /// avoided so we can place a transparent dismiss-catcher *behind* the
    /// dropdown that closes the menu on any outside click without blocking
    /// clicks on the menu items themselves.
    @ViewBuilder private var moreMagicEditsSection: some View {
        moreMagicEditsTrigger
            .anchorPreference(key: MoreTriggerAnchorKey.self, value: .bounds) { $0 }
    }

    /// Default state: text-only "✨ More". Hover/open state: same content in
    /// the same position, with the card fill + border faded in. Position never
    /// shifts — only the surrounding chrome appears.
    @ViewBuilder private var moreMagicEditsTrigger: some View {
        let disabled = portrait.cutoutPNG == nil || appState.isProcessing
        let showChrome = isMoreHovering || isMoreOpen
        Button {
            withAnimation(.easeOut(duration: 0.18)) { isMoreOpen.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .regular))
                Text(Loc.moreMagicEdits)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(showChrome ? 0.04 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(showChrome ? 0.08 : 0), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isMoreHovering = hovering }
        }
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .help(Loc.moreMagicEditsHelp)
    }

    /// Floating menu panel. Distinct dark surface (separate from the inspector
    /// background) so items read clearly; subtle border + shadow give it lift.
    /// Item rows are flat (no per-row card chrome) — the panel is the surface,
    /// hover provides per-row affordance.
    @ViewBuilder private var fillBodyDropdown: some View {
        VStack(spacing: 0) {
            fillBodyDropdownItem
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 8)
        )
    }

    @ViewBuilder private var fillBodyDropdownItem: some View {
        let title = portrait.isFillBodyApplied ? Loc.fillBodyUndo : Loc.fillBody
        let icon = portrait.isFillBodyApplied ? "arrow.uturn.backward" : "rectangle.expand.vertical"
        let active = portrait.isFillBodyApplied
        let showProBadge = !appState.proEntitlement.isPro && !portrait.isFillBodyApplied
        // Mirror the trigger's `isProcessing` guard. Without this, once the
        // dropdown is open the inner button stays live during a running
        // Fill in Body, and every extra tap spawns a parallel backend
        // request — that's what was tripping the server-side rate limiter
        // into "Too many requests" toasts.
        let busy = appState.isProcessing
        Button {
            withAnimation(.easeOut(duration: 0.18)) { isMoreOpen = false }
            if portrait.isFillBodyApplied {
                ImportFlow.undoFillBody(portrait: portrait, context: context, appState: appState, undoManager: undoManager)
            } else {
                ImportFlow.fillBody(portrait: portrait, context: context, appState: appState, undoManager: undoManager)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(active ? Color.accentColor : Color.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(active ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.08))
                    )
                Text(title)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                if showProBadge { ProBadge() }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isFillBodyHovering ? 0.08 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.10)) { isFillBodyHovering = hovering }
        }
        .disabled(busy)
        .opacity(busy ? 0.45 : 1)
    }

    @ViewBuilder
    private func enhanceCard(
        title: String,
        systemImage: String,
        disabled: Bool,
        help: String,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            enhanceCardLabel(title: title, systemImage: systemImage, active: active)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .help(help)
    }

    /// The elevated-card visual chrome shared by `enhanceCard` (Button) and
    /// the "More magic edits" Menu so both sit identically in the section.
    /// `trailingSystemImage` adds an indicator (e.g. chevron) when the
    /// label is acting as a Menu opener.
    @ViewBuilder
    private func enhanceCardLabel(
        title: String,
        systemImage: String,
        active: Bool = false,
        trailingSystemImage: String? = nil,
        showProBadge: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(active ? Color.accentColor : Color.primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                )
                .symbolEffect(.bounce, value: active)
            Text(title)
                .fontWeight(.medium)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
            if showProBadge {
                ProBadge()
            }
            if let trailing = trailingSystemImage {
                Image(systemName: trailing)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Adjust tab

    @ViewBuilder private var adjustTab: some View {
        Section {
            adjustmentSlider(Loc.exposure,    icon: "sun.max",            value: $portrait.adjExposure,    range: -2...2,       neutral: 0,   displayScale: 50)
            adjustmentSlider(Loc.contrast,    icon: "circle.lefthalf.filled", value: $portrait.adjContrast,    range: 0.5...1.5,    neutral: 1,   displayScale: 200)
            adjustmentSlider(Loc.tint,        icon: "drop",               value: $portrait.adjTint,        range: -100...100,   neutral: 0,   displayScale: 1)
            adjustmentSlider(Loc.saturation,  icon: "paintpalette",       value: $portrait.adjSaturation,  range: 0...2,        neutral: 1,   displayScale: 100)
            adjustmentSlider(Loc.temperature, icon: "thermometer.medium", value: $portrait.adjTemperature, range: -2000...2000, neutral: 0,   displayScale: 0.05)
            adjustmentSlider(Loc.highlights,  icon: "sun.horizon",        value: $portrait.adjHighlights,  range: 0...2,        neutral: 1,   displayScale: 100)
            adjustmentSlider(Loc.shadows,     icon: "moon",               value: $portrait.adjShadows,     range: -1...1,       neutral: 0,   displayScale: 100)

            if isAdjustmentsDirty {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { resetAdjustments() }
                } label: {
                    Label(Loc.resetAdjustments, systemImage: "arrow.counterclockwise")
                }
                .foregroundStyle(.secondary)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            Text(Loc.colorAdjustments)
        }
    }

    private var isAdjustmentsDirty: Bool {
        portrait.adjExposure != 0 ||
        portrait.adjContrast != 1 ||
        portrait.adjTint != 0 ||
        portrait.adjSaturation != 1 ||
        portrait.adjTemperature != 0 ||
        portrait.adjHighlights != 1 ||
        portrait.adjShadows != 0
    }

    private func adjustmentSlider(
        _ label: String,
        icon: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        neutral: Double,
        displayScale: Double
    ) -> some View {
        let isDirty = value.wrappedValue != neutral
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .opacity(isDirty ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: isDirty)
                Spacer()
                Text(String(format: "%+.0f", (value.wrappedValue - neutral) * displayScale))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .opacity(isDirty ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: isDirty)
            }
            ZStack {
                Slider(
                    value: Binding(
                        get: { value.wrappedValue },
                        set: { newValue in
                            trackSliderUndo(actionName: label)
                            let snapThreshold = (range.upperBound - range.lowerBound) * 0.02
                            let wasOff = value.wrappedValue != neutral
                            let snapped = abs(newValue - neutral) < snapThreshold ? neutral : newValue
                            if snapped == neutral && wasOff {
                                #if os(macOS)
                                haptics.perform(.alignment, performanceTime: .now)
                                #endif
                            }
                            // Live preview only mutates the model in memory; the
                            // SwiftData save and updatedAt bump are deferred to
                            // drag-end via onEditingChanged. The adjustedCutout
                            // cache self-invalidates on key mismatch so we don't
                            // need to clear it per tick.
                            value.wrappedValue = snapped
                        }
                    ),
                    in: range,
                    onEditingChanged: { editing in
                        if !editing {
                            portrait.updatedAt = Date()
                            try? context.save()
                        }
                    }
                )
                // Subtle tick mark on the track at the neutral position.
                GeometryReader { geo in
                    let fraction = (neutral - range.lowerBound) / (range.upperBound - range.lowerBound)
                    Rectangle()
                        .fill(Color.secondary.opacity(isDirty ? 0 : 0.55))
                        .frame(width: 1.5, height: 6)
                        .position(x: geo.size.width * fraction, y: geo.size.height / 2)
                        .animation(.easeOut(duration: 0.12), value: isDirty)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func resetAdjustments() {
        commitSliderUndo()
        let before = PortraitUndoManager.snapshot(of: portrait)
        portrait.adjExposure = 0
        portrait.adjContrast = 1
        portrait.adjSaturation = 1
        portrait.adjTemperature = 0
        portrait.adjTint = 0
        portrait.adjHighlights = 1
        portrait.adjShadows = 0
        portrait.updatedAt = Date()
        appState.invalidateAdjusted(for: portrait)
        try? context.save()
        PortraitUndoManager.registerFromSnapshots(
            before: before,
            after: PortraitUndoManager.snapshot(of: portrait),
            context: context,
            undoManager: undoManager,
            appState: appState,
            actionName: Loc.resetAdjustments
        )
    }

    /// Captures a "before" snapshot on the first slider tick. The snapshot
    /// is committed as an undo step when a different action starts or when
    /// `commitSliderUndo()` is called explicitly.
    private func trackSliderUndo(actionName: String) {
        // If a previous slider session exists for a different action, commit it first.
        if sliderUndoSnapshot != nil, sliderActionName != actionName {
            commitSliderUndo()
        }
        if sliderUndoSnapshot == nil {
            sliderUndoSnapshot = PortraitUndoManager.snapshot(of: portrait)
            sliderActionName = actionName
        }
    }

    private func commitSliderUndo() {
        guard let before = sliderUndoSnapshot else { return }
        PortraitUndoManager.registerFromSnapshots(
            before: before,
            after: PortraitUndoManager.snapshot(of: portrait),
            context: context,
            undoManager: undoManager,
            appState: appState,
            actionName: sliderActionName ?? Loc.adjustment
        )
        sliderUndoSnapshot = nil
        sliderActionName = nil
    }

    private func autoAlign() {
        guard let cutout = appState.cutout(for: portrait) else { return }
        commitSliderUndo()
        let before = PortraitUndoManager.snapshot(of: portrait)
        let size = CGSize(width: cutout.width, height: cutout.height)
        let t = AutoAligner.computeTransform(
            faceRect: portrait.faceRect,
            eyeCenter: portrait.eyeCenter,
            interEyeDistance: CGFloat(portrait.interEyeDistance),
            cutoutSize: size,
            bodyBottomY: CGFloat(portrait.bodyBottomY))
        portrait.scale = Double(t.scale)
        portrait.offsetX = Double(t.offset.width)
        portrait.offsetY = Double(t.offset.height)
        portrait.updatedAt = Date()
        try? context.save()
        PortraitUndoManager.registerFromSnapshots(
            before: before,
            after: PortraitUndoManager.snapshot(of: portrait),
            context: context,
            undoManager: undoManager,
            appState: appState,
            actionName: Loc.autoAlignAction
        )
    }

    // MARK: - Bulk align

    private var alignableCount: Int {
        allPortraits.reduce(0) { $0 + ($1.faceRect == .zero ? 0 : 1) }
    }

    private func bulkAlign() {
        let result = BulkAligner.alignAll(
            portraits: allPortraits,
            appState: appState,
            context: context,
            undoManager: undoManager
        )
        if result.skipped > 0 { bulkSkippedCount = result.skipped }
    }
}

private struct MoreTriggerAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

// MARK: - Bounding box with corner handles

/// Click-to-select overlay: tap the image to show a dashed outline and four
/// corner handles. Drag a handle to scale the portrait proportionally while
/// anchoring the opposite corner (Figma/Keynote style). Tap outside, press
/// Escape, or start a canvas-drag to dismiss. When hidden the overlay is
/// fully non-interactive so the canvas drag gesture works unimpeded.
struct BoundingBoxOverlay: View {
    @Bindable var portrait: Portrait
    let canvasSide: CGFloat
    let cutoutSize: CGSize
    let isVisible: Bool
    let onCommit: () -> Void

    @Environment(\.undoManager) private var undoManager
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @State private var dragStartScale: Double = 1
    @State private var dragStartOffsetX: Double = 0
    @State private var dragStartOffsetY: Double = 0
    @State private var activeHandle: Handle? = nil
    @State private var handleUndoSnapshot: PortraitUndoManager.Snapshot? = nil

    enum Handle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    var body: some View {
        GeometryReader { geo in
            if cutoutSize.width > 0, cutoutSize.height > 0, canvasSide > 0 {
                let viewScale = geo.size.width / CanvasConstants.editCanvas.width
                let imgW = cutoutSize.width * portrait.scale * viewScale
                let imgH = cutoutSize.height * portrait.scale * viewScale
                let originX = portrait.offsetX * viewScale
                let originY = portrait.offsetY * viewScale

                ZStack {
                    // Dashed outline around the image bounds.
                    Rectangle()
                        .strokeBorder(
                            Color.accentColor.opacity(0.7),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                        .frame(width: imgW, height: imgH)
                        .position(x: originX + imgW / 2, y: originY + imgH / 2)
                        .allowsHitTesting(false)

                    ForEach(Handle.allCases, id: \.self) { handle in
                        handleView(handle,
                                   originX: originX,
                                   originY: originY,
                                   imgW: imgW,
                                   imgH: imgH,
                                   viewScale: viewScale)
                    }
                }
                .opacity(isVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: isVisible)
            }
        }
        // Stable coordinate space for handle drag gestures — prevents
        // flickering caused by the handle moving mid-drag.
        .coordinateSpace(name: "boundingBox")
        // When hidden the overlay must not steal any gestures from the
        // canvas drag underneath.
        .allowsHitTesting(isVisible)
    }

    @ViewBuilder
    private func handleView(_ handle: Handle,
                            originX: CGFloat,
                            originY: CGFloat,
                            imgW: CGFloat,
                            imgH: CGFloat,
                            viewScale: CGFloat) -> some View {
        let pos = handlePosition(handle, originX: originX, originY: originY,
                                 imgW: imgW, imgH: imgH)
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: 12, height: 12)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            // 44pt invisible hit area for comfortable grab.
            // contentShape BEFORE .position() so the hit area stays on
            // the corner, not the parent center.
            .contentShape(Circle().inset(by: -16))
            .position(pos)
            // Gesture AFTER .position() with a named coordinate space so
            // translations stay stable as the handle moves during scaling.
            .highPriorityGesture(handleDragGesture(handle, viewScale: viewScale))
    }

    private func handlePosition(_ handle: Handle,
                                originX: CGFloat, originY: CGFloat,
                                imgW: CGFloat, imgH: CGFloat) -> CGPoint {
        switch handle {
        case .topLeft:     return CGPoint(x: originX,        y: originY)
        case .topRight:    return CGPoint(x: originX + imgW, y: originY)
        case .bottomLeft:  return CGPoint(x: originX,        y: originY + imgH)
        case .bottomRight: return CGPoint(x: originX + imgW, y: originY + imgH)
        }
    }

    private func handleDragGesture(_ handle: Handle, viewScale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("boundingBox"))
            .onChanged { value in
                if activeHandle != handle {
                    activeHandle = handle
                    handleUndoSnapshot = PortraitUndoManager.snapshot(of: portrait)
                    dragStartScale = portrait.scale
                    dragStartOffsetX = portrait.offsetX
                    dragStartOffsetY = portrait.offsetY
                }

                let factor = CanvasConstants.editCanvas.width / max(1, canvasSide)
                let dxCanvas = Double(value.translation.width) * factor
                let dyCanvas = Double(value.translation.height) * factor

                let startW = cutoutSize.width * dragStartScale
                let startH = cutoutSize.height * dragStartScale

                // Anchor = center of the bounding box (scale from center)
                let centerX = dragStartOffsetX + startW / 2
                let centerY = dragStartOffsetY + startH / 2

                let draggedCornerX: Double
                let draggedCornerY: Double
                switch handle {
                case .topLeft:
                    draggedCornerX = dragStartOffsetX + dxCanvas
                    draggedCornerY = dragStartOffsetY + dyCanvas
                case .topRight:
                    draggedCornerX = dragStartOffsetX + startW + dxCanvas
                    draggedCornerY = dragStartOffsetY + dyCanvas
                case .bottomLeft:
                    draggedCornerX = dragStartOffsetX + dxCanvas
                    draggedCornerY = dragStartOffsetY + startH + dyCanvas
                case .bottomRight:
                    draggedCornerX = dragStartOffsetX + startW + dxCanvas
                    draggedCornerY = dragStartOffsetY + startH + dyCanvas
                }

                let newW = abs(draggedCornerX - centerX) * 2
                let newH = abs(draggedCornerY - centerY) * 2
                let scaleFromW = newW / cutoutSize.width
                let scaleFromH = newH / cutoutSize.height
                let rawScale = max(scaleFromW, scaleFromH)
                let newScale = min(max(rawScale, 0.05), 8.0)

                let w = cutoutSize.width * newScale
                let h = cutoutSize.height * newScale
                let newOffsetX = centerX - w / 2
                let newOffsetY = centerY - h / 2

                portrait.scale = newScale
                portrait.offsetX = newOffsetX
                portrait.offsetY = newOffsetY
                portrait.updatedAt = Date()
            }
            .onEnded { _ in
                activeHandle = nil
                onCommit()
                if let before = handleUndoSnapshot {
                    PortraitUndoManager.registerFromSnapshots(
                        before: before,
                        after: PortraitUndoManager.snapshot(of: portrait),
                        context: context,
                        undoManager: undoManager,
                        appState: appState,
                        actionName: Loc.scale
                    )
                    handleUndoSnapshot = nil
                }
            }
    }

}

// MARK: - Guide lines

/// Vertical + horizontal center guides shown during a drag.
/// Lines turn from gray-dashed to accent-colored solid when the image
/// snaps to the corresponding axis.
struct GuideLinesOverlay: View {
    let isVisible: Bool
    let snappedX: Bool
    let snappedY: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Vertical center line (snaps on X axis)
                line(from: CGPoint(x: w / 2, y: 0),
                     to:   CGPoint(x: w / 2, y: h),
                     active: snappedX)

                // Horizontal center line (snaps on Y axis)
                line(from: CGPoint(x: 0, y: h / 2),
                     to:   CGPoint(x: w, y: h / 2),
                     active: snappedY)
            }
            .opacity(isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: isVisible)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func line(from start: CGPoint, to end: CGPoint, active: Bool) -> some View {
        Path { p in
            p.move(to: start)
            p.addLine(to: end)
        }
        .stroke(
            active ? Color.accentColor : Color.white.opacity(0.7),
            style: StrokeStyle(
                lineWidth: active ? 1.5 : 1,
                lineCap: .round,
                dash: active ? [] : [4, 4]
            )
        )
        .shadow(color: .black.opacity(active ? 0.35 : 0.2), radius: 1)
    }
}

// MARK: - Alignment guide overlay

/// Semi-transparent "onion skin" overlay that draws two eye markers and a
/// head oval at the canonical alignment position.  Toggle it on to visually
/// verify that every portrait in the library shares the same eye height and
/// head size — especially useful after a bulk-align.
struct AlignmentGuideOverlay: View {
    let isVisible: Bool

    // Cyan guide colour — visible on both light and dark backgrounds.
    private let guideColor = Color(red: 0, green: 0.82, blue: 0.87)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)

            // Target positions derived from the same constants the aligner uses.
            let ied    = CanvasConstants.targetInterEyeRatio * side
            let eyeCX  = CanvasConstants.targetEyeCenterX * side
            let eyeCY  = CanvasConstants.targetEyeCenterY * side
            let leftX  = eyeCX - ied / 2
            let rightX = eyeCX + ied / 2

            // Head oval — anthropometric proportions relative to inter-eye distance.
            let ovalW  = ied * 2.5
            let ovalH  = ied * 3.6
            // Eyes sit roughly 40% from the top of the skull, so the oval
            // centre is a bit below the eye line.
            let ovalCY = eyeCY + ovalH * 0.10

            ZStack {
                // ── Head oval ──────────────────────────────────
                Ellipse()
                    .stroke(guideColor.opacity(0.40),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: ovalW, height: ovalH)
                    .position(x: eyeCX, y: ovalCY)

                // ── Horizontal eye line ────────────────────────
                Path { p in
                    p.move(to:    CGPoint(x: eyeCX - ovalW * 0.55, y: eyeCY))
                    p.addLine(to: CGPoint(x: eyeCX + ovalW * 0.55, y: eyeCY))
                }
                .stroke(guideColor.opacity(0.30),
                        style: StrokeStyle(lineWidth: 0.75, dash: [4, 3]))

                // ── Left eye ───────────────────────────────────
                eyeMarker(at: CGPoint(x: leftX, y: eyeCY), size: ied * 0.30)

                // ── Right eye ──────────────────────────────────
                eyeMarker(at: CGPoint(x: rightX, y: eyeCY), size: ied * 0.30)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.25), radius: 1)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: isVisible)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func eyeMarker(at center: CGPoint, size: CGFloat) -> some View {
        ZStack {
            // Iris ring
            Circle()
                .stroke(guideColor.opacity(0.55), lineWidth: 1.5)
                .frame(width: size, height: size)
            // Pupil dot
            Circle()
                .fill(guideColor.opacity(0.45))
                .frame(width: size * 0.35, height: size * 0.35)
        }
        .position(center)
    }
}

// MARK: - Drop & processing overlays

/// Shown while the user is hovering a dragged image over the editor.
/// Subtle accent tint + dashed border + label so it's clear that releasing
/// here will start a new portrait.
private struct NewPhotoDropOverlay: View {
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.08)
            VStack(spacing: 14) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)
                Text(Loc.dropPhotoHere)
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            .padding(28)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.accentColor,
                              style: StrokeStyle(lineWidth: 2, dash: [10]))
                .padding(8)
        )
    }
}

/// Shown while ImportFlow is processing a freshly-dropped photo on the editor.
/// Uses the shared ProcessingStatusView so both the drop zone and the editor
/// cycle through the same playful status messages.
private struct ProcessingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.05)
            ProcessingStatusView()
        }
    }
}

// MARK: - Live preview canvas
//
// Built from native SwiftUI views (background layer + Image with scaleEffect/offset)
// rather than Canvas + Compositor. This is more reliable for live editing (no
// re-encode on every redraw) and lets gestures map 1:1 to view space.
// The Compositor is still used for PNG export.

struct CanvasPreview: View {
    let portrait: Portrait
    let background: BackgroundPreset?
    @Environment(AppState.self) private var appState

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            // Edit canvas is 1024pt; the visible side may differ. Scale all
            // stored canvas-space transforms to the visible side.
            let viewScale = side / CanvasConstants.editCanvas.width

            ZStack {
                backgroundView
                    .frame(width: side, height: side)

                if let cutout = appState.adjustedCutout(for: portrait) {
                    Image(decorative: cutout, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: CGFloat(cutout.width) * portrait.scale * viewScale,
                            height: CGFloat(cutout.height) * portrait.scale * viewScale
                        )
                        .position(
                            x: (portrait.offsetX + Double(cutout.width) * portrait.scale / 2) * viewScale,
                            y: (portrait.offsetY + Double(cutout.height) * portrait.scale / 2) * viewScale
                        )
                } else {
                    ProgressView()
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if let bg = background {
            switch bg.kind {
            case .image:
                if let img = appState.backgroundImage(for: bg) {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    fallbackColor
                }
            case .color:
                let c = bg.colorComponents
                Color(.sRGB, red: c.0, green: c.1, blue: c.2, opacity: c.3)
            }
        } else {
            fallbackColor
        }
    }

    private var fallbackColor: some View {
        Color(.sRGB, red: 0.94, green: 0.95, blue: 0.97, opacity: 1.0)
    }
}

// MARK: - Background picker

struct BackgroundPicker: View {
    @Bindable var portrait: Portrait
    let backgrounds: [BackgroundPreset]
    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    @Environment(AppState.self) private var appState
    @Query private var portraits: [Portrait]
    @State private var showAddPopover = false

    /// Single source of truth for which chip the picker should highlight. Mirrors the
    /// canvas-side `selectedBackground` resolution so exactly one chip lights up — even
    /// if the data has multiple `isDefault==true` entries from a prior corrupted state.
    private var effectiveBackgroundID: UUID? {
        if let id = portrait.backgroundPresetID,
           backgrounds.contains(where: { $0.id == id }) {
            return id
        }
        return backgrounds.first(where: { $0.isDefault })?.id ?? backgrounds.first?.id
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let activeID = effectiveBackgroundID
                ForEach(backgrounds) { bg in
                    BackgroundChip(
                        preset: bg,
                        isSelected: bg.id == activeID,
                        onSelect: { select(bg) },
                        onSetDefault: { setDefault(bg) },
                        onDelete: { delete(bg) }
                    )
                }
                AddBackgroundButton(showPopover: $showAddPopover) { kind in
                    addNewBackground(kind)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Actions

    private func select(_ bg: BackgroundPreset) {
        PortraitUndoManager.beginChange(for: portrait, context: context, undoManager: undoManager, appState: appState, actionName: Loc.backgroundAction)
        portrait.backgroundPresetID = bg.id
        portrait.updatedAt = Date()
        try? context.save()
    }

    private func setDefault(_ bg: BackgroundPreset) {
        for other in backgrounds { other.isDefault = false }
        bg.isDefault = true
        try? context.save()
    }

    private func delete(_ bg: BackgroundPreset) {
        // Clear the reference on EVERY portrait using this preset — otherwise
        // they'd keep pointing to a deleted model and the fallback lookup in
        // `selectedBackground` would silently pick the default (usually fine,
        // but cleaner to null them out explicitly).
        for p in portraits where p.backgroundPresetID == bg.id {
            p.backgroundPresetID = nil
        }
        appState.invalidateBackground(bg)
        context.delete(bg)
        try? context.save()
    }

    private func addNewBackground(_ kind: AddBackgroundKind) {
        switch kind {
        case .image:
            pickImageFile()
        case .color(let r, let g, let b):
            let bg = BackgroundPreset(
                name: Loc.color,
                kind: .color,
                color: (r, g, b, 1.0)
            )
            context.insert(bg)
            try? context.save()
            select(bg)
        }
    }

    private func pickImageFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            let name = url.deletingPathExtension().lastPathComponent
            let bg = BackgroundPreset(name: name, kind: .image, imageData: data)
            context.insert(bg)
            try? context.save()
            select(bg)
        }
        #endif
    }
}

// MARK: - Chip

struct BackgroundChip: View {
    let preset: BackgroundPreset
    let isSelected: Bool
    let onSelect: () -> Void
    let onSetDefault: () -> Void
    let onDelete: () -> Void

    @Environment(AppState.self) private var appState
    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var editName: String = ""
    @State private var isPressed = false
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if preset.kind == .image, let img = appState.backgroundImage(for: preset) {
                        Image(img, scale: 1, label: Text(""))
                            .resizable()
                            .scaledToFill()
                    } else {
                        let c = preset.colorComponents
                        Color(.sRGB, red: c.0, green: c.1, blue: c.2, opacity: c.3)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                                      lineWidth: isSelected ? 2.5 : 1)
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
                }
                .scaleEffect(isSelected ? 1.04 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
                .shadow(color: .black.opacity(isSelected ? 0.18 : 0.06),
                        radius: isSelected ? 6 : 2, y: isSelected ? 3 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isPressed)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !isPressed { isPressed = true } }
                        .onEnded { _ in
                            isPressed = false
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                onSelect()
                            }
                        }
                )
                .contextMenu { menuContents }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white, Color.accentColor)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                        .padding(4)
                        .symbolEffect(.bounce, value: isSelected)
                        .transition(.scale.combined(with: .opacity))
                }

                if isHovering && !isSelected {
                    Menu {
                        menuContents
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white, .black.opacity(0.55))
                            .shadow(radius: 1)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(4)
                }
            }
            .onHover { isHovering = $0 }

            if isRenaming {
                TextField(Loc.name, text: $editName, onCommit: finishRename)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.caption2)
                    .frame(width: 76)
            } else {
                Text(preset.name)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .frame(width: 80)
    }

    @ViewBuilder
    private var menuContents: some View {
        Button(Loc.select, action: onSelect)
        Button(Loc.rename) {
            editName = preset.name
            isRenaming = true
        }
        Button(preset.isDefault ? Loc.defaultCheck : Loc.setDefault, action: onSetDefault)
            .disabled(preset.isDefault)
        Divider()
        Button(Loc.delete, role: .destructive, action: onDelete)
            .disabled(preset.isDefault)
    }

    private func finishRename() {
        let trimmed = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            preset.name = trimmed
            try? context.save()
        }
        isRenaming = false
    }
}

// MARK: - Add button + popover

enum AddBackgroundKind {
    case image
    case color(Double, Double, Double)
}

struct AddBackgroundButton: View {
    @Binding var showPopover: Bool
    let onPick: (AddBackgroundKind) -> Void

    // Small curated palette. Kept neutral/on-brand — users can always upload custom.
    // Names are resolved at render time via Loc so they update on language change.
    private static let paletteColors: [(Double, Double, Double)] = [
        (1.00, 1.00, 1.00),
        (0.93, 0.95, 0.97),
        (0.96, 0.94, 0.91),
        (0.83, 0.89, 0.95),
        (0.85, 0.92, 0.86),
        (0.97, 0.89, 0.84),
        (0.15, 0.25, 0.45),
        (0.18, 0.19, 0.22),
    ]
    private static var paletteNames: [String] {
        [Loc.white, Loc.lightGray, Loc.warmWhite, Loc.softBlue,
         Loc.softGreen, Loc.peach, Loc.deepBlue, Loc.anthracite]
    }
    private var palette: [(String, Double, Double, Double)] {
        zip(Self.paletteNames, Self.paletteColors).map { ($0, $1.0, $1.1, $1.2) }
    }

    var body: some View {
        VStack(spacing: 4) {
            Button {
                showPopover.toggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.appSurface)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            Color.secondary.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1, dash: [3])
                        )
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 72, height: 72)
            }
            .buttonStyle(PressableButtonStyle())
            .popover(isPresented: $showPopover, arrowEdge: .top) {
                popoverContents
            }

            Text(Loc.add)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 80)
    }

    private var popoverContents: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showPopover = false
                onPick(.image)
            } label: {
                Label(Loc.uploadImage, systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())

            Divider()

            Text(Loc.chooseColor)
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 8), count: 4),
                      spacing: 8) {
                ForEach(palette, id: \.0) { item in
                    Button {
                        showPopover = false
                        onPick(.color(item.1, item.2, item.3))
                    } label: {
                        Circle()
                            .fill(Color(.sRGB, red: item.1, green: item.2, blue: item.3, opacity: 1))
                            .frame(width: 30, height: 30)
                            .overlay {
                                Circle().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                            }
                    }
                    .buttonStyle(PressableButtonStyle())
                    .help(item.0)
                }
            }
        }
        .padding(14)
        .frame(width: 240)
    }
}

