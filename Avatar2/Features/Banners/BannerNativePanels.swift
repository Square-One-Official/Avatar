// E37.13–37.15 — Native macOS panels (Freeform-pariteit): image pick, font, colour, preview.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum BannerNativePanels {

    /// Kiest een afbeelding via `NSOpenPanel`; downscale naar PNG.
    static func pickImage(maxSide: Int = 2048) -> PickedImage? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let raw = try? Data(contentsOf: url) else { return nil }
        return pickedImage(from: raw, filename: url.lastPathComponent, maxSide: maxSide)
    }

    static func pickedImage(from raw: Data, filename: String, maxSide: Int = 2048) -> PickedImage? {
        let png = BackgroundKit.downscaledPNG(raw, maxSide: CGFloat(maxSide)) ?? raw
        return PickedImage(data: png, filename: filename, byteCount: png.count)
    }

    static func formatByteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Quick Look via tijdelijk bestand (geen QLPreviewPanel-delegate nodig).
    static func quickLook(data: Data, filename: String = "banner-image.png") {
        let safe = filename.isEmpty ? "banner-image.png" : filename
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe)
        try? data.write(to: url)
        NSWorkspace.shared.open(url)
    }
}

struct PickedImage: Sendable {
    let data: Data
    let filename: String
    let byteCount: Int
}

// MARK: - NSFontPanel

@MainActor
final class BannerFontPanelController: NSObject {
    static let shared = BannerFontPanelController()

    private var apply: ((NSFont) -> Void)?
    private var baseFont: NSFont?
    private weak var restoreTarget: AnyObject?
    private var restoreAction: Selector?

    func show(layer: BannerTextLayer, apply: @escaping (NSFont) -> Void) {
        self.apply = apply
        baseFont = Self.nsFont(from: layer)
        let manager = NSFontManager.shared
        restoreTarget = manager.target as AnyObject?
        restoreAction = manager.action
        manager.target = self
        manager.action = #selector(changeFont(_:))
        if let baseFont {
            NSFontPanel.shared.setPanelFont(baseFont, isMultiple: false)
        }
        NSFontPanel.shared.orderFront(nil)
    }

    func dismiss() {
        NSFontPanel.shared.orderOut(nil)
        restoreFontManager()
        baseFont = nil
    }

    @objc private func changeFont(_ sender: NSFontManager) {
        guard let apply, let font = baseFont else { return }
        let converted = sender.convert(font)
        baseFont = converted
        apply(converted)
    }

    private func restoreFontManager() {
        let manager = NSFontManager.shared
        if let restoreTarget { manager.target = restoreTarget }
        if let restoreAction { manager.action = restoreAction }
        apply = nil
    }

    static func nsFont(from layer: BannerTextLayer) -> NSFont {
        let weight = nsWeight(layer.weightRaw)
        if let name = layer.fontName, let font = NSFont(name: name, size: layer.fontSize) {
            return font
        }
        return NSFont.systemFont(ofSize: layer.fontSize, weight: weight)
    }

    static func applyFont(_ font: NSFont, to layer: inout BannerTextLayer) {
        layer.fontSize = Double(font.pointSize)
        let psName = font.fontName
        if psName.hasPrefix(".AppleSystem") || psName.contains("System") {
            layer.fontName = nil
        } else {
            layer.fontName = psName
        }
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.bold) {
            layer.weightRaw = 3
        } else {
            let w = NSFontManager.shared.weight(of: font)
            if w >= 9 { layer.weightRaw = 3 }
            else if w >= 6 { layer.weightRaw = 2 }
            else if w >= 4 { layer.weightRaw = 1 }
            else { layer.weightRaw = 0 }
        }
    }

    private static func nsWeight(_ raw: Int) -> NSFont.Weight {
        switch raw {
        case 1: return .medium
        case 2: return .semibold
        case 3: return .bold
        default: return .regular
        }
    }
}

// MARK: - NSColorPanel

@MainActor
final class BannerColorPanelController: NSObject {
    static let shared = BannerColorPanelController()

    private var apply: ((NSColor) -> Void)?
    private var observer: NSObjectProtocol?

    func show(hex: String, apply: @escaping (NSColor) -> Void) {
        self.apply = apply
        let panel = NSColorPanel.shared
        panel.color = Color(hexRGB: hex).map { NSColor($0) } ?? .white
        observer = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.colorChanged()
        }
        panel.orderFront(nil)
    }

    func dismiss() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        NSColorPanel.shared.orderOut(nil)
        apply = nil
    }

    private func colorChanged() {
        guard let apply else { return }
        apply(NSColorPanel.shared.color)
    }
}
