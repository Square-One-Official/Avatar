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
    @Binding var selection: UUID?
    @State private var search = ""

    private var filtered: [Portrait] {
        guard !search.isEmpty else { return portraits }
        let q = search.lowercased()
        return portraits.filter {
            $0.name.lowercased().contains(q) || $0.tags.lowercased().contains(q)
        }
    }

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(Loc.searchPlaceholder, text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding([.horizontal, .top], 12)

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
                                let targets = contextTargets(for: p)
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
                .animation(.easeOut(duration: 0.2), value: filtered.map(\.id))
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .onDeleteCommand {
                    delete(filtered.filter { appState.selectedPortraitIDs.contains($0.id) })
                }
            }

            #if !APP_STORE
            SidebarUpdateCard()
            #endif

            if !appState.proEntitlement.isPro {
                SidebarProQuotaCard()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.proEntitlement.isPro)
        .animation(.easeOut(duration: 0.2), value: appState.proEntitlement.freeImportsUsed)
        .background(Color.appCanvas)
        .onAppear {
            if appState.selectedPortraitIDs.isEmpty, let id = selection {
                appState.selectedPortraitIDs = [id]
            }
        }
        .onChange(of: appState.selectedPortraitIDs) { _, newValue in
            let single: UUID? = newValue.count == 1 ? newValue.first : nil
            if selection != single { selection = single }
        }
        .onChange(of: selection) { _, newValue in
            let desired: Set<UUID> = newValue.map { [$0] } ?? []
            if appState.selectedPortraitIDs.count <= 1 && appState.selectedPortraitIDs != desired {
                appState.selectedPortraitIDs = desired
            }
        }
        #if !APP_STORE
        .animation(.easeOut(duration: 0.3), value: updater.state)
        #endif
    }

    private func contextTargets(for portrait: Portrait) -> [Portrait] {
        let selected = appState.selectedPortraitIDs
        if selected.contains(portrait.id) && selected.count > 1 {
            return filtered.filter { selected.contains($0.id) }
        }
        return [portrait]
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
        if let sel = selection, ids.contains(sel) { selection = nil }
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

    var body: some View {
        // Reuse the same live preview composition as the editor for visual consistency.
        CanvasPreview(portrait: portrait, background: background)
    }
}
