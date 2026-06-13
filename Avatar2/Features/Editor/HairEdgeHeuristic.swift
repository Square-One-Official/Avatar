// Haarrand-heuristiek (E05.6). Detecteert of een Vision-cutout een
// waarschijnlijk rafelige haarrand heeft — de bekende failure mode van
// Apple's semi-binaire matte, die het gedownloade ORMBG-model gladder doet.
//
// FEAT-lane: dit werkt puur op de cutout-output (geen AvatarKit-wijziging).
// Een diepere engine-confidence (matte-zachtheid uit de engine zelf) kan
// dit later vervangen — notitie voor AI-team.
//
// Werking: downsample, zoek per kolom de bovenste opake rij (de silhouet-
// bovenrand), en meet de gemiddelde absolute sprong tussen buurkolommen.
// Een gladde rand (huid/schouder) springt nauwelijks; spikey haarslierten
// in een semi-binaire matte springen veel. Genormaliseerd op de hoogte.

import CoreGraphics

enum HairEdgeHeuristic {
    /// Drempel voor de genormaliseerde gemiddelde randsprong waarboven we
    /// de rand als "rafelig" beschouwen. Geijkt op synthetische fixtures
    /// (gladde boog ~0.00; gekartelde rand ~0.05+).
    static let raggednessThreshold: Double = 0.02

    /// True als de cutout-bovenrand waarschijnlijk rafelig haar bevat.
    static func isLikelyRagged(cutout: CGImage, alphaThreshold: UInt8 = 128) -> Bool {
        raggedness(of: cutout, alphaThreshold: alphaThreshold) > raggednessThreshold
    }

    /// Genormaliseerde maat (≥0) voor de karteligheid van de bovenrand.
    /// Intern/getest los van de drempel.
    static func raggedness(of cutout: CGImage, alphaThreshold: UInt8 = 128) -> Double {
        // Downsample naar ~256 breed voor snelheid en ruisdemping.
        let targetW = 256
        let scale = min(1.0, Double(targetW) / Double(max(1, cutout.width)))
        let w = max(1, Int((Double(cutout.width) * scale).rounded()))
        let h = max(1, Int((Double(cutout.height) * scale).rounded()))
        guard w > 4, h > 4 else { return 0 }

        let bpr = w * 4
        var buf = [UInt8](repeating: 0, count: h * bpr)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: bpr, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return 0
        }
        ctx.draw(cutout, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Per kolom de eerste opake rij vanaf de silhouet-bovenrand.
        // CGContextDrawImage tekent een CGImage geflipt in een bottom-left
        // context: de visuele bovenrand van het beeld komt op buf-rij 0.
        // We scannen dus buf-rijen oplopend; de absolute sprong tussen
        // buurkolommen is wat telt (oriëntatie van de maat doet er niet toe).
        var topRow = [Int?](repeating: nil, count: w)
        for x in 0..<w {
            for r in 0..<h {
                if buf[r * bpr + x * 4 + 3] > alphaThreshold {
                    topRow[x] = r
                    break
                }
            }
        }

        // Alleen kolommen met een silhouet meetellen; gemiddelde absolute
        // sprong tussen opeenvolgende gevulde buurkolommen.
        var deltas: [Int] = []
        var prev: Int?
        for x in 0..<w {
            guard let t = topRow[x] else { prev = nil; continue }
            if let p = prev { deltas.append(abs(t - p)) }
            prev = t
        }
        guard deltas.count >= 8 else { return 0 }
        let mean = Double(deltas.reduce(0, +)) / Double(deltas.count)
        return mean / Double(h)
    }
}
