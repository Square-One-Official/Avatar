// Achtergrond-state + brand kit (E07.1). De kleur-presets zijn de
// DS-projectkleuren; brand colors voegt de gebruiker toe via de
// color picker en zijn persistent (barebones brand kit, UserDefaults).
// Gradient-presets zijn 10 mesh-composities op paletten uit uiGradients
// (https://github.com/ghosh/uiGradients) — overlapping radials, geen
// asset. Compositing op exportkwaliteit = E07.2; hier leveren we de
// selectie + een preview-render.

import AppKit
import AvatarUI
import SwiftUI

/// Eén mesh-preset: een palet + blob-layout (CSS-mesh-stijl overlapping
/// radials). `id` is stabiel (selectie-key); `name` is de uiGradients-bron.
struct BackgroundGradientPreset: Identifiable, Equatable {
    struct Blob: Equatable {
        let hex: String
        /// Genormaliseerd, SwiftUI-ruimte (0,0 = linksboven).
        let x: CGFloat
        let y: CGFloat
        /// Straal als fractie van de langste zijde.
        let radius: CGFloat
    }

    let id: String
    let name: String
    let blobs: [Blob]

    var colors: [Color] {
        blobs.compactMap { Color(hexRGB: $0.hex) }
    }
}

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

    /// Tien mesh-achtergronden. Paletten uit uiGradients (Peach, Bora Bora,
    /// Purple Paradise, Aqua Marine, Rose Water, Moonrise, Shroom Haze,
    /// Bourbon, Pinot Noir, Monte Carlo); layout als CSS mesh (meerdere
    /// kleurpunten i.p.v. één diagonale blend).
    static let gradientPresets: [BackgroundGradientPreset] = [
        mesh("peach", "Peach",
             ("#ED4264", 0.18, 0.22, 0.72),
             ("#FFEDBC", 0.88, 0.82, 0.78),
             ("#FF9A8B", 0.82, 0.18, 0.52),
             ("#FFF5E4", 0.28, 0.88, 0.58)),
        mesh("bora-bora", "Bora Bora",
             ("#2BC0E4", 0.16, 0.20, 0.70),
             ("#EAECC6", 0.86, 0.84, 0.74),
             ("#7FDBDA", 0.78, 0.22, 0.50),
             ("#F7FFF0", 0.30, 0.78, 0.56)),
        mesh("purple-paradise", "Purple Paradise",
             ("#1D2B64", 0.14, 0.18, 0.76),
             ("#F8CDDA", 0.88, 0.80, 0.70),
             ("#6B7FD7", 0.72, 0.24, 0.52),
             ("#C9B6E4", 0.28, 0.86, 0.54)),
        mesh("aqua-marine", "Aqua Marine",
             ("#1A2980", 0.12, 0.22, 0.74),
             ("#26D0CE", 0.86, 0.78, 0.72),
             ("#4FACFE", 0.78, 0.16, 0.50),
             ("#00F2FE", 0.32, 0.88, 0.56)),
        mesh("rose-water", "Rose Water",
             ("#E55D87", 0.20, 0.18, 0.70),
             ("#5FC3E4", 0.84, 0.82, 0.72),
             ("#F8B4D9", 0.80, 0.22, 0.50),
             ("#A8E6CF", 0.26, 0.84, 0.54)),
        mesh("moonrise", "Moonrise",
             ("#DAE2F8", 0.16, 0.16, 0.74),
             ("#D6A4A4", 0.86, 0.84, 0.70),
             ("#FFFFFF", 0.78, 0.20, 0.48),
             ("#F5D0C5", 0.28, 0.80, 0.56)),
        mesh("shroom-haze", "Shroom Haze",
             ("#5C258D", 0.18, 0.20, 0.74),
             ("#4389A2", 0.86, 0.80, 0.70),
             ("#9D50BB", 0.76, 0.18, 0.50),
             ("#6DD5ED", 0.30, 0.86, 0.54)),
        mesh("bourbon", "Bourbon",
             ("#EC6F66", 0.18, 0.22, 0.70),
             ("#F3A183", 0.86, 0.78, 0.72),
             ("#FFD3B6", 0.80, 0.20, 0.50),
             ("#FF8A80", 0.28, 0.86, 0.54)),
        mesh("pinot-noir", "Pinot Noir",
             ("#182848", 0.14, 0.18, 0.78),
             ("#4B6CB7", 0.86, 0.80, 0.70),
             ("#2C3E50", 0.72, 0.22, 0.50),
             ("#667EEA", 0.30, 0.86, 0.52)),
        mesh("monte-carlo", "Monte Carlo",
             ("#CC95C0", 0.18, 0.20, 0.70),
             ("#DBD4B4", 0.84, 0.82, 0.68),
             ("#7AA1D2", 0.80, 0.18, 0.52),
             ("#F5E6CC", 0.28, 0.84, 0.56)),
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

    /// Tile-fill voor een mesh-preset (overlapping radials).
    @ViewBuilder
    static func meshFill(_ preset: BackgroundGradientPreset) -> some View {
        GeometryReader { geo in
            let longest = max(geo.size.width, geo.size.height)
            ZStack {
                if let hex = preset.blobs.first?.hex, let base = Color(hexRGB: hex) {
                    base
                }
                ForEach(Array(preset.blobs.enumerated()), id: \.offset) { _, blob in
                    if let color = Color(hexRGB: blob.hex) {
                        RadialGradient(
                            colors: [color, color.opacity(0)],
                            center: UnitPoint(x: blob.x, y: blob.y),
                            startRadius: 0,
                            endRadius: blob.radius * longest
                        )
                    }
                }
            }
        }
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

    /// Rendert een 2-kleuren lineaire gradient (CMS-presets) naar PNG.
    @MainActor
    static func renderGradientPNG(_ colors: [Color], side: CGFloat = 1024) -> Data? {
        let view = gradient(colors).frame(width: side, height: side)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    /// Rendert een mesh-preset naar PNG zodat hij als `backgroundImageData`
    /// opgeslagen en uniform getoond kan worden.
    static func renderGradientPNG(_ preset: BackgroundGradientPreset, side: CGFloat = 1024) -> Data? {
        guard let cg = renderMeshImage(blobs: preset.blobs, size: CGSize(width: side, height: side)) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    /// Overlapping radial mesh (CSS-mesh-techniek). `Blob.y` is SwiftUI-ruimte
    /// (0 = boven); CoreGraphics is y-omhoog, dus we flippen.
    static func renderMeshImage(
        blobs: [BackgroundGradientPreset.Blob],
        size: CGSize
    ) -> CGImage? {
        let w = max(1, Int(size.width.rounded()))
        let h = max(1, Int(size.height.rounded()))
        let longest = CGFloat(max(w, h))
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        if let first = blobs.first {
            ctx.setFillColor(cgColor(hex: first.hex))
        } else {
            ctx.setFillColor(CGColor(srgbRed: 0.11, green: 0.10, blue: 0.09, alpha: 1))
        }
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        for blob in blobs {
            let opaque = cgColor(hex: blob.hex)
            guard let clear = opaque.copy(alpha: 0),
                  let grad = CGGradient(
                    colorsSpace: cs,
                    colors: [opaque, clear] as CFArray,
                    locations: [0, 1]
                  ) else { continue }
            let center = CGPoint(
                x: blob.x * CGFloat(w),
                y: (1 - blob.y) * CGFloat(h)
            )
            ctx.drawRadialGradient(
                grad,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: blob.radius * longest,
                options: []
            )
        }
        return ctx.makeImage()
    }

    private static func mesh(
        _ id: String,
        _ name: String,
        _ blobs: (String, CGFloat, CGFloat, CGFloat)...
    ) -> BackgroundGradientPreset {
        BackgroundGradientPreset(
            id: id,
            name: name,
            blobs: blobs.map { BackgroundGradientPreset.Blob(hex: $0.0, x: $0.1, y: $0.2, radius: $0.3) }
        )
    }

    private static func cgColor(hex: String) -> CGColor {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            return CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        }
        return CGColor(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
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

// UXS-22: `Color.hexRGB` / `Color(hexRGB:)` leven nu in AvatarUI (DSColor),
// samen met de 8-cijfer-variant die BannerDocRenderer nodig had. Deze kopie
// accepteerde alleen 6 cijfers — dat gaf per call site een ander antwoord.
