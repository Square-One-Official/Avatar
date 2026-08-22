import Foundation
import AppKit
import SwiftData
import UniformTypeIdentifiers

/// Renders portraits to temporary PNG files so they can be dragged to Finder,
/// Desktop, or other apps that accept file drops.
@MainActor
enum PortraitDragExport {
    private static let folderName = "AaavatarDrag"

    /// Writes one composited PNG and returns its file URL, or nil on failure.
    static func fileURL(
        for portrait: Portrait,
        background: BackgroundPreset?,
        appState: AppState
    ) -> URL? {
        guard let cutout = appState.adjustedCutout(for: portrait) else { return nil }
        let bgLayer = BackgroundLayer.resolve(
            preset: background,
            fallback: background.flatMap { appState.backgroundImage(for: $0) }
        )
        let transform = AlignTransform(
            scale: CGFloat(portrait.scale),
            offset: CGSize(width: portrait.offsetX, height: portrait.offsetY)
        )
        let size = CGSize(width: 1024, height: 1024)
        guard let image = Compositor.render(
            cutout: cutout,
            background: bgLayer,
            transform: transform,
            outputSize: size,
            shape: .square
        ) else { return nil }

        let dir = scratchDirectory()
        let safe = sanitize(portrait.name.isEmpty ? Loc.portrait : portrait.name)
        let url = dir.appendingPathComponent("\(safe)-\(portrait.id.uuidString.prefix(8)).png")
        do {
            try ExportService.writePNG(image, to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Provider for a row/cell drag. When the dragged item is part of a
    /// multi-selection, every selected portrait is written into a temporary
    /// folder and that folder is dragged — Finder then receives all files.
    static func itemProvider(
        primary: Portrait,
        selected: [Portrait],
        backgroundResolver: (Portrait) -> BackgroundPreset?,
        appState: AppState
    ) -> NSItemProvider {
        let targets: [Portrait] =
            selected.contains(where: { $0.id == primary.id }) && selected.count > 1
            ? selected
            : [primary]

        if targets.count == 1, let only = targets.first,
           let url = fileURL(for: only, background: backgroundResolver(only), appState: appState) {
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }

        let urls: [(Portrait, URL)] = targets.compactMap { portrait in
            guard let url = fileURL(
                for: portrait,
                background: backgroundResolver(portrait),
                appState: appState
            ) else { return nil }
            return (portrait, url)
        }
        guard !urls.isEmpty else { return NSItemProvider() }

        let bundle = scratchDirectory()
            .appendingPathComponent("Portraits-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try? FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        var usedNames = Set<String>()
        for (portrait, src) in urls {
            var base = sanitize(portrait.name.isEmpty ? Loc.portrait : portrait.name) + ".png"
            if usedNames.contains(base) {
                base = sanitize(portrait.name.isEmpty ? Loc.portrait : portrait.name)
                    + "-\(portrait.id.uuidString.prefix(4)).png"
            }
            usedNames.insert(base)
            let dest = bundle.appendingPathComponent(base)
            try? FileManager.default.copyItem(at: src, to: dest)
        }

        return NSItemProvider(contentsOf: bundle) ?? NSItemProvider()
    }

    private static func scratchDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return s.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "_" }
            .reduce(into: "") { $0.append($1) }
    }
}
