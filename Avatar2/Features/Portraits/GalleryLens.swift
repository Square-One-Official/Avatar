// Gallery-lens voor de Portraits-surface (Finder-stijl): één grote preview boven
// + een horizontale filmstrip onder. Klik een filmstrip-thumb = focus (preview
// wisselt); ⌘/⇧-klik = multi-select; klik de grote preview = openen in de editor.
// ←/→ (of de pijl-knoppen op de preview) bladeren CYCLISCH door de set; de
// filmstrip volgt mee. Rechtermuis = enkel/bulk-menu. Selectie leest mee met
// `model.selectedPortraitIDs`.

import AppKit
import AvatarUI
import SwiftData
import SwiftUI

struct GalleryLens: View {
    let items: [Portrait2]
    let model: ShellModel
    let folders: [Folder2]

    @State private var focusID: PersistentIdentifier?
    @State private var menuTarget: Portrait2?
    @State private var menuAnchor: CGRect = .zero

    private var focused: Portrait2? {
        items.first { $0.persistentModelID == focusID } ?? items.first
    }

    private var focusedIndex: Int {
        items.firstIndex { $0.persistentModelID == focused?.persistentModelID } ?? 0
    }

    /// Cyclisch bladeren (−1 = vorige, +1 = volgende).
    private func cycle(_ delta: Int) {
        guard items.count > 1 else { return }
        let next = (focusedIndex + delta + items.count) % items.count
        focusID = items[next].persistentModelID
    }

    var body: some View {
        VStack(spacing: 0) {
            if let f = focused { preview(f) } else { Spacer() }
            filmstrip
        }
        .coordinateSpace(name: PortraitContextMenuSpace.name)
        .portraitContextMenuOverlay(
            target: $menuTarget,
            anchor: menuAnchor,
            model: model,
            folders: folders,
            selectedTargets: { items.filter { model.isPortraitSelected($0) } }
        )
        // ←/→ bladeren door de gallery (cyclisch). Onzichtbare knoppen — alleen
        // actief zolang de gallery-lens zichtbaar is.
        .background {
            Button("") { cycle(-1) }.keyboardShortcut(.leftArrow, modifiers: []).opacity(0)
            Button("") { cycle(1) }.keyboardShortcut(.rightArrow, modifiers: []).opacity(0)
        }
    }

    // MARK: - Grote preview

    private func preview(_ p: Portrait2) -> some View {
        VStack(spacing: DSSpacing.gap3) {
            PortraitComposite(portrait: p, maxDimension: 1200)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl3, style: .continuous))
                .frame(maxWidth: 520)
            VStack(spacing: 2) {
                Text(p.name.isEmpty ? "Untitled" : p.name)
                    .dsTextStyle(.h4).foregroundStyle(DSColor.Foreground.primary)
                if !p.role.isEmpty {
                    Text(p.role).dsTextStyle(.labelSmall).foregroundStyle(DSColor.Foreground.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DSSpacing.gap6)
        .contentShape(Rectangle())
        .onTapGesture { model.openPortrait(p) }
        .help("Click to open · ← / → to browse")
        // Blader-pijlen links/rechts (cyclisch). De knoppen vangen hun eigen klik,
        // dus ze openen het portret niet.
        .overlay(alignment: .leading) { navArrow("chevron.left") { cycle(-1) } }
        .overlay(alignment: .trailing) { navArrow("chevron.right") { cycle(1) } }
        .portraitContextMenuTrigger(portrait: p, model: model, target: $menuTarget, anchor: $menuAnchor)
    }

    private func navArrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DSColor.Foreground.primary)
                .frame(width: 40, height: 40)
                .background(DSColor.Background.card, in: Circle())
                .overlay(Circle().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(DSSpacing.gap5)
        .opacity(items.count > 1 ? 1 : 0)
        .allowsHitTesting(items.count > 1)
    }

    // MARK: - Filmstrip

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.gap3) {
                    ForEach(items) { p in
                        filmThumb(p).id(p.persistentModelID)
                    }
                }
                .padding(.horizontal, DSSpacing.gap6)
                .padding(.vertical, DSSpacing.gap4)
            }
            .frame(height: 116)
            .background(DSColor.Background.card)
            .overlay(alignment: .top) {
                Rectangle().fill(DSColor.Foreground.divider).frame(height: DSBorderWidth.thin)
            }
            // De filmstrip volgt de focus (klik of ←/→) en centreert 'm.
            .onChange(of: focusID) { _, id in
                guard let id else { return }
                withAnimation(.spring(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func filmThumb(_ p: Portrait2) -> some View {
        let isFocus = p.persistentModelID == focused?.persistentModelID
        let isSel = model.isPortraitSelected(p)
        return PortraitComposite(portrait: p, maxDimension: 200)
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous)
                    .strokeBorder(
                        (isFocus || isSel) ? DSColor.Action.primary : DSColor.Foreground.divider,
                        lineWidth: (isFocus || isSel) ? DSBorderWidth.medium : DSBorderWidth.thin
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isSel {
                    DSSelectionCheckBadge(size: 15)
                        .padding(3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                let mods = NSApp.currentEvent?.modifierFlags ?? []
                if mods.contains(.command) || mods.contains(.shift) {
                    model.handlePortraitClick(p, ordered: items.map(\.persistentModelID), mods: mods)
                } else {
                    focusID = p.persistentModelID
                }
            }
            .dsMotion(DSMotion.micro, value: isFocus)
            .portraitContextMenuTrigger(portrait: p, model: model, target: $menuTarget, anchor: $menuAnchor)
    }
}
