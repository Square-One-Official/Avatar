// Banner-resolver (E34.3). Vertaalt de banner-keuze van een portret naar een
// `BannerCompositor.Fill`. De "Match avatar"-modus leidt de vulling af uit de
// portret-achtergrond; is die niet vlak (transparant/origineel) dan wordt de
// achtergrondkleur uit de originele foto gesampled (DominantColor.edge), met een
// neutrale fallback als er niets te matchen valt.

import AppKit
import AvatarKit

enum BannerResolver {

    /// Neutrale fallback (transparant zonder originele foto): een rustige
    /// donkergrijze cover die als "leeg" leest.
    static let neutralFallback = BannerCompositor.Fill.color(red: 0.12, green: 0.12, blue: 0.13)

    /// Vulling voor de huidige banner-keuze van het portret.
    static func fill(for portrait: Portrait2) -> BannerCompositor.Fill {
        fill(for: portrait, banner: portrait.bannerBackground)
    }

    static func fill(for portrait: Portrait2, banner: BannerBackground) -> BannerCompositor.Fill {
        switch banner {
        case .color(let hex):
            return rgb(hex).map { .color(red: $0.r, green: $0.g, blue: $0.b) } ?? neutralFallback
        case .image(let data):
            return cgImage(data).map { .image($0) } ?? neutralFallback
        case .matchPortrait:
            return matchPortrait(portrait)
        }
    }

    private static func matchPortrait(_ portrait: Portrait2) -> BannerCompositor.Fill {
        switch portrait.background {
        case .color(let hex):
            return rgb(hex).map { .color(red: $0.r, green: $0.g, blue: $0.b) } ?? neutralFallback
        case .image(let data):
            return cgImage(data).map { .image($0) } ?? neutralFallback
        case .original, .transparent:
            // Geen vlakke kleur → sample de achtergrondkleur uit de originele foto.
            if let original = portrait.originalData.flatMap(cgImage),
               let c = DominantColor.edge(original) {
                return .color(red: c.r, green: c.g, blue: c.b)
            }
            return neutralFallback
        }
    }

    private static func cgImage(_ data: Data) -> CGImage? {
        NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}
