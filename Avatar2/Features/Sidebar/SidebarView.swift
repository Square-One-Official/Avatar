// Sidebar/set (E05.4 + E04.5-fix bevinding 8, Figma: App / Sidebar images
// 4011:4986, paneel "Siri AI" 248 breed). Losstaande afgeronde kaart
// (bg Card, r-4xl continuous — zelfde kaarttaal als DSEditPanel; ShellView
// geeft de marge rondom) met DSSearchField (capsule h48, E03.10) bovenin,
// DSSidebarRow-slots (thumb 48, continuous corners; selectie = afgeronde
// Inset-highlight) en de DSAddButton (sidebar-add-besluit 10 jun).
// Thumbnails in Figma zijn placeholderfoto's; wij renderen de cutouts.

import AppKit
import AvatarKit
import AvatarUI
import SwiftData
import SwiftUI

struct SidebarView: View {
    /// Marge t.o.v. de vensterrand — ShellView gebruikt dezelfde waarde
    /// als padding, de kaartradius rekent er concentrisch mee.
    static let edgeInset: CGFloat = ShellMetrics.windowEdgeInset

    // Laatst bewerkt bovenaan, zoals v1 (punt 13).
    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var portraits: [Portrait2]
    // PoC (left-nav): mappen voor het folder-filter + "Move to folder".
    @Query(sort: \Folder2.createdAt, order: .forward) private var folders: [Folder2]
    @State private var searchText = ""
    /// PoC (left-nav): filter de (volledige) lijst op map. nil-sentinels via enum.
    @State private var folderFilter: FolderFilter = .all

    enum FolderFilter: Hashable { case all, unfiled, folder(PersistentIdentifier) }

    let selectedID: PersistentIdentifier?
    let onSelect: (Portrait2) -> Void
    let onAdd: () -> Void
    /// E19.2: export het portret via de shell (selecteert + opent de popup).
    var onExport: (Portrait2) -> Void = { _ in }
    /// E19.5: set-brede voortgang (Align/Match lighting) → shell-toast.
    var onSetBusy: (String?) -> Void = { _ in }
    /// E19.4: watermerk-bepaling voor bulk-export (free = watermerk).
    var isPro: Bool = false

    @Environment(\.undoManager) private var undoManager
    @Environment(\.modelContext) private var modelContext
    /// E19.2/19.3: context-menu-acties.
    @State private var renameTarget: Portrait2?
    @State private var deleteTarget: Portrait2?
    /// E24.22: portret waarvoor het DS-rechtermuis-menu open is.
    @State private var menuTarget: Portrait2?
    /// E19.4: multi-select voor bulk-export (cmd/shift-klik), los van de
    /// canvas-selectie. lastClickedID = ankerpunt voor shift-bereik.
    @State private var selectedForBulk: Set<PersistentIdentifier> = []
    @State private var lastClickedID: PersistentIdentifier?
    /// E05.7: loopt tijdens een set-brede align (knop disabled + pulse).
    @State private var isAligning = false
    /// E12.2: loopt tijdens de set-brede lichtnormalisatie.
    @State private var isMatchingLight = false
    /// E27.6: de gedeelde off-main thumbnail-store (zelfde type als de board, eigen
    /// instance). Decodeert + downscalet elke rij-thumb op een achtergrond-Task →
    /// geen full-res-decode op de main-thread meer bij hover/scroll (de reden dat
    /// de oude `SidebarThumbnailCache` bestond), en (id, updatedAt)-gekeyd zodat een
    /// bewerkt portret vanzelf ververst.
    @State private var thumbs = ThumbnailStore()

    private var filtered: [Portrait2] {
        // PoC (left-nav): eerst op map filteren, dan op zoektekst.
        var base = portraits
        switch folderFilter {
        case .all: break
        case .unfiled: base = base.filter { $0.folder == nil }
        case .folder(let id): base = base.filter { $0.folder?.persistentModelID == id }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.role.localizedCaseInsensitiveContains(query)
        }
    }

    /// Label voor de folder-filter-knop.
    private var folderFilterLabel: String {
        switch folderFilter {
        case .all: return "All images"
        case .unfiled: return "Unfiled"
        case .folder(let id): return folders.first { $0.persistentModelID == id }?.name ?? "Folder"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // PoC (left-nav): map-filter — de set-sidebar toont nu álle beelden,
            // optioneel gefilterd op map.
            folderFilterMenu
                .padding(.horizontal, DSSpacing.gap4)
                .padding(.top, DSSpacing.gap4)
            DSSearchField(text: $searchText)
                .padding(.horizontal, DSSpacing.gap4)
                .padding(.top, DSSpacing.gap2)
                .padding(.bottom, DSSpacing.gap4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { portrait in
                        DSSidebarRow(
                            name: portrait.name.isEmpty ? "Name" : portrait.name,
                            role: portrait.role.isEmpty ? "Role" : portrait.role,
                            isSelected: portrait.persistentModelID == selectedID && selectedForBulk.isEmpty,
                            isMultiSelected: selectedForBulk.contains(portrait.persistentModelID),
                            action: { handleRowClick(portrait) },
                            avatar: { thumbnail(for: portrait) }
                        )
                        // E24.22: rechtermuis → ons DS-menu (i.p.v. native
                        // `.contextMenu`). Positie via anchor-preference (zie de
                        // overlay onderaan de lijst).
                        .onRightClick { menuTarget = portrait }
                        .anchorPreference(key: RowAnchorKey.self, value: .bounds) {
                            [portrait.persistentModelID: $0]
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.gap4)
                .padding(.top, DSSpacing.gap4)
            }

            VStack(spacing: DSSpacing.gap2) {
                // E05.7: de kern-merkbelofte als één knop — prominent
                // (brand) maar rustig; alleen zinvol bij een set (≥2).
                if portraits.count >= 2 {
                    DSPrimaryButton(
                        isAligning ? "Aligning…" : "Align set",
                        icon: Image(systemName: "wand.and.stars"),
                        fullWidth: true
                    ) {
                        alignSet()
                    }
                    .disabled(isAligning)
                    // E12.2: set-brede lichtnormalisatie naar het geselecteerde
                    // portret als referentie. Secundair t.o.v. "Align set".
                    DSNeutralButton(
                        isMatchingLight ? "Matching lighting…" : "Match lighting",
                        icon: Image(systemName: "sun.max"),
                        fullWidth: true
                    ) {
                        matchLighting()
                    }
                    .disabled(isMatchingLight)
                }
                DSAddButton("Add portrait") {
                    onAdd()
                }
            }
            .padding(DSSpacing.gap4)
        }
        .frame(width: 248)
        .frame(maxHeight: .infinity)
        #if DEBUG
        // E24.22/19.4 smoke-haken: forceer het DS-menu / een bulk-selectie.
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--seed-bulk") {
                selectedForBulk = Set(filtered.prefix(3).map(\.persistentModelID))
                lastClickedID = filtered.first?.persistentModelID
            }
            if args.contains("--show-sidebar-menu") {
                menuTarget = filtered.first
            }
        }
        #endif
        // E24.22: DS-rechtermuis-menu — gepositioneerd onder de aangeklikte rij
        // (anchor-preference). Een transparante scrim eronder sluit bij een klik
        // buiten het menu.
        .overlayPreferenceValue(RowAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let target = menuTarget, let anchor = anchors[target.persistentModelID] {
                    let rect = proxy[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { menuTarget = nil }
                        rowContextMenu(for: target)
                            .fixedSize()
                            .offset(
                                x: min(rect.minX + DSSpacing.gap2, proxy.size.width - 182),
                                y: rect.maxY - 4
                            )
                    }
                }
            }
        }
        // Concentrisch met de vensterrand (E03.15, bevinding 17):
        // binnenradius = vensterradius − marge; ShellView zet de kaart op
        // dezelfde `edgeInset`.
        .background(
            DSColor.Background.card,
            in: .rect(
                cornerRadius: DSRadius.concentric(inset: Self.edgeInset),
                style: .continuous
            )
        )
        // E19.3: rename-modal.
        .sheet(isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            if let target = renameTarget { RenameSheet(portrait: target) }
        }
        // E19.2: delete met bevestiging.
        .confirmationDialog(
            "Delete this portrait?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget { modelContext.delete(target) }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: - PoC (left-nav) map-filter

    private var folderFilterMenu: some View {
        Menu {
            Button { folderFilter = .all } label: { Label("All images", systemImage: "square.grid.2x2") }
            Button { folderFilter = .unfiled } label: { Label("Unfiled", systemImage: "tray") }
            if !folders.isEmpty { Divider() }
            ForEach(folders) { folder in
                Button { folderFilter = .folder(folder.persistentModelID) } label: { Text(folder.name) }
            }
        } label: {
            HStack(spacing: DSSpacing.gap2) {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DSColor.Foreground.muted)
                Text(folderFilterLabel)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            .padding(.horizontal, DSSpacing.gap3)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.Background.inset, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    // MARK: - E24.22 DS-rechtermuis-menu

    private func rowContextMenu(for portrait: Portrait2) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            // E19.4: bulk-export wanneer ≥2 portretten geselecteerd zijn.
            if selectedForBulk.count >= 2 {
                menuRow("Export \(selectedForBulk.count) portraits…", icon: "square.and.arrow.up.on.square") {
                    menuTarget = nil; bulkExport()
                }
                Divider().padding(.vertical, 2)
            }
            menuRow("Rename", icon: "pencil") { menuTarget = nil; renameTarget = portrait }
            moveToFolderMenu(for: portrait)
            menuRow("Export…", icon: "square.and.arrow.up") { menuTarget = nil; onExport(portrait) }
            Divider().padding(.vertical, 2)
            menuRow("Delete", icon: "trash", destructive: true) { menuTarget = nil; deleteTarget = portrait }
        }
        .padding(DSSpacing.gap1)
        .frame(width: 190)
        .dsPanelSurface(cornerRadius: DSRadius.lg)
    }

    /// PoC (left-nav): submenu "Move to folder" — verplaatst het portret naar
    /// Unfiled, een bestaande map, of een nieuw aangemaakte map.
    private func moveToFolderMenu(for portrait: Portrait2) -> some View {
        Menu {
            Button("Unfiled") { menuTarget = nil; portrait.folder = nil }
            if !folders.isEmpty { Divider() }
            ForEach(folders) { folder in
                Button(folder.name) { menuTarget = nil; portrait.folder = folder }
            }
            Divider()
            Button("New folder…") {
                menuTarget = nil
                let f = Folder2(name: "Untitled folder \(folders.count + 1)", order: folders.count + 1)
                modelContext.insert(f)
                portrait.folder = f
            }
        } label: {
            HStack(spacing: DSSpacing.gap2) {
                Image(systemName: "folder").font(.system(size: 12, weight: .medium)).frame(width: 16)
                Text("Move to folder").dsTextStyle(.labelBase)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            .foregroundStyle(DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .dsHoverHighlight(cornerRadius: DSRadius.md)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    /// E19.4: klik-afhandeling met cmd/shift voor multi-select; gewone klik =
    /// canvas-selectie (en wist de bulk-selectie).
    private func handleRowClick(_ portrait: Portrait2) {
        menuTarget = nil
        let mods = NSApp.currentEvent?.modifierFlags ?? []
        let id = portrait.persistentModelID
        if mods.contains(.command) {
            if selectedForBulk.contains(id) { selectedForBulk.remove(id) } else { selectedForBulk.insert(id) }
            lastClickedID = id
        } else if mods.contains(.shift), let last = lastClickedID,
                  let from = filtered.firstIndex(where: { $0.persistentModelID == last }),
                  let to = filtered.firstIndex(where: { $0.persistentModelID == id }) {
            for p in filtered[min(from, to)...max(from, to)] { selectedForBulk.insert(p.persistentModelID) }
        } else {
            selectedForBulk.removeAll()
            lastClickedID = id
            onSelect(portrait)
        }
    }

    /// E19.4: exporteer alle geselecteerde portretten naar een gekozen map.
    private func bulkExport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose a folder to export the selected portraits"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let targets = portraits.filter { selectedForBulk.contains($0.persistentModelID) }
        guard !targets.isEmpty else { return }
        onSetBusy("Exporting \(targets.count) portraits…")
        Task { @MainActor in
            for (i, p) in targets.enumerated() {
                guard let data = PortraitExporter.makePNG(for: p, watermark: !isPro, shape: p.frameShape) else { continue }
                let base = p.name.trimmingCharacters(in: .whitespaces)
                let name = (base.isEmpty ? "portrait-\(i + 1)" : base.replacingOccurrences(of: "/", with: "-")) + ".png"
                try? data.write(to: dir.appendingPathComponent(name))
            }
            onSetBusy(nil)
            selectedForBulk.removeAll()
        }
    }

    private func menuRow(_ title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap2) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium)).frame(width: 16)
                Text(title).dsTextStyle(.labelBase)
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? DSColor.Signal.error : DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .dsHoverHighlight(cornerRadius: DSRadius.md)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func thumbnail(for portrait: Portrait2) -> some View {
        // E19.6/E27.6: gedownscalede thumb (96px = 2× de 48pt-slot) uit de gedeelde
        // off-main store i.p.v. een full-res decode per render. `adjusted: false` =
        // de rauwe cutout, zoals de sidebar 'm altijd toonde. Mist (nog aan het
        // decoderen) → de placeholder hieronder.
        if let image = thumbs.thumbnail(for: portrait, maxDimension: 96, adjusted: false) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                // Previewanimatie (E05.7): korte puls tijdens het alignen.
                .scaleEffect(isAligning ? 0.9 : 1)
                .animation(.spring(duration: 0.4), value: isAligning)
        } else {
            DSColor.Background.inset
        }
    }

    /// E05.7: past het auto-frame-profiel (E06.5) toe op álle portretten,
    /// als één set-brede undo-stap. Detectie draait off-main; het schrijven
    /// + de undo-registratie gebeuren binnen één NSUndoManager-groep zodat
    /// Cmd+Z de hele set in één keer terugdraait.
    private func alignSet() {
        guard !isAligning else { return }
        isAligning = true
        onSetBusy("Aligning set…")
        let targets = portraits
        Task {
            defer { onSetBusy(nil) }
            // 1. Bereken alle transforms (off-main per cutout).
            var items: [(Portrait2, TransformUndo.Snapshot, AutoFramer.Transform)] = []
            for portrait in targets {
                guard let cg = NSImage(data: portrait.cutoutData)?
                    .cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                let before = TransformUndo.snapshot(of: portrait)
                let transform = await AutoFramer.transform(forCutout: cg)
                items.append((portrait, before, transform))
            }
            // 2. Schrijf + registreer alles in één undo-groep.
            undoManager?.beginUndoGrouping()
            undoManager?.setActionName("Align Set")
            withAnimation(.spring(duration: 0.45)) {
                for (portrait, before, transform) in items {
                    portrait.offsetX = transform.offset.width
                    portrait.offsetY = transform.offset.height
                    portrait.scale = transform.scale
                    portrait.touch()
                    TransformUndo.register(
                        undoManager,
                        portrait: portrait,
                        undoTo: before,
                        redoTo: TransformUndo.snapshot(of: portrait),
                        actionName: "Align Set"
                    )
                }
            }
            undoManager?.endUndoGrouping()
            isAligning = false
        }
    }

    /// E12.2: trekt de belichting/kleurbalans van álle portretten naar het
    /// geselecteerde portret (of het meest recente) als referentie, in één
    /// set-brede undo-groep. Lokaal (SetLightingNormalizer); de referentie
    /// zelf blijft ongemoeid (gain ≈ 1 → geen wijziging → geen undo-stap).
    private func matchLighting() {
        guard !isMatchingLight else { return }
        isMatchingLight = true
        onSetBusy("Matching lighting…")
        let targets = portraits
        let reference = targets.first { $0.persistentModelID == selectedID } ?? targets.first
        Task {
            defer { isMatchingLight = false; onSetBusy(nil) }
            guard let reference,
                  let refCG = Self.cgImage(from: reference.cutoutData),
                  let refStats = SetLightingNormalizer.referenceStats(of: refCG) else { return }

            // 1. Bereken de genormaliseerde bytes per (niet-referentie-)portret.
            var items: [(Portrait2, Data, Data)] = []
            for portrait in targets where portrait.persistentModelID != reference.persistentModelID {
                guard let cg = Self.cgImage(from: portrait.cutoutData),
                      let outCG = SetLightingNormalizer.match(cg, to: refStats),
                      let png = Self.pngData(from: outCG) else { continue }
                items.append((portrait, portrait.cutoutData, png))
            }

            // 2. Schrijf + registreer alles in één undo-groep.
            undoManager?.beginUndoGrouping()
            undoManager?.setActionName("Match Lighting")
            withAnimation(.spring(duration: 0.4)) {
                for (portrait, before, after) in items {
                    portrait.cutoutData = after
                    portrait.touch()
                    CutoutDataUndo.register(
                        undoManager, portrait: portrait,
                        undoTo: before, redoTo: after, actionName: "Match Lighting"
                    )
                }
            }
            undoManager?.endUndoGrouping()
        }
    }

    private static func cgImage(from data: Data) -> CGImage? {
        NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func pngData(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// E24.22: rij-frames (per portret-id) zodat het DS-rechtermuis-menu onder de
/// juiste rij gepositioneerd kan worden.
private struct RowAnchorKey: PreferenceKey {
    static var defaultValue: [PersistentIdentifier: Anchor<CGRect>] = [:]
    static func reduce(
        value: inout [PersistentIdentifier: Anchor<CGRect>],
        nextValue: () -> [PersistentIdentifier: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { current, _ in current }
    }
}
