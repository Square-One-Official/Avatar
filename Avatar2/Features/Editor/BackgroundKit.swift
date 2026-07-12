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

    /// E24.23/24.24: schaal een upload terug naar `maxSide` en her-encodeer als
    /// PNG. Voorkomt enorme blobs (24.23) en levert een uniforme swatch-bron.
    static func downscaledPNG(_ rawData: Data, maxSide: CGFloat = 1024) -> Data? {
        guard let img = NSImage(data: rawData),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxSide / max(w, h))
        if scale >= 1 {
            return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        }
        let nw = Int((w * scale).rounded()), nh = Int((h * scale).rounded())
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
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
/// Audit-opschoning (2026-07-03): de oude picker bewaarde bij élke
/// sluit-actie een tussenstand, waardoor de kit volliep met tientallen bijna
/// identieke tinten ("veel random rood"). De kit saneert daarom bij laden
/// éénmalig de opgeslagen lijst (perceptueel bijna-gelijke kleuren vouwen
/// samen, recentste wint, max `maxStored`) en houdt hem bij `add` schoon.
@MainActor
@Observable
final class BrandColorKit {
    static let shared = BrandColorKit()

    private static let key = "backgroundBrandColorsHex"
    /// Ruim genoeg voor een echte brand-kit, krap genoeg om nooit meer een
    /// eindeloze rij te worden.
    static let maxStored = 12
    /// Euclidische RGB-afstand (0–441) waaronder twee tinten als "dezelfde
    /// kleur" tellen. 30 vouwt picker-drag-tussenstanden samen maar laat
    /// bewust gekozen buurkleuren (bv. twee merkroden) naast elkaar bestaan.
    private static let minDistance: Double = 30

    private(set) var hexColors: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.key) ?? []
        let cleaned = Self.sanitized(stored)
        self.hexColors = cleaned
        if cleaned != stored { defaults.set(cleaned, forKey: Self.key) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    func add(_ hex: String) {
        guard let rgb = Self.rgbComponents(hex) else { return }
        // Bijna-gelijke bestaande tint(en) eruit — de nieuwste wint z'n plek
        // achteraan; daarna cappen op de recentste `maxStored`.
        hexColors.removeAll { existing in
            guard let other = Self.rgbComponents(existing) else { return true }
            return Self.distance(rgb, other) < Self.minDistance
        }
        hexColors.append(hex)
        if hexColors.count > Self.maxStored {
            hexColors.removeFirst(hexColors.count - Self.maxStored)
        }
        defaults.set(hexColors, forKey: Self.key)
    }

    /// Verwijder een brand-kleur (het hover-kruisje in het background-paneel).
    func remove(_ hex: String) {
        hexColors.removeAll { $0 == hex }
        defaults.set(hexColors, forKey: Self.key)
    }

    /// Eénmalige sanering van een opgeslagen lijst: onparseerbare waardes
    /// weg, perceptuele near-duplicates samengevouwen (recentste wint,
    /// volgorde blijft), gecapt op de recentste `maxStored`.
    static func sanitized(_ hexes: [String]) -> [String] {
        var keptRecentFirst: [(hex: String, rgb: (Double, Double, Double))] = []
        for hex in hexes.reversed() {
            guard let rgb = rgbComponents(hex) else { continue }
            let isNearDuplicate = keptRecentFirst.contains {
                distance(rgb, $0.rgb) < minDistance
            }
            if !isNearDuplicate { keptRecentFirst.append((hex, rgb)) }
            if keptRecentFirst.count == maxStored { break }
        }
        return keptRecentFirst.reversed().map(\.hex)
    }

    private static func rgbComponents(_ hex: String) -> (Double, Double, Double)? {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
    }

    private static func distance(
        _ a: (Double, Double, Double), _ b: (Double, Double, Double)
    ) -> Double {
        let dr = a.0 - b.0, dg = a.1 - b.1, db = a.2 - b.2
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}

/// E24.24: persistente custom achtergrond-AFBEELDINGEN (uploads). Net als de
/// brand colors herbruikbaar, maar als PNG-bestanden in Application Support
/// (ids in UserDefaults) i.p.v. hex in UserDefaults — beelden horen niet in
/// UserDefaults. @Observable zodat de Image-rij live een nieuwe swatch toont.
@MainActor
@Observable
final class BackgroundImageKit {
    static let shared = BackgroundImageKit()

    private static let key = "backgroundCustomImageIDs"

    /// Volgorde van opgeslagen uploads (nieuwste achteraan).
    private(set) var imageIDs: [String]

    @ObservationIgnored private let defaults: UserDefaults
    /// Audit-cleanup: gedecodeerde swatches cachen (id → NSImage). Swatch-ids
    /// zijn immutable UUID's (één keer geschreven), dus dit kan niet stale raken;
    /// het scheelt een file-read + decode per render in de swatch-rij.
    @ObservationIgnored private var imageCache: [String: NSImage] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.imageIDs = defaults.stringArray(forKey: Self.key) ?? []
    }

    private var dir: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let d = base.appendingPathComponent("CustomBackgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func url(_ id: String) -> URL? { dir?.appendingPathComponent("\(id).png") }

    func data(for id: String) -> Data? { url(id).flatMap { try? Data(contentsOf: $0) } }

    func image(for id: String) -> NSImage? {
        if let cached = imageCache[id] { return cached }
        guard let img = data(for: id).flatMap({ NSImage(data: $0) }) else { return nil }
        imageCache[id] = img
        return img
    }

    /// Slaat een upload (downscaled) persistent op + voegt 'm als swatch toe.
    /// Geeft de opgeslagen (downscaled) PNG terug voor direct gebruik als
    /// achtergrond. nil bij een onleesbare afbeelding.
    @discardableResult
    func add(_ rawData: Data) -> Data? {
        guard let png = BackgroundKit.downscaledPNG(rawData) else { return nil }
        let id = UUID().uuidString
        guard let u = url(id) else { return png }
        do { try png.write(to: u) } catch { return png }
        imageIDs.append(id)
        defaults.set(imageIDs, forKey: Self.key)
        return png
    }

    /// PoC (Manage backgrounds): verwijder een upload (bestand + id + cache).
    func remove(_ id: String) {
        if let u = url(id) { try? FileManager.default.removeItem(at: u) }
        imageCache[id] = nil
        imageIDs.removeAll { $0 == id }
        defaults.set(imageIDs, forKey: Self.key)
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
