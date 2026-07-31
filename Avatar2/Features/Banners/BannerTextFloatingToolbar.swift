// E37.13 — Freeform-stijl floating tekst-toolbar: kleur · Aa · grootte direct
// boven het tekstkader op het canvas (format/kleur-panelen stapelen omhoog).

import AppKit
import AvatarUI
import SwiftUI

enum BannerTextPresets {
    static let placeholder = "Type to enter text"

    /// Legacy default-literals die vóór de Freeform-chrome (d1ec4e7) als échte
    /// `layer.string` persisteerden: het oude Text-paneel (E37.4,
    /// `BannerTextPanel.addText`) zaaide "Your text". De UX-audit (UX1) zag die
    /// lagen nog als thumbnail-soep — voor filter/sweep/render tellen ze als
    /// placeholder (UXS-5).
    static let legacyPlaceholders: Set<String> = ["Your text"]

    static let fontSizes: [Double] = [10, 12, 14, 18, 24, 36, 48, 64, 72, 96, 144]

    /// Freeform-achtige swatches (wit → zwart + accenten).
    static let swatchHexes: [String] = [
        "#FFFFFF", "#AEAEB2", "#111111", "#30B0C7", "#FF6482", "#AF52DE",
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#5AC8FA", "#007AFF",
    ]

    static func isEmptyOrPlaceholder(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == placeholder || legacyPlaceholders.contains(trimmed)
    }
}

struct BannerTextFloatingToolbar: View {
    @Bindable var doc: BannerDoc
    let layerID: UUID
    var presentation: UIPresentationStore
    let undoManager: UndoManager?
    /// Bovenrand van het tekstkader in scherm-coördinaten (midden X, top Y).
    let anchorTextTop: CGPoint
    var onDelete: () -> Void
    /// Verhoog vanuit de canvas-chrome om open submenu's te sluiten (tik buiten).
    var menuDismissNonce: Int = 0
    var onMenusOpenChange: ((Bool) -> Void)?

    @State private var layersBeforeEdit: BannerLayers?
    @State private var pillHeight: CGFloat = 36

    private var colorMenuKind: BannerFloatingMenu { .textColor(layerID: layerID) }
    private var formatMenuKind: BannerFloatingMenu { .textFormat(layerID: layerID) }
    private var sizeMenuKind: BannerFloatingMenu { .textSize(layerID: layerID) }

    private var showColorMenu: Bool { presentation.bannerFloatingMenu == colorMenuKind }
    private var showFormatMenu: Bool { presentation.bannerFloatingMenu == formatMenuKind }
    private var showSizeMenu: Bool { presentation.bannerFloatingMenu == sizeMenuKind }

    private let gapAboveText: CGFloat = 10

    private var pillCenter: CGPoint {
        CGPoint(
            x: anchorTextTop.x,
            y: anchorTextTop.y - gapAboveText - pillHeight / 2
        )
    }

    private var layerIndex: Int? {
        doc.layers.texts.firstIndex(where: { $0.id == layerID })
    }

    var body: some View {
        // Pil blijft vast boven het tekstkader; panelen groeien omhoog (Freeform).
        pillRow
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ToolbarPillHeightKey.self, value: geo.size.height)
                }
            )
            .overlay(alignment: .top) {
                VStack(spacing: DSSpacing.gap2) {
                    if showFormatMenu {
                        formatMenu
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if showColorMenu {
                        colorMenu
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .fixedSize()
                .alignmentGuide(.top) { d in d[.bottom] + DSSpacing.gap2 }
            }
            .onPreferenceChange(ToolbarPillHeightKey.self) { pillHeight = $0 }
            .position(pillCenter)
            .dsMotion(DSMotion.fast, value: showFormatMenu)
            .dsMotion(DSMotion.fast, value: showColorMenu)
            .dsMotion(DSMotion.fast, value: presentation.bannerFloatingMenu)
            .onDisappear {
                BannerFontPanelController.shared.dismiss()
                BannerColorPanelController.shared.dismiss()
            }
            .onChange(of: menuDismissNonce) { _, _ in closeSubmenus() }
            .onChange(of: presentation.bannerFloatingMenu) { _, _ in reportMenusOpen() }
    }

    private var anySubmenuOpen: Bool {
        showColorMenu || showFormatMenu || showSizeMenu
    }

    private func closeSubmenus() {
        switch presentation.bannerFloatingMenu {
        case .textColor(layerID), .textFormat(layerID), .textSize(layerID):
            presentation.bannerFloatingMenu = nil
        default:
            break
        }
    }

    private func toggleMenu(_ kind: BannerFloatingMenu) {
        presentation.bannerFloatingMenu = presentation.bannerFloatingMenu == kind ? nil : kind
    }

    private func closeMenu(_ kind: BannerFloatingMenu) {
        if presentation.bannerFloatingMenu == kind { presentation.bannerFloatingMenu = nil }
    }

    private func menuBinding(_ kind: BannerFloatingMenu) -> Binding<Bool> {
        Binding(
            get: { presentation.bannerFloatingMenu == kind },
            set: { presentation.bannerFloatingMenu = $0 ? kind : nil }
        )
    }

    private func reportMenusOpen() {
        onMenusOpenChange?(anySubmenuOpen)
    }

    /// Compacte pil: kleur · Aa · grootte — altijd direct boven het tekstkader.
    private var pillRow: some View {
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
                .dsShadow(.card)
        )
    }

    // MARK: - Controls

    private var colorButton: some View {
        let hex = doc.layers.texts.first(where: { $0.id == layerID })?.colorHex ?? "#FFFFFF"
        let color = Color(hexRGB: hex) ?? .white
        return Button {
            toggleMenu(colorMenuKind)
        } label: {
            Circle()
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        // Kleur-paneel zit in de VStack boven de pil (Freeform-stijl).
    }

    private var formatButton: some View {
        Button {
            toggleMenu(formatMenuKind)
        } label: {
            // UXS-20: DS-tekststijl i.p.v. een los puntgetal uit de schaduwschaal.
            Text("Aa")
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)
                .frame(minWidth: 28)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { openFontPanel() })
        // Format-paneel zit in de VStack boven de pil (Freeform-stijl).
    }

    private func openFontPanel() {
        closeMenu(formatMenuKind)
        guard let index = layerIndex else { return }
        let layer = doc.layers.texts[index]
        BannerFontPanelController.shared.show(layer: layer) { font in
            mutateLayer { BannerFontPanelController.applyFont(font, to: &$0) }
        }
    }

    private var sizeButton: some View {
        let size = Int(doc.layers.texts.first(where: { $0.id == layerID })?.fontSize ?? 50)
        return Button {
            toggleMenu(sizeMenuKind)
        } label: {
            HStack(spacing: 4) {
                Text("\(size)")
                    .dsTextStyle(.labelBase)
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(DSColor.Foreground.primary)
        }
        .buttonStyle(.plain)
        .dsDropdownMenu(isPresented: menuBinding(sizeMenuKind), anchorHeight: 28, placement: .below) {
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
            HoverFill(active: false, activeFill: .clear, baseFill: DSColor.Background.neutral, cornerRadius: DSRadius.md) {
                closeMenu(colorMenuKind)
                BannerColorPanelController.shared.show(hex: currentHex) { color in
                    guard let hex = Color(nsColor: color).hexRGB else { return }
                    mutateLayer { $0.colorHex = hex }
                }
            } label: {
                Text("More Text Colors")
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DSSpacing.gap2)
            }
        }
        .padding(DSSpacing.gap3)
        .frame(width: 220)
        .dsPanelSurface(cornerRadius: DSRadius.lg, solid: true)
        .dsDropdownDismissOverlay(isPresented: menuBinding(colorMenuKind))
    }

    private var formatMenu: some View {
        VStack(spacing: DSSpacing.gap2) {
            HStack(spacing: DSSpacing.gap2) {
                styleSegmented
                fontsChip
            }
            HStack(spacing: DSSpacing.gap2) {
                alignChip(0, icon: "text.alignleft")
                alignChip(1, icon: "text.aligncenter")
                alignChip(2, icon: "text.alignright")
            }

            Divider().padding(.vertical, 2)

            HoverRow {
                closeMenu(formatMenuKind)
                onDelete()
            } label: {
                Text("Delete Text")
                    .dsTextStyle(.labelBase)
                    // UXS-23: één destructive-taal — DSMenuRow gebruikt hetzelfde
                    // token, dus systeemrood hoort hier niet meer.
                    .foregroundStyle(DSColor.Foreground.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DSSpacing.gap2)
                    .padding(.vertical, DSSpacing.gap1)
            }
        }
        .padding(DSSpacing.gap2)
        .frame(width: 248)
        .dsPanelSurface(cornerRadius: DSRadius.lg, solid: true)
        .dsDropdownDismissOverlay(isPresented: menuBinding(formatMenuKind))
    }

    /// Gesegmenteerde B | I | U met hairline-scheidingen (één grijze pil, actieve
    /// cel als witte kaart) — zoals Freeform.
    private var styleSegmented: some View {
        HStack(spacing: 0) {
            segmentCell("B", weight: .bold, italic: false, underline: false, active: isBold) { toggleBold() }
            segmentDivider
            segmentCell("I", weight: .regular, italic: true, underline: false, active: isItalic) { toggleItalic() }
            segmentDivider
            segmentCell("U", weight: .regular, italic: false, underline: true, active: isUnderline) { toggleUnderline() }
        }
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous).fill(DSColor.Background.neutral))
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
    }

    private var segmentDivider: some View {
        Rectangle().fill(DSColor.Foreground.primary.opacity(0.08)).frame(width: 1, height: 22)
    }

    private func segmentCell(
        _ title: String,
        weight: Font.Weight,
        italic: Bool,
        underline: Bool,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        // De B/I/U-knoppen dragen hun eigen gewicht (bold/regular), dus hier
        // blijft `.system` met het DS-puntformaat i.p.v. een vaste stijl.
        var text = Text(title).font(.system(size: DSTypography.FontSize.sm, weight: weight))
        if italic { text = text.italic() }
        if underline { text = text.underline() }
        return HoverFill(active: active, activeFill: DSColor.Background.card, cornerRadius: DSRadius.sm) {
            action()
        } label: {
            text
                .foregroundStyle(DSColor.Foreground.primary)
                .frame(width: 44, height: 36)
        }
        .padding(2)
    }

    private var fontsChip: some View {
        HoverFill(active: false, activeFill: .clear, baseFill: DSColor.Background.neutral, cornerRadius: DSRadius.md) {
            closeMenu(formatMenuKind)
            openFontPanel()
        } label: {
            VStack(spacing: 0) {
                Text("Fonts")
                    .dsTextStyle(.labelSmall)
                Text("…")
                    .dsTextStyle(.labelSmall)
            }
            .foregroundStyle(DSColor.Foreground.primary)
            .frame(width: 64, height: 40)
        }
    }

    private var sizeMenu: some View {
        let current = doc.layers.texts.first(where: { $0.id == layerID })?.fontSize ?? 50
        // Scrollbaar + begrensd: de toolbar zweeft bovenaan de tekst en het menu
        // opent omlaag — een volle, ongelimiteerde lijst liep onder de zwevende
        // onderbalk door waardoor de grootste maten niet aanklikbaar waren.
        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(BannerTextPresets.fontSizes, id: \.self) { size in
                    HoverRow {
                        mutateLayer { $0.fontSize = size }
                        closeMenu(sizeMenuKind)
                    } label: {
                        HStack {
                            Text("\(Int(size))")
                                .dsTextStyle(.labelBase)
                                .foregroundStyle(DSColor.Foreground.primary)
                            Spacer()
                            if Int(current) == Int(size) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(DSColor.Foreground.muted)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, DSSpacing.gap3)
                        .padding(.vertical, DSSpacing.gap2)
                    }
                }
            }
            .padding(.vertical, DSSpacing.gap1)
        }
        .frame(width: 132, height: 220)
        .dsPanelSurface(cornerRadius: DSRadius.lg, solid: true)
        .dsDropdownDismissOverlay(isPresented: menuBinding(sizeMenuKind))
    }

    // MARK: - Helpers

    private var currentHex: String {
        doc.layers.texts.first(where: { $0.id == layerID })?.colorHex ?? "#FFFFFF"
    }

    private var isBold: Bool {
        (doc.layers.texts.first(where: { $0.id == layerID })?.weightRaw ?? 0) >= 3
    }

    private var isItalic: Bool {
        doc.layers.texts.first(where: { $0.id == layerID })?.italic == true
    }

    private var isUnderline: Bool {
        doc.layers.texts.first(where: { $0.id == layerID })?.underline == true
    }

    private var currentAlign: Int {
        doc.layers.texts.first(where: { $0.id == layerID })?.alignRaw ?? 1
    }

    private func swatchButton(hex: String) -> some View {
        let selected = currentHex.caseInsensitiveCompare(hex) == .orderedSame
        return Button {
            mutateLayer { $0.colorHex = hex }
            closeMenu(colorMenuKind)
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

    private func alignChip(_ align: Int, icon: String) -> some View {
        let selected = currentAlign == align
        return HoverFill(
            active: selected,
            activeFill: DSColor.Action.primary,
            baseFill: DSColor.Background.neutral,
            cornerRadius: DSRadius.md
        ) {
            mutateLayer { $0.alignRaw = align }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? DSColor.Action.primaryForeground : DSColor.Foreground.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
    }

    private func toggleBold() {
        mutateLayer { layer in
            layer.weightRaw = layer.weightRaw >= 3 ? 0 : 3
        }
    }

    private func toggleItalic() {
        mutateLayer { $0.italic = !($0.italic ?? false) }
    }

    private func toggleUnderline() {
        mutateLayer { $0.underline = !($0.underline ?? false) }
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

private struct ToolbarPillHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 36
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Knop met een afgeronde vulling die op hover lichtjes oplicht (en een actieve
/// staat). Basis voor de B|I|U-cellen, uitlijnknoppen en Fonts-chip.
private struct HoverFill<Label: View>: View {
    var active: Bool
    var activeFill: Color
    var baseFill: Color = .clear
    var cornerRadius: CGFloat
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(active ? activeFill : baseFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(Color.primary.opacity(hovering && !active ? 0.06 : 0))
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Een volledige-breedte menurij met hover-achtergrond (lijstitems).
private struct HoverRow<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.06 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
