// E37.13 — Freeform-stijl floating tekst-toolbar: kleur · Aa · grootte direct
// onder de selectie op het canvas (geen zware onderste panelen).

import AppKit
import AvatarUI
import SwiftUI

enum BannerTextPresets {
    static let placeholder = "Type to enter text"

    static let fontSizes: [Double] = [10, 12, 14, 18, 24, 36, 48, 64, 72, 96, 144]

    /// Freeform-achtige swatches (wit → zwart + accenten).
    static let swatchHexes: [String] = [
        "#FFFFFF", "#AEAEB2", "#111111", "#30B0C7", "#FF6482", "#AF52DE",
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#5AC8FA", "#007AFF",
    ]

    static func isEmptyOrPlaceholder(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == placeholder
    }
}

struct BannerTextFloatingToolbar: View {
    @Bindable var doc: BannerDoc
    let layerID: UUID
    let undoManager: UndoManager?
    var onDelete: () -> Void

    @State private var showColorMenu = false
    @State private var showFormatMenu = false
    @State private var showSizeMenu = false
    @State private var layersBeforeEdit: BannerLayers?

    private var layerIndex: Int? {
        doc.layers.texts.firstIndex(where: { $0.id == layerID })
    }

    var body: some View {
        HStack(spacing: DSSpacing.gap3) {
            colorButton
            formatButton
            sizeButton
        }
        .padding(.horizontal, DSSpacing.gap3)
        .padding(.vertical, DSSpacing.gap2)
        .background(
            Capsule(style: .continuous)
                .fill(DSColor.Background.card)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        )
        .onDisappear {
            BannerFontPanelController.shared.dismiss()
            BannerColorPanelController.shared.dismiss()
        }
    }

    // MARK: - Controls

    private var colorButton: some View {
        let hex = doc.layers.texts.first(where: { $0.id == layerID })?.colorHex ?? "#FFFFFF"
        let color = Color(hexRGB: hex) ?? .white
        return Button {
            showFormatMenu = false
            showSizeMenu = false
            showColorMenu.toggle()
        } label: {
            Circle()
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .dsDropdownMenu(isPresented: $showColorMenu, anchorHeight: 22) {
            colorMenu
        }
    }

    private var formatButton: some View {
        Button {
            showColorMenu = false
            showSizeMenu = false
            showFormatMenu.toggle()
        } label: {
            Text("Aa")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DSColor.Foreground.primary)
                .frame(minWidth: 28)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { openFontPanel() })
        .dsDropdownMenu(isPresented: $showFormatMenu, anchorHeight: 28) {
            formatMenu
        }
    }

    private func openFontPanel() {
        showFormatMenu = false
        guard let index = layerIndex else { return }
        let layer = doc.layers.texts[index]
        BannerFontPanelController.shared.show(layer: layer) { font in
            mutateLayer { BannerFontPanelController.applyFont(font, to: &$0) }
        }
    }

    private var sizeButton: some View {
        let size = Int(doc.layers.texts.first(where: { $0.id == layerID })?.fontSize ?? 50)
        return Button {
            showColorMenu = false
            showFormatMenu = false
            showSizeMenu.toggle()
        } label: {
            HStack(spacing: 4) {
                Text("\(size)")
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(DSColor.Foreground.primary)
        }
        .buttonStyle(.plain)
        .dsDropdownMenu(isPresented: $showSizeMenu, anchorHeight: 28) {
            sizeMenu
        }
    }

    // MARK: - Menus

    private var colorMenu: some View {
        VStack(spacing: DSSpacing.gap2) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 6), spacing: 8) {
                ForEach(BannerTextPresets.swatchHexes, id: \.self) { hex in
                    swatchButton(hex: hex)
                }
            }
            Button("More Text Colours") {
                showColorMenu = false
                BannerColorPanelController.shared.show(hex: currentHex) { color in
                    guard let hex = Color(nsColor: color).hexRGB else { return }
                    mutateLayer { $0.colorHex = hex }
                }
            }
            .buttonStyle(.plain)
            .dsTextStyle(.labelSmall)
            .foregroundStyle(DSColor.Foreground.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.gap2)
            .background(DSColor.Background.neutral, in: RoundedRectangle(cornerRadius: DSRadius.md))
        }
        .padding(DSSpacing.gap3)
        .frame(width: 220)
        .dsPanelSurface(cornerRadius: DSRadius.lg, solid: true)
        .dsDropdownDismissOverlay(isPresented: $showColorMenu)
    }

    private var formatMenu: some View {
        VStack(spacing: DSSpacing.gap2) {
            HStack(spacing: DSSpacing.gap1) {
                formatChip("B", selected: isBold) { toggleBold() }
                formatChip("I", selected: false) { } // italic — model heeft geen italic; visuele stub
                    .opacity(0.35)
                    .disabled(true)
                formatChip("U", selected: false) { }
                    .opacity(0.35)
                    .disabled(true)
                Button {
                    showFormatMenu = false
                    openFontPanel()
                } label: {
                    formatChipLabel("Fonts…", selected: false)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: DSSpacing.gap1) {
                alignChip(0, icon: "text.alignleft")
                alignChip(1, icon: "text.aligncenter")
                alignChip(2, icon: "text.alignright")
            }

            Divider()

            Button("Delete Text") {
                showFormatMenu = false
                onDelete()
            }
            .buttonStyle(.plain)
            .dsTextStyle(.labelBase)
            .foregroundStyle(Color.red)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DSSpacing.gap2)
        .dsPanelSurface(cornerRadius: DSRadius.lg, solid: true)
        .dsDropdownDismissOverlay(isPresented: $showFormatMenu)
    }

    private var sizeMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            let current = doc.layers.texts.first(where: { $0.id == layerID })?.fontSize ?? 50
            Button {
                showSizeMenu = false
            } label: {
                HStack {
                    Text("\(Int(current))")
                    Spacer()
                    Image(systemName: "checkmark")
                }
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)
                .padding(.horizontal, DSSpacing.gap3)
                .padding(.vertical, DSSpacing.gap2)
            }
            .buttonStyle(.plain)

            Divider().padding(.horizontal, DSSpacing.gap2)

            ForEach(BannerTextPresets.fontSizes, id: \.self) { size in
                Button {
                    mutateLayer { $0.fontSize = size }
                    showSizeMenu = false
                } label: {
                    Text("\(Int(size))")
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DSSpacing.gap3)
                        .padding(.vertical, DSSpacing.gap1)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 120)
        .padding(.vertical, DSSpacing.gap2)
        .dsPanelSurface(cornerRadius: DSRadius.lg, solid: true)
        .dsDropdownDismissOverlay(isPresented: $showSizeMenu)
    }

    // MARK: - Helpers

    private var currentHex: String {
        doc.layers.texts.first(where: { $0.id == layerID })?.colorHex ?? "#FFFFFF"
    }

    private var isBold: Bool {
        (doc.layers.texts.first(where: { $0.id == layerID })?.weightRaw ?? 0) >= 3
    }

    private var currentAlign: Int {
        doc.layers.texts.first(where: { $0.id == layerID })?.alignRaw ?? 1
    }

    private func swatchButton(hex: String) -> some View {
        let selected = currentHex.caseInsensitiveCompare(hex) == .orderedSame
        return Button {
            mutateLayer { $0.colorHex = hex }
            showColorMenu = false
        } label: {
            Circle()
                .fill(Color(hexRGB: hex) ?? .white)
                .frame(width: 28, height: 28)
                .overlay {
                    if selected {
                        Circle().strokeBorder(Color.primary, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func formatChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            formatChipLabel(title, selected: selected)
        }
        .buttonStyle(.plain)
    }

    private func formatChipLabel(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 14, weight: title == "B" ? .bold : .regular))
            .foregroundStyle(selected ? DSColor.Action.primaryForeground : DSColor.Foreground.primary)
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                    .fill(selected ? DSColor.Action.primary : DSColor.Background.neutral)
            )
    }

    private func alignChip(_ align: Int, icon: String) -> some View {
        let selected = currentAlign == align
        return Button {
            mutateLayer { $0.alignRaw = align }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? DSColor.Action.primaryForeground : DSColor.Foreground.primary)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                        .fill(selected ? DSColor.Action.primary : DSColor.Background.neutral)
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleBold() {
        mutateLayer { layer in
            layer.weightRaw = layer.weightRaw >= 3 ? 0 : 3
        }
    }

    private func mutateLayer(_ edit: (inout BannerTextLayer) -> Void) {
        guard let index = layerIndex else { return }
        let before = doc.layers
        var layers = doc.layers
        edit(&layers.texts[index])
        doc.layers = layers
        BannerDocUndo.registerLayers(undoManager, doc: doc, from: before, to: layers, actionName: "Text")
    }
}
