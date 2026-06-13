// Achtergrond-state + brand kit (E07.1). De kleur-presets zijn de
// DS-projectkleuren; brand colors voegt de gebruiker toe via de
// eyedropper (NSColorSampler) en zijn persistent (barebones brand kit,
// UserDefaults). Beeld-presets zijn gegenereerde gradients (echte render,
// geen asset); de ontworpen print-presets uit het frame zijn assets en
// volgen later (ASSETS.md). Compositing op exportkwaliteit = E07.2; hier
// leveren we de selectie + een preview-render.

import AppKit
import AvatarUI
import SwiftUI

enum BackgroundKit {
    /// Vaste kleur-presets (Figma "Color"-rij = DS-projectkleuren).
    static let colorPresets: [Color] = [
        DSColor.Projects.project1,
        DSColor.Projects.project4,
        DSColor.Projects.project8,
        DSColor.Projects.project12,
        DSColor.Projects.project15,
        DSColor.Projects.project18,
    ]

    /// Gegenereerde gradient-presets voor de "Image"-rij (echte render;
    /// ontworpen print-presets zijn assets, zie ASSETS.md).
    static let gradientPresets: [[Color]] = [
        [rgb(0x6EC6FF), rgb(0xE3F2FF)],
        [rgb(0xFFB4A2), rgb(0xE7C6FF)],
        [rgb(0xB5EAD7), rgb(0xC7CEEA)],
        [rgb(0xFFDAC1), rgb(0xFFB7B2)],
        [rgb(0x2C3E50), rgb(0x4CA1AF)],
    ]

    /// Lokale hex→Color (de AvatarUI-init is internal).
    static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    static func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Rendert een gradient-preset naar PNG zodat hij als
    /// `backgroundImageData` opgeslagen en uniform getoond kan worden.
    @MainActor
    static func renderGradientPNG(_ colors: [Color], side: CGFloat = 1024) -> Data? {
        let view = gradient(colors).frame(width: side, height: side)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }
}

/// Persistente brand colors (hex), door de gebruiker toegevoegd via de
/// eyedropper. UserDefaults-backed; @Observable zodat de paneel-rij
/// live bijwerkt.
@MainActor
@Observable
final class BrandColorKit {
    static let shared = BrandColorKit()

    private static let key = "backgroundBrandColorsHex"

    private(set) var hexColors: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hexColors = defaults.stringArray(forKey: Self.key) ?? []
    }

    @ObservationIgnored private let defaults: UserDefaults

    func add(_ hex: String) {
        guard !hexColors.contains(hex) else { return }
        hexColors.append(hex)
        defaults.set(hexColors, forKey: Self.key)
    }
}

extension Color {
    /// #RRGGBB uit deze kleur (best-effort via NSColor in sRGB).
    var hexRGB: String? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((srgb.redComponent * 255).rounded())
        let g = Int((srgb.greenComponent * 255).rounded())
        let b = Int((srgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    init?(hexRGB: String) {
        var s = hexRGB
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self = BackgroundKit.rgb(v)
    }
}
