import SwiftUI
import SwiftData
import AppKit
import QuickLook
import QuickLookUI

struct LibraryView: View {
    let search: String

    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    @Environment(AppState.self) private var appState
    #if !APP_STORE
    @Environment(UpdateManager.self) private var updater
    #endif
    @Query(sort: \Portrait.updatedAt, order: .reverse) private var portraits: [Portrait]
    @Query private var backgrounds: [BackgroundPreset]
    @State private var filtered: [Portrait] = []
    @State private var filteredIDs: [UUID] = []
    @State private var quickLookURL: URL?

    var body: some View {
        @Bindable var state = appState
        let selectedSet = appState.selectedPortraitIDs
        let multiTargets: [Portrait] = selectedSet.count > 1
            ? filtered.filter { selectedSet.contains($0.id) }
            : []

        VStack(spacing: 0) {
            if filtered.isEmpty {
                emptyState
            } else {
                portraitList(selection: $state.selectedPortraitIDs,
                             selectedSet: selectedSet,
                             multiTargets: multiTargets)
            }

            #if !APP_STORE
            SidebarUpdateCard()
                .motionAwareAnimation(.easeOut(duration: 0.3), value: updater.state)
            #endif

            if !appState.proEntitlement.isPro {
                SidebarProQuotaCard()
                    .transition(.opacity)
                    .motionAwareAnimation(.easeOut(duration: 0.2),
                                          value: appState.proEntitlement.freeImportsUsed)
            }
        }
        .motionAwareAnimation(.easeOut(duration: 0.2), value: appState.proEntitlement.isPro)
        .background(Color.appCanvas)
        .onAppear { recomputeFiltered() }
        .onChange(of: portraits) { _, _ in recomputeFiltered() }
        .onChange(of: search) { _, _ in recomputeFiltered() }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView(
            portraits.isEmpty ? Loc.noPortraitsYet : Loc.noResults,
            systemImage: "person.crop.rectangle",
            description: Text(portraits.isEmpty ? Loc.importToStart : Loc.adjustSearch)
        )
        .frame(maxHeight: .infinity)
    }

    private func portraitList(
        selection: Binding<Set<UUID>>,
        selectedSet: Set<UUID>,
        multiTargets: [Portrait]
    ) -> some View {
        List(selection: selection) {
            ForEach(filtered) { p in
                PortraitRow(portrait: p, background: background(for: p))
                    .tag(p.id)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .listRowBackground(Color.clear)
                    .onDrag {
                        PortraitDragExport.itemProvider(
                            primary: p,
                            selected: selectedSet.contains(p.id) && selectedSet.count > 1
                                ? multiTargets
                                : [p],
                            backgroundResolver: { background(for: $0) },
                            appState: appState
                        )
                    }
                    .contextMenu {
                        rowContextMenu(for: p, selectedSet: selectedSet, multiTargets: multiTargets)
                    }
            }
        }
        .onDeleteCommand {
            let targets: [Portrait] = selectedSet.count > 1
                ? multiTargets
                : portraitsForSelection()
            delete(targets)
        }
        .onKeyPress(.space) {
            if let first = portraitsForSelection().first {
                presentQuickLook(for: first)
                return .handled
            }
            return .ignored
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .motionAwareAnimation(.easeOut(duration: 0.2), value: filteredIDs)
        .quickLookPreview($quickLookURL)
    }

    @ViewBuilder
    private func rowContextMenu(
        for p: Portrait,
        selectedSet: Set<UUID>,
        multiTargets: [Portrait]
    ) -> some View {
        let targets: [Portrait] = (selectedSet.contains(p.id) && selectedSet.count > 1)
            ? multiTargets
            : [p]
        Button(Loc.quickLook) {
            presentQuickLook(for: p)
        }
        Divider()
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

    // MARK: - Actions

    private func recomputeFiltered() {
        let next: [Portrait]
        if search.isEmpty {
            next = portraits
        } else {
            next = portraits.filter {
                $0.name.localizedStandardContains(search)
                    || $0.tags.localizedStandardContains(search)
            }
        }
        filtered = next
        filteredIDs = next.map(\.id)
    }

    private func portraitsForSelection() -> [Portrait] {
        filtered.filter { appState.selectedPortraitIDs.contains($0.id) }
    }

    private func export(_ portraits: [Portrait]) {
        guard !portraits.isEmpty else { return }
        appState.libraryExportPortraitIDs = Set(portraits.map(\.id))
    }

    private func delete(_ portraits: [Portrait]) {
        PortraitLibrary.delete(
            portraits,
            context: context,
            appState: appState,
            undoManager: undoManager
        )
    }

    private func presentQuickLook(for portrait: Portrait) {
        let bg = background(for: portrait)
        guard let cutout = appState.adjustedCutout(for: portrait)
                ?? appState.thumbnail(for: portrait, background: bg) else {
            return
        }
        let bgLayer = BackgroundLayer.resolve(
            preset: bg,
            fallback: bg.flatMap { appState.backgroundImage(for: $0) }
        )
        let transform = AlignTransform(
            scale: CGFloat(portrait.scale),
            offset: CGSize(width: portrait.offsetX, height: portrait.offsetY)
        )
        let size = CGSize(width: 1024, height: 1024)
        let image = Compositor.render(
            cutout: cutout,
            background: bgLayer,
            transform: transform,
            outputSize: size,
            shape: .square
        ) ?? cutout

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AaavatarQuickLook", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = portrait.name.isEmpty ? "portrait" : portrait.name
            .replacingOccurrences(of: "/", with: "_")
        let url = dir.appendingPathComponent("\(safe)-\(portrait.id.uuidString).png")
        do {
            try ExportService.writePNG(image, to: url)
            quickLookURL = url
            // Also drive the classic panel — Space-bar Quick Look is more
            // reliable via QLPreviewPanel than the SwiftUI sheet alone.
            if let panel = QLPreviewPanel.shared() {
                PortraitQuickLookController.shared.url = url
                PortraitQuickLookController.shared.becomePreviewProvider()
                if !panel.isVisible {
                    panel.makeKeyAndOrderFront(nil)
                } else {
                    panel.reloadData()
                }
            }
        } catch {
            // Silent — Space is a convenience; failure shouldn't interrupt.
        }
    }

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
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if !portrait.tags.isEmpty {
                    Text(portrait.tags)
                        .font(.caption)
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

/// Minimal QLPreviewPanel data source so Space opens a real Quick Look panel.
@MainActor
final class PortraitQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = PortraitQuickLookController()
    var url: URL?

    override init() {
        super.init()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as QLPreviewItem?
    }
}

extension PortraitQuickLookController {
    /// Ensures the shared controller is the panel's data source before show.
    func becomePreviewProvider() {
        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = self
            panel.delegate = self
        }
    }
}
