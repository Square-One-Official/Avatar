// E37.13 — Freeform-stijl tekst-chrome op het canvas: blauwe selectierand,
// blauwe zij-handvatten (breedte → word-wrap), groen hoek-handvat (schaal),
// inline editor + floating toolbar. Selectie-gedreven (los van de active tool).

import AppKit
import AvatarUI
import SwiftUI

struct BannerCanvasTextChrome: View {
    @Bindable var doc: BannerDoc
    @Binding var selection: Set<BannerElementRef>
    let layerID: UUID
    var presentation: UIPresentationStore
    let canvasSize: CGSize
    let layout: BannerCanvasChromeMetrics.Layout
    let undoManager: UndoManager?
    @Binding var isEditing: Bool
    @Binding var toolbarVisible: Bool
    /// True zolang een handvat (schaal) actief gesleept wordt: de laag wordt dan
    /// uit de gebakken preview gehouden en live als vector-overlay getoond.
    @Binding var isManipulating: Bool

    @State private var draftString: String = ""
    /// UXS-1: de tekst zoals die was vóór de huidige edit-sessie — Escape zet
    /// 'm hiermee terug. nil = niet aan het bewerken.
    @State private var textBeforeEdit: String?
    @State private var scaleDragStartSize: Double?
    @State private var scaleDragStartBoxWidthCanvas: Double?
    /// Vast middelpunt van het kader bij start van de hoek-schaal (scherm-ruimte).
    @State private var scaleAnchorScreen: CGPoint?
    @State private var scaleStartDistance: CGFloat?
    /// Live waarden tijdens hoek-schaal — font én kaderbreedte schalen proportioneel.
    @State private var liveFontSize: Double?
    @State private var liveBoxWidthCanvas: Double?
    @State private var widthDragStart: Double?
    @State private var layersBeforeHandle: BannerLayers?
    @State private var toolbarMenusOpen = false
    @State private var toolbarMenuDismissNonce = 0
    @FocusState private var boxFocused: Bool

    private var layer: BannerTextLayer? {
        doc.layers.texts.first(where: { $0.id == layerID })
    }

    private var isScaling: Bool { liveFontSize != nil }

    /// De laag zoals hij NU getoond moet worden: tijdens typen volgt de string de
    /// live `draftString` (geen één-cyclus-lag → kader en tekst lopen synchroon),
    /// tijdens schalen volgt de fontgrootte `liveFontSize`.
    private var displayLayer: BannerTextLayer? {
        guard var l = layer else { return nil }
        if isEditing { l.string = draftString }
        if let live = liveFontSize { l.fontSize = live }
        return l
    }

    /// Anker voor de floating toolbar: midden boven het tekstkader.
    private func toolbarAnchor(for rect: CGRect) -> CGPoint {
        let halfMaxPanel: CGFloat = 124
        let minX = halfMaxPanel
        let maxX = layout.viewportSize.width - halfMaxPanel
        return CGPoint(x: min(max(rect.midX, minX), maxX), y: rect.minY)
    }

    private var showToolbar: Bool { (toolbarVisible || isEditing) && !isScaling }

    var body: some View {
        if let layer, let display = displayLayer,
           let rect = screenRect(
               for: display,
               frozenBoxWidthCanvas: isScaling ? liveBoxWidthCanvas : nil
           ) {
            ZStack {
                if toolbarMenusOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { toolbarMenuDismissNonce += 1 }
                }
                selectionBox(rect)
                if !isEditing, !isScaling, BannerTextPresets.isEmptyOrPlaceholder(display.string) {
                    placeholderHint(layer: display, rect: rect)
                }
                if isScaling, !BannerTextPresets.isEmptyOrPlaceholder(display.string) {
                    liveTextOverlay(layer: display, rect: rect)
                }
                if isEditing {
                    inlineEditor(layer: display, rect: rect)
                }
                sideHandle(rect: rect, side: -1)
                sideHandle(rect: rect, side: 1)
                scaleHandle(rect: rect)
                if showToolbar {
                    BannerTextFloatingToolbar(
                        doc: doc,
                        layerID: layerID,
                        presentation: presentation,
                        undoManager: undoManager,
                        anchorTextTop: toolbarAnchor(for: rect),
                        onDelete: removeLayer,
                        menuDismissNonce: toolbarMenuDismissNonce,
                        onMenusOpenChange: { toolbarMenusOpen = $0 }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dsMotion(DSMotion.fast, value: showToolbar)
            .onAppear {
                draftString = layer.string
                if !isEditing { boxFocused = true }
            }
            .onChange(of: layer.string) { _, new in
                if !isEditing { draftString = new }
            }
            .onChange(of: isEditing) { _, editing in
                if editing {
                    // Dubbelklik-pad (BannerCanvasOverlay): buiten een edit volgt
                    // `draftString` de laag, dus dít is de laatst vastgelegde tekst.
                    // Type-to-edit heeft de snapshot al gezet vóór het overschrijven.
                    if textBeforeEdit == nil { textBeforeEdit = draftString }
                } else {
                    textBeforeEdit = nil
                    boxFocused = true
                }
            }
        }
    }

    /// Live vector-weergave tijdens schalen: schaalt vloeiend mee met `liveFontSize`
    /// zonder de preview per frame te her-bakken (anti-flikker, geen dubbel beeld).
    private func liveTextOverlay(layer: BannerTextLayer, rect: CGRect) -> some View {
        let fontSize = max(1, layer.fontSize * layout.canvasScale)
        let nsFont = BannerFontPanelController.nsFont(from: layer)
        var text = Text(layer.string)
            .font(Font(NSFont(name: nsFont.fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)))
        if layer.italic == true { text = text.italic() }
        if layer.underline == true { text = text.underline() }
        return text
            .foregroundStyle(Color(hexRGB: layer.colorHex) ?? .white)
            .multilineTextAlignment(layer.alignRaw == 0 ? .leading : (layer.alignRaw == 2 ? .trailing : .center))
            .frame(width: rect.width, alignment: textSwiftUIAlignment(layer.alignRaw))
            .fixedSize(horizontal: false, vertical: true)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    // MARK: - Chrome

    private func selectionBox(_ rect: CGRect) -> some View {
        Rectangle()
            .strokeBorder(DSColor.Action.primary, lineWidth: 1.5)
            .frame(width: rect.width + 8, height: rect.height + 8)
            .contentShape(Rectangle())
            .focusable(!isEditing)
            .focusEffectDisabled()
            .focused($boxFocused)
            .onDeleteCommand { removeLayer() }
            .onKeyPress(phases: .down) { press in handleTypeToEdit(press) }
            .contextMenu {
                Button(role: .destructive) { removeLayer() } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .allowsHitTesting(!isEditing)
            .position(x: rect.midX, y: rect.midY)
    }

    private func placeholderHint(layer: BannerTextLayer, rect: CGRect) -> some View {
        let fontSize = max(12, layer.fontSize * layout.canvasScale)
        let nsFont = BannerFontPanelController.nsFont(from: layer)
        return Text(BannerTextPresets.placeholder)
            .font(Font(NSFont(name: nsFont.fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)))
            .foregroundStyle((Color(hexRGB: layer.colorHex) ?? .white).opacity(0.45))
            .multilineTextAlignment(layer.alignRaw == 0 ? .leading : (layer.alignRaw == 2 ? .trailing : .center))
            .frame(width: rect.width, alignment: textSwiftUIAlignment(layer.alignRaw))
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    /// Blauw zij-handvat: versleept zet de vaste box-breedte (word-wrap). `side`
    /// is -1 (links) of +1 (rechts); de box blijft op het anker gecentreerd.
    private func sideHandle(rect: CGRect, side: CGFloat) -> some View {
        Circle()
            .fill(DSColor.Action.primary)
            .frame(width: 11, height: 11)
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .contentShape(Circle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(BannerCanvasOverlay.space))
                    .onChanged { value in
                        if widthDragStart == nil {
                            widthDragStart = currentBoxWidthCanvas(rect: rect)
                            layersBeforeHandle = doc.layers
                        }
                        guard let start = widthDragStart,
                              let index = doc.layers.texts.firstIndex(where: { $0.id == layerID }) else { return }
                        let deltaCanvas = Double(value.translation.width / layout.canvasScale)
                        let newWidth = max(40, start + Double(side) * 2 * deltaCanvas)
                        var layers = doc.layers
                        layers.texts[index].width = newWidth / Double(canvasSize.width)
                        layers.texts[index].wrapsLines = true
                        doc.layers = layers
                    }
                    .onEnded { _ in commitHandle() }
            )
            .position(x: side < 0 ? rect.minX - 4 : rect.maxX + 4, y: rect.midY)
    }

    private func scaleHandle(rect: CGRect) -> some View {
        Circle()
            // UXS-18: was systeemgroen — de enige groene UI in een lime-DS.
            .fill(DSColor.Action.primary)
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .contentShape(Circle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(BannerCanvasOverlay.space))
                    .onChanged { value in
                        if scaleDragStartSize == nil {
                            scaleDragStartSize = layer?.fontSize
                            if let base = layer {
                                scaleDragStartBoxWidthCanvas = BannerLayoutMetrics.scaleFrameWidthCanvas(
                                    for: base, canvas: canvasSize
                                )
                            }
                            scaleAnchorScreen = CGPoint(x: rect.midX, y: rect.midY)
                            scaleStartDistance = max(
                                8,
                                hypot(value.startLocation.x - rect.midX, value.startLocation.y - rect.midY)
                            )
                            layersBeforeHandle = doc.layers
                            isManipulating = true
                        }
                        guard let startSize = scaleDragStartSize,
                              let startWidth = scaleDragStartBoxWidthCanvas,
                              let startDist = scaleStartDistance,
                              let anchor = scaleAnchorScreen,
                              startDist > 0 else { return }
                        // Proportioneel t.o.v. vast middelpunt — font én kader schalen gelijk (Freeform).
                        let dist = hypot(value.location.x - anchor.x, value.location.y - anchor.y)
                        let ratio = max(0.05, dist / startDist)
                        liveFontSize = max(8, startSize * ratio)
                        liveBoxWidthCanvas = max(40, startWidth * ratio)
                    }
                    .onEnded { _ in commitScale() }
            )
            .position(x: rect.maxX + 4, y: rect.maxY + 4)
    }

    private func commitScale() {
        defer {
            scaleDragStartSize = nil
            scaleDragStartBoxWidthCanvas = nil
            scaleAnchorScreen = nil
            scaleStartDistance = nil
            liveFontSize = nil
            liveBoxWidthCanvas = nil
            layersBeforeHandle = nil
            isManipulating = false
        }
        guard let final = liveFontSize,
              let index = doc.layers.texts.firstIndex(where: { $0.id == layerID }) else { return }
        let before = layersBeforeHandle ?? doc.layers
        var layers = doc.layers
        layers.texts[index].fontSize = final
        if let w = liveBoxWidthCanvas {
            layers.texts[index].width = w / Double(canvasSize.width)
        }
        doc.layers = layers
        BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: layers, actionName: "Resize text")
    }

    private func commitHandle() {
        if let before = layersBeforeHandle, before != doc.layers {
            BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: doc.layers, actionName: "Resize text")
        }
        scaleDragStartSize = nil
        scaleDragStartBoxWidthCanvas = nil
        scaleAnchorScreen = nil
        scaleStartDistance = nil
        liveFontSize = nil
        liveBoxWidthCanvas = nil
        widthDragStart = nil
        layersBeforeHandle = nil
    }

    private func currentBoxWidthCanvas(rect: CGRect) -> Double {
        if let frac = layer?.width { return frac * Double(canvasSize.width) }
        return Double(rect.width / layout.canvasScale)
    }

    // MARK: - Inline editor

    private func inlineEditor(layer: BannerTextLayer, rect: CGRect) -> some View {
        let fontSize = max(12, layer.fontSize * layout.canvasScale)
        let nsFont = BannerFontPanelController.nsFont(from: layer)
        var editorFont = NSFont(name: nsFont.fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        if layer.italic == true {
            editorFont = NSFontManager.shared.convert(editorFont, toHaveTrait: .italicFontMask)
        }
        let color = NSColor(Color(hexRGB: layer.colorHex) ?? .white)
        let selectAll = layer.string == BannerTextPresets.placeholder
        return BannerInlineTextField(
            text: $draftString,
            font: editorFont,
            color: color,
            underline: layer.underline == true,
            alignment: textAlignment(layer.alignRaw),
            placeholder: BannerTextPresets.placeholder,
            containerWidth: rect.width,
            focusOnFirstAppear: true,
            selectAllOnFirstFocus: selectAll,
            onSubmit: { commitText() },
            onCancel: { cancelText() },
            onDeleteWhenEmpty: removeLayer
        )
        .frame(
            width: rect.width,
            height: max(rect.height, fontSize + 4)
        )
        .position(x: rect.midX, y: rect.midY)
        .onChange(of: draftString) { _, new in
            guard let index = doc.layers.texts.firstIndex(where: { $0.id == layerID }) else { return }
            var layers = doc.layers
            layers.texts[index].string = new
            doc.layers = layers
        }
    }

    private func handleTypeToEdit(_ press: KeyPress) -> KeyPress.Result {
        let action = BannerTypeToEdit.action(
            for: press.characters,
            hasCommandOrControl: press.modifiers.contains(.command) || press.modifiers.contains(.control),
            isEditing: isEditing
        )
        switch action {
        case .ignore:
            return .ignored
        case let .begin(draft):
            // UXS-1: eerst de bestaande tekst vastleggen — de regel hieronder
            // overschrijft de draft met de zojuist getypte toets.
            textBeforeEdit = layer?.string ?? draftString
            draftString = draft
            toolbarVisible = true
            isEditing = true
            syncDraftToDoc()
            return .handled
        case let .appendToDraft(chars):
            // 37.17 (audit-B6): toets 2+ kan hier nog binnenkomen vóórdat de
            // inline NSTextView first responder is (de box heeft dan nog focus).
            // Bufferen in de draft i.p.v. `.ignored` — geen keystroke-verlies.
            draftString += chars
            syncDraftToDoc()
            return .handled
        }
    }

    /// Schrijft de live draft naar de doc-laag. Tijdens de first-responder-handoff
    /// (37.17) hangt de inline editor — en dus z'n `onChange(of: draftString)` —
    /// nog niet in de boom; zonder deze sync zou een commit direct na het typen
    /// de gebufferde tekens verliezen.
    private func syncDraftToDoc() {
        guard let index = doc.layers.texts.firstIndex(where: { $0.id == layerID }),
              doc.layers.texts[index].string != draftString else { return }
        var layers = doc.layers
        layers.texts[index].string = draftString
        doc.layers = layers
    }

    private func textAlignment(_ alignRaw: Int) -> NSTextAlignment {
        switch alignRaw {
        case 0: return .left
        case 2: return .right
        default: return .center
        }
    }

    private func textSwiftUIAlignment(_ alignRaw: Int) -> Alignment {
        switch alignRaw {
        case 0: return .leading
        case 2: return .trailing
        default: return .center
        }
    }

    // MARK: - Layout

    private func screenRect(for layer: BannerTextLayer, frozenBoxWidthCanvas: Double? = nil) -> CGRect? {
        let canvasRect: CGRect
        if let frozen = frozenBoxWidthCanvas {
            let boxW = CGFloat(frozen)
            let boxH = BannerLayoutMetrics.textBoxHeight(for: layer, canvas: canvasSize, boxW: boxW)
            let anchorX = layer.x * canvasSize.width
            let centerYTop = layer.y * canvasSize.height
            canvasRect = CGRect(x: anchorX - boxW / 2, y: centerYTop - boxH / 2, width: boxW, height: boxH)
        } else {
            canvasRect = BannerLayoutMetrics.textRect(layer: layer, canvas: canvasSize)
        }
        return BannerCanvasChromeMetrics.screenRect(canvasRect: canvasRect, layout: layout)
    }

    private func commitText() {
        isEditing = false
        if BannerTextPresets.isEmptyOrPlaceholder(draftString) {
            removeLayer()
        }
    }

    /// UXS-1: Escape — zet de tekst terug op de stand van vóór de edit en sluit
    /// de editor. Was de laag vers (placeholder/leeg vóór het typen), dan hoort er
    /// niets achter te blijven: die laag verdwijnt, net als bij ⌫ op een lege laag.
    /// Registreert bewust géén undo-stap — een geannuleerde edit is geen wijziging.
    private func cancelText() {
        let original = textBeforeEdit
        textBeforeEdit = nil
        isEditing = false
        guard let original else { return }
        if BannerTextPresets.isEmptyOrPlaceholder(original) {
            removeLayer()
            return
        }
        draftString = original
        guard let index = doc.layers.texts.firstIndex(where: { $0.id == layerID }),
              doc.layers.texts[index].string != original else { return }
        var layers = doc.layers
        layers.texts[index].string = original
        doc.layers = layers
    }

    private func removeLayer() {
        let before = doc.layers
        var layers = doc.layers
        layers.texts.removeAll { $0.id == layerID }
        doc.layers = layers
        BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: layers, actionName: "Delete text")
        selection.remove(.text(layerID))
    }
}

/// 37.17 (audit-B6) — Pure besluitlogica voor type-to-edit op de selectiebox.
/// Toets 1 start de editor (`begin`); toetsen die daarna nog in de chrome landen
/// — het gat tot de NSTextView first responder is — worden aan de draft geplakt
/// (`appendToDraft`) i.p.v. genegeerd. Los getrokken uit de view zodat het
/// contract unit-testbaar is.
enum BannerTypeToEdit {
    enum Action: Equatable {
        case ignore
        case begin(draft: String)
        case appendToDraft(String)
    }

    static func action(for characters: String, hasCommandOrControl: Bool, isEditing: Bool) -> Action {
        guard !hasCommandOrControl else { return .ignore }
        guard let first = characters.first,
              first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol || first == " " else {
            return .ignore
        }
        return isEditing ? .appendToDraft(characters) : .begin(draft: characters)
    }
}
