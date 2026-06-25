#if DEBUG
// Smoke-only zaaihulp: vult een GEÏSOLEERDE in-memory store met voorbeeld-
// portretten zodat de Portraits-lenzen + de hero-morph deterministisch te
// screenshotten zijn ZONDER Thierry's echte store te vervuilen. Geactiveerd via
// `--smoke-store` (zie Avatar2App). De "cutouts" zijn synthetische silhouetten —
// genoeg om layout/animatie te tonen, duidelijk geen echte personen.

import AppKit
import SwiftData

enum SmokeSeed {
    static func populate(_ context: ModelContext) {
        // (naam, rol, achtergrond-hex, silhouet-kleur)
        let people: [(String, String, UInt32, UInt32)] = [
            ("Ava Bennett", "Product Designer", 0xFFE0B2, 0x6D4C41),
            ("Liam Carter", "iOS Engineer", 0xC8E6C9, 0x2E7D32),
            ("Noah Diaz", "Founder", 0xBBDEFB, 0x1565C0),
            ("Mia Evans", "Marketing Lead", 0xF8BBD0, 0xAD1457),
            ("Zoe Fraser", "Researcher", 0xD1C4E9, 0x4527A0),
            ("Kai Greene", "Data Scientist", 0xFFF9C4, 0xF9A825),
            ("Ivy Holt", "Illustrator", 0xB2DFDB, 0x00695C),
            ("Leo Park", "Photographer", 0xFFCCBC, 0xBF360C),
        ]
        let work = Folder2(name: "Work", order: 0, colorHex: "#4C8BF5")
        let team = Folder2(name: "Team", order: 1, colorHex: "#34C759")
        context.insert(work)
        context.insert(team)

        for (idx, person) in people.enumerated() {
            guard let cutout = silhouettePNG(side: 512, color: person.3) else { continue }
            let portrait = Portrait2(name: person.0, role: person.1, cutoutData: cutout)
            portrait.backgroundColorHex = String(format: "#%06X", person.2)
            portrait.frameShape = .square
            // Spreid over root/Work/Team zodat de map-filtering ook iets toont.
            switch idx % 3 {
            case 1: portrait.folder = work
            case 2: portrait.folder = team
            default: break // root ("Unfiled" → zichtbaar onder "All portraits")
            }
            context.insert(portrait)
        }
        try? context.save()
    }

    /// Synthetisch silhouet (hoofd + schouders) in `color` op transparant — PNG.
    private static func silhouettePNG(side: Int, color hex: UInt32) -> Data? {
        let s = CGFloat(side)
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
        // Schouders: brede ellips onderaan (deels buiten beeld → bustelijn).
        ctx.fillEllipse(in: CGRect(x: s * 0.10, y: -s * 0.34, width: s * 0.80, height: s * 0.72))
        // Hoofd: cirkel erboven.
        ctx.fillEllipse(in: CGRect(x: s * 0.32, y: s * 0.40, width: s * 0.36, height: s * 0.36))
        guard let cg = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}
#endif
