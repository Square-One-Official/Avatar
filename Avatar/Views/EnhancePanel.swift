import SwiftUI
import SwiftData
import AppKit

/// Discrete enhance actions plus click-to-reveal color sliders. Lives in the
/// editor inspector as a single panel so Magic Retouch and exposure stay in
/// the same working set — modelled on the macOS Display popover, not iOS
/// Control Center.
struct EnhancePanel: View {
    @Bindable var portrait: Portrait
    var trackSliderUndo: (String) -> Void
    var commitSliderUndo: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expandedAdjustment: AdjustmentKind? = nil

    #if os(macOS)
    private let haptics = NSHapticFeedbackManager.defaultPerformer
    #endif

    var body: some View {
        VStack(spacing: 16) {
            if showMagicCutoutUpgrade {
                compactActionRow(
                    title: Loc.redoWithMagicCutout,
                    systemImage: "wand.and.stars",
                    disabled: appState.isProcessing,
                    help: Loc.redoWithMagicCutoutHelp
                ) {
                    ImportFlow.reprocess(portrait: portrait, context: context, appState: appState)
                }
            }

            actionGrid

            adjustmentsBlock
        }
        .onAppear { expandFirstDirtyIfNeeded() }
        .onChange(of: portrait.id) { _, _ in
            expandedAdjustment = nil
            expandFirstDirtyIfNeeded()
        }
        .focusedSceneValue(\.enhanceCommands, commandTarget)
    }

    // MARK: Actions

    /// One-shot offer to re-cut a free Apple-pipeline cutout via cloud
    /// Magic Cutout. Hidden in local-only mode: redo IS a cloud call, and
    /// showing a disabled-with-upsell button would be dishonest.
    private var showMagicCutoutUpgrade: Bool {
        portrait.originalImageData != nil
            && !portrait.cutoutUsedMagic
            && appState.privacyPrefs.cloudAllowed
    }

    private var showFillBody: Bool {
        appState.privacyPrefs.cloudAllowed || portrait.isFillBodyApplied
    }

    private var showColorize: Bool {
        appState.privacyPrefs.cloudAllowed || portrait.isColorized
    }

    private var hasCutout: Bool { portrait.cutoutPNG != nil }
    private var isBusy: Bool { appState.isProcessing }

    private var actionGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 14
        ) {
            actionTile(
                title: Loc.autoAlignAction,
                accessibilityTitle: Loc.autoAlignFace,
                systemImage: "face.smiling",
                isToggle: false,
                isOn: false,
                disabled: portrait.faceRect == .zero,
                help: portrait.faceRect == .zero ? Loc.autoAlignDisabledHelp : Loc.autoAlignFace,
                showProBadge: false
            ) {
                autoAlign()
            }

            actionTile(
                title: Loc.magicRetouch,
                accessibilityTitle: Loc.magicRetouch,
                systemImage: "wand.and.sparkles",
                isToggle: true,
                isOn: portrait.isMagicRetouched,
                disabled: !hasCutout || isBusy,
                help: portrait.isMagicRetouched ? Loc.magicRetouchUndoHelp : Loc.magicRetouchHelp,
                showProBadge: false
            ) {
                toggleMagicRetouch()
            }

            if showFillBody {
                actionTile(
                    title: Loc.fillBody,
                    accessibilityTitle: Loc.fillBody,
                    systemImage: "bandage.fill",
                    isToggle: true,
                    isOn: portrait.isFillBodyApplied,
                    disabled: !hasCutout || isBusy,
                    help: portrait.isFillBodyApplied ? Loc.fillBodyUndoHelp : Loc.fillBodyHelp,
                    showProBadge: showFillProBadge
                ) {
                    toggleFillBody()
                }
            }

            if showColorize {
                actionTile(
                    title: Loc.colorize,
                    accessibilityTitle: Loc.colorize,
                    systemImage: "paintpalette",
                    isToggle: true,
                    isOn: portrait.isColorized,
                    disabled: !hasCutout || isBusy,
                    help: portrait.isColorized ? Loc.colorizeUndoHelp : Loc.colorizeHelp,
                    showProBadge: showColorizeProBadge
                ) {
                    toggleColorize()
                }
            }
        }
    }

    private var showFillProBadge: Bool {
        appState.privacyPrefs.cloudAllowed
            && !appState.proEntitlement.isPro
            && !portrait.isFillBodyApplied
    }

    private var showColorizeProBadge: Bool {
        appState.privacyPrefs.cloudAllowed
            && !appState.proEntitlement.isPro
            && !portrait.isColorized
    }

    @ViewBuilder
    private func actionTile(
        title: String,
        accessibilityTitle: String,
        systemImage: String,
        isToggle: Bool,
        isOn: Bool,
        disabled: Bool,
        help: String,
        showProBadge: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.body.weight(.medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isOn ? Color.appSurface : Color.primary)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle().fill(isOn ? Color.primary : Color.secondary.opacity(0.14))
                        )
                        .modifier(BounceSymbolIfMotionAllowed(isOn: isOn, reduceMotion: reduceMotion))

                    if showProBadge {
                        ProBadge()
                            .scaleEffect(0.85)
                            .offset(x: 6, y: -4)
                    }
                }

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(isToggle ? (isOn ? Loc.statusOn : Loc.statusOff) : " ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .opacity(isToggle ? 1 : 0)
                    .accessibilityHidden(!isToggle)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .help(help)
        .accessibilityLabel(showProBadge ? "\(accessibilityTitle), \(Loc.proPlanName)" : accessibilityTitle)
        .accessibilityValue(isToggle ? (isOn ? Loc.statusOn : Loc.statusOff) : "")
        .accessibilityHint(help)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func compactActionRow(
        title: String,
        systemImage: String,
        disabled: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
                Text(title)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
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
        .buttonStyle(PressableButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityHint(help)
    }

    // MARK: Adjustments

    private var adjustmentsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Loc.colorAdjustments)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            adjustmentTiles

            if let kind = expandedAdjustment {
                adjustmentSlider(kind)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isAdjustmentsDirty {
                Button {
                    Motion.run(reduceMotion, .easeOut(duration: 0.18)) {
                        expandedAdjustment = nil
                        resetAdjustments()
                    }
                } label: {
                    Label(Loc.resetAdjustments, systemImage: "arrow.counterclockwise")
                }
                .foregroundStyle(.secondary)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .motionAwareAnimation(.easeOut(duration: 0.18), value: expandedAdjustment)
        .motionAwareAnimation(.easeOut(duration: 0.18), value: isAdjustmentsDirty)
        .focusable()
        .onMoveCommand { direction in
            moveAdjustmentSelection(direction)
        }
    }

    private var adjustmentTiles: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
            spacing: 8
        ) {
            ForEach(AdjustmentKind.allCases) { kind in
                adjustmentTile(kind)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Loc.colorAdjustments)
    }

    @ViewBuilder
    private func adjustmentTile(_ kind: AdjustmentKind) -> some View {
        let isSelected = expandedAdjustment == kind
        let dirty = kind.isDirty(portrait)
        Button {
            Motion.run(reduceMotion, .easeOut(duration: 0.18)) {
                expandedAdjustment = isSelected ? nil : kind
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: kind.icon)
                    .font(.body.weight(.medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.appSurface : Color.primary)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(isSelected ? Color.primary : Color.secondary.opacity(0.14))
                    )

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .opacity(dirty ? 1 : 0)
                    .offset(x: 1, y: -1)
                    .accessibilityHidden(true)
            }
            .frame(width: 44, height: 44)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .help(kind.label)
        .accessibilityLabel(kind.label)
        .accessibilityValue(displayValue(for: kind))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(Loc.adjustmentTileHint)
    }

    @ViewBuilder
    private func adjustmentSlider(_ kind: AdjustmentKind) -> some View {
        let value = binding(for: kind)
        let dirty = kind.isDirty(portrait)
        let shown = displayValue(for: kind)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: kind.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)
                Text(kind.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .opacity(dirty ? 1 : 0)
                    .motionAwareAnimation(.easeOut(duration: 0.12), value: dirty)
                    .accessibilityHidden(true)
                Spacer()
                Text(shown)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ZStack {
                Slider(
                    value: Binding(
                        get: { value.wrappedValue },
                        set: { newValue in
                            trackSliderUndo(kind.label)
                            let snapThreshold = (kind.range.upperBound - kind.range.lowerBound) * 0.02
                            let wasOff = value.wrappedValue != kind.neutral
                            let snapped = abs(newValue - kind.neutral) < snapThreshold ? kind.neutral : newValue
                            if snapped == kind.neutral && wasOff {
                                #if os(macOS)
                                haptics.perform(.alignment, performanceTime: .now)
                                #endif
                            }
                            value.wrappedValue = snapped
                        }
                    ),
                    in: kind.range,
                    onEditingChanged: { editing in
                        if !editing {
                            portrait.updatedAt = Date()
                            try? context.save()
                        }
                    }
                )
                .accessibilityLabel(kind.label)
                .accessibilityValue(shown)

                GeometryReader { geo in
                    let fraction = (kind.neutral - kind.range.lowerBound)
                        / (kind.range.upperBound - kind.range.lowerBound)
                    Rectangle()
                        .fill(Color.secondary.opacity(dirty ? 0 : 0.55))
                        .frame(width: 1.5, height: 6)
                        .position(x: geo.size.width * fraction, y: geo.size.height / 2)
                        .motionAwareAnimation(.easeOut(duration: 0.12), value: dirty)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: Actions (logic)

    private func toggleMagicRetouch() {
        if portrait.isMagicRetouched {
            ImportFlow.undoMagicRetouch(portrait: portrait, context: context, appState: appState)
        } else {
            ImportFlow.magicRetouch(portrait: portrait, context: context, appState: appState)
        }
    }

    private func toggleFillBody() {
        if portrait.isFillBodyApplied {
            ImportFlow.undoFillBody(portrait: portrait, context: context, appState: appState, undoManager: undoManager)
        } else {
            ImportFlow.fillBody(portrait: portrait, context: context, appState: appState, undoManager: undoManager)
        }
    }

    private func toggleColorize() {
        if portrait.isColorized {
            ImportFlow.undoColorize(portrait: portrait, context: context, appState: appState, undoManager: undoManager)
        } else {
            ImportFlow.colorize(portrait: portrait, context: context, appState: appState, undoManager: undoManager)
        }
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

    private var isAdjustmentsDirty: Bool {
        AdjustmentKind.allCases.contains { $0.isDirty(portrait) }
    }

    private func expandFirstDirtyIfNeeded() {
        guard expandedAdjustment == nil else { return }
        expandedAdjustment = AdjustmentKind.allCases.first { $0.isDirty(portrait) }
    }

    private func moveAdjustmentSelection(_ direction: MoveCommandDirection) {
        let kinds = AdjustmentKind.allCases
        let current = expandedAdjustment ?? kinds[0]
        guard let idx = kinds.firstIndex(of: current) else { return }
        let nextIndex: Int
        switch direction {
        case .left, .up:
            nextIndex = max(0, idx - 1)
        case .right, .down:
            nextIndex = min(kinds.count - 1, idx + 1)
        default:
            return
        }
        Motion.run(reduceMotion, .easeOut(duration: 0.18)) {
            expandedAdjustment = kinds[nextIndex]
        }
    }

    private func binding(for kind: AdjustmentKind) -> Binding<Double> {
        switch kind {
        case .exposure:    $portrait.adjExposure
        case .contrast:    $portrait.adjContrast
        case .tint:        $portrait.adjTint
        case .saturation:  $portrait.adjSaturation
        case .temperature: $portrait.adjTemperature
        case .highlights:  $portrait.adjHighlights
        case .shadows:     $portrait.adjShadows
        }
    }

    private func displayValue(for kind: AdjustmentKind) -> String {
        String(format: "%+.0f", (binding(for: kind).wrappedValue - kind.neutral) * kind.displayScale)
    }

    private var commandTarget: EnhanceCommands {
        EnhanceCommands(
            autoAlign: { autoAlign() },
            canAutoAlign: portrait.faceRect != .zero && appState.cutout(for: portrait) != nil,
            toggleMagicRetouch: { toggleMagicRetouch() },
            canMagicRetouch: hasCutout && !isBusy,
            isMagicRetouched: portrait.isMagicRetouched,
            toggleFillBody: { toggleFillBody() },
            canFillBody: showFillBody && hasCutout && !isBusy,
            isFillBodyApplied: portrait.isFillBodyApplied,
            showFillBody: showFillBody,
            toggleColorize: { toggleColorize() },
            canColorize: showColorize && hasCutout && !isBusy,
            isColorized: portrait.isColorized,
            showColorize: showColorize,
            resetAdjustments: {
                expandedAdjustment = nil
                resetAdjustments()
            },
            canResetAdjustments: isAdjustmentsDirty
        )
    }
}

/// Applies `.symbolEffect(.bounce)` only when Reduce Motion is off.
private struct BounceSymbolIfMotionAllowed: ViewModifier {
    let isOn: Bool
    let reduceMotion: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.symbolEffect(.bounce, value: isOn)
        }
    }
}

// MARK: - Adjustment kinds

private enum AdjustmentKind: String, CaseIterable, Identifiable, Equatable {
    case exposure, contrast, tint, saturation, temperature, highlights, shadows
    var id: String { rawValue }

    var label: String {
        switch self {
        case .exposure:    Loc.exposure
        case .contrast:    Loc.contrast
        case .tint:        Loc.tint
        case .saturation:  Loc.saturation
        case .temperature: Loc.temperature
        case .highlights:  Loc.highlights
        case .shadows:     Loc.shadows
        }
    }

    var icon: String {
        switch self {
        case .exposure:    "sun.max"
        case .contrast:    "circle.lefthalf.filled"
        case .tint:        "drop"
        case .saturation:  "paintpalette"
        case .temperature: "thermometer.medium"
        case .highlights:  "sun.horizon"
        case .shadows:     "moon"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .exposure:    -2...2
        case .contrast:    0.5...1.5
        case .tint:        -100...100
        case .saturation:  0...2
        case .temperature: -2000...2000
        case .highlights:  0...2
        case .shadows:     -1...1
        }
    }

    var neutral: Double {
        switch self {
        case .exposure, .tint, .temperature, .shadows: 0
        case .contrast, .saturation, .highlights: 1
        }
    }

    var displayScale: Double {
        switch self {
        case .exposure:    50
        case .contrast:    200
        case .tint:        1
        case .saturation:  100
        case .temperature: 0.05
        case .highlights:  100
        case .shadows:     100
        }
    }

    func isDirty(_ portrait: Portrait) -> Bool {
        switch self {
        case .exposure:    portrait.adjExposure != 0
        case .contrast:    portrait.adjContrast != 1
        case .tint:        portrait.adjTint != 0
        case .saturation:  portrait.adjSaturation != 1
        case .temperature: portrait.adjTemperature != 0
        case .highlights:  portrait.adjHighlights != 1
        case .shadows:     portrait.adjShadows != 0
        }
    }
}
