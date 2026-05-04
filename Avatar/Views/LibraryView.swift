import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    #if !APP_STORE
    @Environment(UpdateManager.self) private var updater
    #endif
    @Query(sort: \Portrait.updatedAt, order: .reverse) private var portraits: [Portrait]
    @Query private var backgrounds: [BackgroundPreset]
    @State private var search = ""
    /// Cached filter result. Rebuilt only when `portraits` or `search` change,
    /// not on every body invalidation. The previous computed-property version
    /// re-ran the O(N) filter every time the body re-evaluated (selection
    /// change, animation tick, pro-quota update, etc.).
    @State private var filtered: [Portrait] = []
    /// Stable identity list used as the `value:` of the List's animation.
    /// Storing this avoids allocating `filtered.map(\.id)` on every render.
    @State private var filteredIDs: [UUID] = []

    var body: some View {
        @Bindable var state = appState
        // Compute the current selection-set facets ONCE per body so per-row
        // context menus don't rescan the filtered list. `multiTargets` is
        // empty when there's a single selection — the row falls back to `[p]`.
        let selectedSet = appState.selectedPortraitIDs
        let multiTargets: [Portrait] = selectedSet.count > 1
            ? filtered.filter { selectedSet.contains($0.id) }
            : []

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(Loc.searchPlaceholder, text: $search)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                if selectedSet.count >= 2 {
                    Button {
                        export(multiTargets)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("\(Loc.export) \(selectedSet.count) \(Loc.portraitsPlural)")
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 8)
            .animation(.easeOut(duration: 0.15), value: selectedSet.count >= 2)

            if filtered.isEmpty {
                ContentUnavailableView(
                    portraits.isEmpty ? Loc.noPortraitsYet : Loc.noResults,
                    systemImage: "person.crop.rectangle",
                    description: Text(portraits.isEmpty
                        ? Loc.importToStart
                        : Loc.adjustSearch)
                )
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $state.selectedPortraitIDs) {
                    ForEach(filtered) { p in
                        PortraitRow(portrait: p, background: background(for: p))
                            .tag(p.id)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .listRowBackground(Color.clear)
                            .contextMenu {
                                let targets: [Portrait] = (selectedSet.contains(p.id) && selectedSet.count > 1)
                                    ? multiTargets
                                    : [p]
                                Button(targets.count > 1
                                       ? "\(Loc.export) \(targets.count) \(Loc.portraitsPlural)"
                                       : Loc.export) {
                                    export(targets)
                                }
                                Divider()
                                Button(targets.count > 1
                                       ? "\(Loc.delete) \(targets.count) \(Loc.portraitsPlural)"
                                       : Loc.delete,
                                       role: .destructive) {
                                    delete(targets)
                                }
                            }
                    }
                }
                .animation(.easeOut(duration: 0.2), value: filteredIDs)
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            #if !APP_STORE
            SidebarUpdateCard()
                .animation(.easeOut(duration: 0.3), value: updater.state)
            #endif

            if !appState.proEntitlement.isPro {
                SidebarProQuotaCard()
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: appState.proEntitlement.freeImportsUsed)
            }
            // Pre-auth checkout grant lives in Settings → Account
            // (LinkDeviceCard) — surfacing it in the sidebar took up
            // permanent real estate from a paying user for a benefit
            // (multi-Mac sync) most users don't need day-to-day.
        }
        .animation(.easeOut(duration: 0.2), value: appState.proEntitlement.isPro)
        .background(Color.appCanvas)
        .onAppear { recomputeFiltered() }
        .onChange(of: portraits) { _, _ in recomputeFiltered() }
        .onChange(of: search) { _, _ in recomputeFiltered() }
    }

    private func recomputeFiltered() {
        let next: [Portrait]
        if search.isEmpty {
            next = portraits
        } else {
            let q = search.lowercased()
            next = portraits.filter {
                $0.name.lowercased().contains(q) || $0.tags.lowercased().contains(q)
            }
        }
        filtered = next
        filteredIDs = next.map(\.id)
    }

    private func export(_ portraits: [Portrait]) {
        guard !portraits.isEmpty else { return }
        appState.libraryExportPortraitIDs = Set(portraits.map(\.id))
    }

    private func delete(_ portraits: [Portrait]) {
        guard !portraits.isEmpty else { return }
        let ids = Set(portraits.map(\.id))
        for p in portraits { context.delete(p) }
        appState.selectedPortraitIDs.subtract(ids)
    }

    /// Resolves the background each portrait should be drawn against.
    /// Honours the per-portrait `backgroundPresetID` so the thumbnail updates
    /// the moment the user picks a different background in the editor.
    private func background(for portrait: Portrait) -> BackgroundPreset? {
        if let id = portrait.backgroundPresetID,
           let bg = backgrounds.first(where: { $0.id == id }) {
            return bg
        }
        return backgrounds.first(where: { $0.isDefault }) ?? backgrounds.first
    }
}

private struct PortraitRow: View {
    let portrait: Portrait
    let background: BackgroundPreset?
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(portrait: portrait, background: background)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(portrait.name.isEmpty ? Loc.unnamed : portrait.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !portrait.tags.isEmpty {
                    Text(portrait.tags)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct Thumbnail: View {
    let portrait: Portrait
    let background: BackgroundPreset?
    @Environment(AppState.self) private var appState

    var body: some View {
        // Flat cached thumbnail — one Image, no GeometryReader, no per-row CI
        // chain or Compositor work after the first paint per (portrait, bg)
        // pair. Falls back to a neutral surface while the cutout decodes.
        if let img = appState.thumbnail(for: portrait, background: background) {
            Image(decorative: img, scale: 1)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fill)
        } else {
            Color.appSurface
        }
    }
}
