// macOS window/sheet appearance (E23 follow-up). SwiftUI's
// `.preferredColorScheme()` volgt niet betrouwbaar naar sheet-vensters;
// `WindowBackgroundPainter` pusht `NSWindow.appearance` zodat DSColor-tokens
// en native controls de juiste light/dark-variant kiezen.

import AppKit
import SwiftUI

extension NSAppearance {
    var dsIsDarkMode: Bool {
        bestMatch(from: [.darkAqua, .vibrantDark,
                         .accessibilityHighContrastDarkAqua,
                         .accessibilityHighContrastVibrantDark]) != nil
    }
}

/// Volgt het systeem-appearance zodat "System" naar een concrete scheme kan
/// resolven (SwiftUI's `.preferredColorScheme(nil)` wist een eerdere override
/// niet betrouwbaar op macOS).
@MainActor
@Observable
final class SystemAppearanceObserver {
    private(set) var isDark: Bool = false
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
            self?.startObserving()
        }
        DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        isDark = NSApp?.effectiveAppearance.dsIsDarkMode ?? false
    }

    private func startObserving() {
        observation = NSApp?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.refresh()
        }
    }
}

extension AppearancePreference {
    /// Concrete scheme voor modifiers/painter — System volgt het OS.
    func resolvedColorScheme(systemIsDark: Bool) -> ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemIsDark ? .dark : .light
        }
    }
}

/// Zet `NSWindow.appearance` + achtergrond zodat sheet- en hoofdvensters de
/// theme-voorkeur volgen. Gebaseerd op v1 `WindowBackgroundPainter`.
struct WindowBackgroundPainter: NSViewRepresentable {
    let colorScheme: ColorScheme

    final class Coordinator: NSObject {
        var observation: NSKeyValueObservation?
        var latestColorScheme: ColorScheme?
        var hasAppliedScheme = false
        var lastAppliedScheme: ColorScheme?
        deinit { observation?.invalidate() }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.latestColorScheme = colorScheme
        context.coordinator.hasAppliedScheme = true
        context.coordinator.lastAppliedScheme = colorScheme
        DispatchQueue.main.async { [coordinator = context.coordinator] in
            paint(view, colorScheme: coordinator.latestColorScheme ?? colorScheme)
            if let window = view.window, coordinator.observation == nil {
                coordinator.observation = window.observe(
                    \.effectiveAppearance,
                    options: [.new]
                ) { [weak view, weak coordinator] _, _ in
                    guard let view, let coordinator else { return }
                    let next = coordinator.latestColorScheme ?? colorScheme
                    if coordinator.hasAppliedScheme,
                       coordinator.lastAppliedScheme == next {
                        return
                    }
                    coordinator.hasAppliedScheme = true
                    coordinator.lastAppliedScheme = next
                    DispatchQueue.main.async {
                        paint(view, colorScheme: next)
                    }
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.latestColorScheme = colorScheme
        if context.coordinator.hasAppliedScheme,
           context.coordinator.lastAppliedScheme == colorScheme {
            return
        }
        context.coordinator.hasAppliedScheme = true
        context.coordinator.lastAppliedScheme = colorScheme
        let scheme = colorScheme
        DispatchQueue.main.async { paint(nsView, colorScheme: scheme) }
    }
}

private func paint(_ view: NSView, colorScheme: ColorScheme) {
    guard let window = view.window else { return }
    let target: NSAppearance? = switch colorScheme {
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    @unknown default: nil
    }
    window.appearance = target
    window.backgroundColor = windowBackgroundColor(for: colorScheme)
    window.titlebarAppearsTransparent = true
    if let content = window.contentView { invalidateAppearance(content) }
}

private func windowBackgroundColor(for colorScheme: ColorScheme) -> NSColor {
    switch colorScheme {
    case .light: NSColor(srgbHex: 0xFAFAF9, alpha: 0xFF)
    case .dark: NSColor(srgbHex: 0x000000, alpha: 0xFF)
    @unknown default: NSColor(srgbHex: 0x000000, alpha: 0xFF)
    }
}

private func invalidateAppearance(_ view: NSView) {
    view.needsDisplay = true
    for sub in view.subviews { invalidateAppearance(sub) }
}

private extension NSColor {
    convenience init(srgbHex hex: UInt32, alpha: UInt8) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: CGFloat(alpha) / 255.0
        )
    }
}
