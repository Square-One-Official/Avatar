import SwiftUI
import SwiftData
import AppKit

struct ExportSheet: View {
    let portraits: [Portrait]
    let backgroundResolver: (Portrait) -> BackgroundPreset?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \ExportPreset.sortOrder) private var presets: [ExportPreset]

    @State private var selected: Set<UUID> = []
    @State private var isExporting = false
    @State private var doneMessage: String?
    @State private var errorMessage: String?
    @State private var globalShape: ExportShape = .square
    /// Paths written by the last successful export / Share pass — drives ShareLink.
    @State private var shareURLs: [URL] = []

    /// Single-portrait flow used by the Editor toolbar.
    init(portrait: Portrait, background: BackgroundPreset?) {
        self.portraits = [portrait]
        self.backgroundResolver = { _ in background }
    }

    /// Multi-portrait flow used by the library context menu and sidebar
    /// Export button. The resolver lets the caller pick the right background
    /// per portrait without us re-querying SwiftData inside the sheet.
    init(portraits: [Portrait], backgroundResolver: @escaping (Portrait) -> BackgroundPreset?) {
        self.portraits = portraits
        self.backgroundResolver = backgroundResolver
    }

    private var titleText: String {
        portraits.count > 1
            ? "\(Loc.exportPortrait) (\(portraits.count))"
            : Loc.exportPortrait
    }

    private var totalFileCount: Int {
        selected.count * portraits.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(titleText)
                    .font(.title3.weight(.semibold))
                Spacer()
                Picker(Loc.shape, selection: $globalShape) {
                    Image(systemName: "square").tag(ExportShape.square)
                    Image(systemName: "circle").tag(ExportShape.circle)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                .onChange(of: globalShape) { _, newShape in
                    for preset in presets { preset.shape = newShape }
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(PressableButtonStyle())
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(Loc.close)
            }
            .padding()

            Divider()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(presets) { preset in
                        PresetCard(preset: preset, isSelected: selected.contains(preset.id))
                            .onTapGesture {
                                if selected.contains(preset.id) {
                                    selected.remove(preset.id)
                                } else {
                                    selected.insert(preset.id)
                                }
                            }
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                if let doneMessage {
                    StatusChip(severity: .success, message: doneMessage, style: .soft)
                }
                if let errorMessage {
                    StatusChip(severity: .danger, message: errorMessage, style: .soft)
                }
                Spacer()
                if !shareURLs.isEmpty {
                    ShareLink(items: shareURLs) {
                        Label(Loc.share, systemImage: "square.and.arrow.up")
                    }
                    .help(Loc.shareHelp)
                } else {
                    Button {
                        runExport(toTemporaryForShare: true)
                    } label: {
                        Label(Loc.share, systemImage: "square.and.arrow.up")
                    }
                    .help(Loc.shareHelp)
                    .disabled(selected.isEmpty || isExporting || portraits.isEmpty)
                }
                Button(Loc.close) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    runExport(toTemporaryForShare: false)
                } label: {
                    if isExporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(Loc.exportCount(totalFileCount))
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty || isExporting || portraits.isEmpty)
            }
            .padding()
        }
        .frame(width: 640, height: 520)
        .background(Color.appCanvas)
        .background(WindowBackgroundPainter(colorScheme: colorScheme).frame(width: 0, height: 0))
        .onAppear {
            if let first = presets.first { globalShape = first.shape }
        }
    }

    private func runExport(toTemporaryForShare: Bool) {
        let dir: URL
        if toTemporaryForShare {
            dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("AaavatarShare-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                errorMessage = Loc.exportFailed(error.localizedDescription)
                return
            }
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = Loc.exportHere
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            dir = chosen
        }

        let jobs: [ExportJob] = presets
            .filter { selected.contains($0.id) }
            .map { ExportJob(name: $0.name, width: $0.width, height: $0.height, shape: $0.shape) }

        // Capture all main-actor / model state up-front so the background task
        // is self-contained and Sendable.
        var portraitJobs: [PortraitExportData] = []
        var prepFailed: [String] = []
        for portrait in portraits {
            let displayName = portrait.name.isEmpty ? Loc.portrait : portrait.name
            guard let cutout = appState.adjustedCutout(for: portrait) else {
                prepFailed.append(displayName)
                continue
            }
            let bg = backgroundResolver(portrait)
            let bgLayer = BackgroundLayer.resolve(
                preset: bg,
                fallback: bg.flatMap { appState.backgroundImage(for: $0) }
            )
            let transform = AlignTransform(
                scale: CGFloat(portrait.scale),
                offset: CGSize(width: portrait.offsetX, height: portrait.offsetY)
            )
            portraitJobs.append(PortraitExportData(
                name: portrait.name,
                cutout: cutout,
                background: bgLayer,
                transform: transform
            ))
        }

        if portraitJobs.isEmpty {
            errorMessage = Loc.noImageToExport
            return
        }

        isExporting = true
        errorMessage = nil
        doneMessage = nil
        shareURLs = []

        Task.detached(priority: .userInitiated) {
            let result = ExportRunner.run(
                portraits: portraitJobs,
                jobs: jobs,
                directory: dir
            )
            await MainActor.run {
                isExporting = false
                let allFailures = prepFailed + result.failed
                if !allFailures.isEmpty {
                    errorMessage = Loc.exportFailed(allFailures.joined(separator: ", "))
                }
                if !result.urls.isEmpty {
                    shareURLs = result.urls
                    doneMessage = Loc.filesSaved(result.written)
                    if toTemporaryForShare {
                        presentSharePicker(urls: result.urls)
                    }
                }
            }
        }
    }

    private func presentSharePicker(urls: [URL]) {
        guard let content = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        let rect = NSRect(x: content.bounds.midX, y: content.bounds.midY, width: 1, height: 1)
        picker.show(relativeTo: rect, of: content, preferredEdge: .minY)
    }
}

/// Sendable snapshot of an ExportPreset for use off the main actor.
private struct ExportJob: Sendable {
    let name: String
    let width: Int
    let height: Int
    let shape: ExportShape
}

/// Sendable bundle of everything needed to render one portrait off the main actor.
private struct PortraitExportData: @unchecked Sendable {
    let name: String
    let cutout: CGImage
    let background: BackgroundLayer
    let transform: AlignTransform
}

private enum ExportRunner {
    struct Result {
        let written: Int
        let failed: [String]
        let urls: [URL]
    }

    static func run(
        portraits: [PortraitExportData],
        jobs: [ExportJob],
        directory: URL
    ) -> Result {
        var written = 0
        var failed: [String] = []
        var urls: [URL] = []
        for portrait in portraits {
            let safeName = sanitize(portrait.name.isEmpty ? Loc.portrait : portrait.name)
            for job in jobs {
                let outSize = CGSize(width: job.width, height: job.height)
                guard let img = Compositor.render(
                    cutout: portrait.cutout,
                    background: portrait.background,
                    transform: portrait.transform,
                    outputSize: outSize,
                    shape: job.shape
                ) else {
                    failed.append("\(portrait.name)/\(job.name)"); continue
                }
                let safePreset = sanitize(job.name)
                let url = directory.appendingPathComponent("\(safeName)_\(safePreset).png")
                do {
                    try ExportService.writePNG(img, to: url)
                    written += 1
                    urls.append(url)
                } catch {
                    failed.append("\(portrait.name)/\(job.name)")
                }
            }
        }
        return Result(written: written, failed: failed, urls: urls)
    }

    private static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return s.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "_" }
            .reduce(into: "") { $0.append($1) }
    }
}

private struct PresetCard: View {
    @Bindable var preset: ExportPreset
    let isSelected: Bool

    private var aspect: CGFloat {
        guard preset.height > 0 else { return 1 }
        return CGFloat(preset.width) / CGFloat(preset.height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.appSurface)
                Group {
                    if preset.shape == .circle {
                        Circle()
                            .strokeBorder(Color.secondary, lineWidth: 1)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.secondary, lineWidth: 1)
                    }
                }
                .aspectRatio(aspect, contentMode: .fit)
                .padding(8)
            }
            .frame(height: 80)

            Text(preset.name).font(.callout.weight(.medium))
            Text("\(preset.width) × \(preset.height)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                              lineWidth: isSelected ? 2 : 1)
        }
    }
}
