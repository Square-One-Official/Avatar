// E37.13 — Freeform-stijl tekst-chrome op het canvas: blauwe selectierand,
// schaal-handvat, inline editor + floating toolbar.

import AppKit
import AvatarUI
import SwiftUI

struct BannerCanvasTextChrome: View {
    @Bindable var doc: BannerDoc
    @Binding var selection: BannerCanvasSelection?
    let layerID: UUID
    let activeTool: BannerTool?
    let canvasSize: CGSize
    let drawn: CGSize
    let origin: CGPoint
    let scale: CGFloat
    let undoManager: UndoManager?
    @Binding var isEditing: Bool

    @State private var draftString: String = ""
    @State private var scaleDragStartSize: Double?
    @State private var scaleDragStartDistance: CGFloat?
    @State private var layersBeforeScale: BannerLayers?
    @FocusState private var boxFocused: Bool

    private var layer: BannerTextLayer? {
        doc.layers.texts.first(where: { $0.id == layerID })
    }

    private var deleteEnabled: Bool {
        activeTool == .text && !isEditing
    }

    var body: some View {
        if let layer, let rect = screenRect(for: layer) {
            ZStack {
                selectionBox(rect)
                if activeTool == .text {
                    inlineEditor(layer: layer, rect: rect)
                    scaleHandle(rect: rect)
                    BannerTextFloatingToolbar(doc: doc, layerID: layerID, undoManager: undoManager, onDelete: removeLayer)
                        .fixedSize()
                        .position(x: rect.midX, y: rect.maxY + 36)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                draftString = layer.string
                if BannerTextPresets.isEmptyOrPlaceholder(layer.string) {
                    isEditing = true
                } else {
                    boxFocused = true
                }
            }
            .onChange(of: layer.string) { _, new in
                if !isEditing { draftString = new }
            }
            .onChange(of: isEditing) { _, editing in
                if !editing { boxFocused = true }
            }
        }
    }

    // MARK: - Chrome

    // De selectierand is óók de delete-zone: rechtermuisknop → "Delete", en
    // ⌫/Delete-toets als hij focus heeft (na committen/selecteren, niet tijdens
    // typen). Hit-testing alleen aan in select-modus; de move-drag blijft via de
    // overlay-gesture lopen.
    private func selectionBox(_ rect: CGRect) -> some View {
        Rectangle()
            .strokeBorder(Color.accentColor, lineWidth: 1.5)
            .frame(width: rect.width + 8, height: rect.height + 8)
            .contentShape(Rectangle())
            .focusable(deleteEnabled)
            .focusEffectDisabled()
            .focused($boxFocused)
            .onDeleteCommand { removeLayer() }
            .contextMenu {
                Button(role: .destructive) { removeLayer() } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .allowsHitTesting(deleteEnabled)
            .position(x: rect.midX, y: rect.midY)
    }

    private func scaleHandle(rect: CGRect) -> some View {
        Circle()
            .fill(Color.green)
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .position(x: rect.maxX + 4, y: rect.maxY + 4)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if scaleDragStartSize == nil {
                            scaleDragStartSize = layer?.fontSize
                            scaleDragStartDistance = hypot(value.translation.width, value.translation.height)
                            layersBeforeScale = doc.layers
                        }
                        guard let startSize = scaleDragStartSize,
                              let startDist = scaleDragStartDistance,
                              startDist > 0,
                              let index = doc.layers.texts.firstIndex(where: { $0.id == layerID }) else { return }
                        let dist = hypot(value.translation.width, value.translation.height)
                        let factor = max(0.25, dist / startDist)
                        var layers = doc.layers
                        layers.texts[index].fontSize = min(240, max(10, startSize * Double(factor)))
                        doc.layers = layers
                    }
                    .onEnded { _ in
                        if let before = layersBeforeScale, before != doc.layers {
                            BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: doc.layers, actionName: "Scale text")
                        }
                        scaleDragStartSize = nil
                        scaleDragStartDistance = nil
                        layersBeforeScale = nil
                    }
            )
    }

    // MARK: - Inline editor

    private func inlineEditor(layer: BannerTextLayer, rect: CGRect) -> some View {
        let fontSize = max(12, layer.fontSize * scale)
        let nsFont = BannerFontPanelController.nsFont(from: layer)
        let color = NSColor(Color(hexRGB: layer.colorHex) ?? .white)
        // Select-all alleen voor (legacy) placeholder-tekst; lege laag wil enkel focus.
        let selectAll = isEditing && layer.string == BannerTextPresets.placeholder
        return BannerInlineTextField(
            text: $draftString,
            font: NSFont(name: nsFont.fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize),
            color: color,
            alignment: textAlignment(layer.alignRaw),
            placeholder: BannerTextPresets.placeholder,
            focusOnFirstAppear: isEditing,
            selectAllOnFirstFocus: selectAll,
            onSubmit: { commitText() },
            onDeleteWhenEmpty: removeLayer
        )
        .frame(width: max(rect.width, 120), height: max(rect.height, fontSize + 4))
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(isEditing)
        .onChange(of: draftString) { _, new in
            guard let index = doc.layers.texts.firstIndex(where: { $0.id == layerID }) else { return }
            var layers = doc.layers
            layers.texts[index].string = new
            doc.layers = layers
        }
        .onTapGesture(count: 2) { isEditing = true }
    }

    private func textAlignment(_ alignRaw: Int) -> NSTextAlignment {
        switch alignRaw {
        case 0: return .left
        case 2: return .right
        default: return .center
        }
    }

    // MARK: - Layout

    private func screenRect(for layer: BannerTextLayer) -> CGRect? {
        var canvasRect = BannerLayoutMetrics.textRect(layer: layer, canvas: canvasSize)
        if canvasRect.width < 1 {
            let fontH = layer.fontSize
            let fontW = max(120, CGFloat(layer.string.count) * layer.fontSize * 0.55)
            canvasRect = CGRect(
                x: layer.x * canvasSize.width - fontW / 2,
                y: layer.y * canvasSize.height - fontH / 2,
                width: fontW,
                height: fontH
            )
        }
        return CGRect(
            x: origin.x + canvasRect.minX * scale,
            y: origin.y + canvasRect.minY * scale,
            width: canvasRect.width * scale,
            height: canvasRect.height * scale
        )
    }

    private func commitText() {
        isEditing = false
        if BannerTextPresets.isEmptyOrPlaceholder(draftString) {
            removeLayer()
        }
    }

    private func removeLayer() {
        let before = doc.layers
        var layers = doc.layers
        layers.texts.removeAll { $0.id == layerID }
        doc.layers = layers
        BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: layers, actionName: "Delete text")
        if case .text(layerID) = selection { selection = nil }
    }
}
