// E37.16 — Reken-helpers voor multi-selectie: gecombineerde bounding box,
// uniform groep-schalen en uitlijnen (6 assen). Alle functies werken op
// `BannerLayers` value-types en in canvas-pixels (top-left), zodat de aanroeper
// het resultaat als één undo-bare mutatie kan wegschrijven.

import CoreGraphics
import Foundation

enum BannerGroupTransform {

    enum AlignAxis {
        case left, centerH, right, top, centerV, bottom
    }

    /// De canvas-pixel-rect van één element (tekst of logo), of `nil`.
    static func rect(of ref: BannerElementRef, doc: BannerDoc, canvas: CGSize) -> CGRect? {
        switch ref {
        case let .text(id):
            guard let text = doc.layers.texts.first(where: { $0.id == id }) else { return nil }
            return BannerLayoutMetrics.textRect(layer: text, canvas: canvas)
        case .logo:
            guard let logo = doc.layers.logo,
                  let data = doc.logoImageData,
                  let cg = BannerDocRenderer.cgImage(from: data) else { return nil }
            return BannerLayoutMetrics.logoRect(layer: logo, logoImage: cg, canvas: canvas)
        }
    }

    /// De gezamenlijke bounding box (canvas-px) van alle gegeven elementen.
    static func combinedRect(_ refs: Set<BannerElementRef>, doc: BannerDoc, canvas: CGSize) -> CGRect? {
        var union: CGRect?
        for ref in refs {
            guard let r = rect(of: ref, doc: doc, canvas: canvas) else { continue }
            union = union.map { $0.union(r) } ?? r
        }
        return union
    }

    /// Schaalt alle elementen uniform met `factor` rondom `anchor` (canvas-px).
    /// Tekst → `fontSize` (en box-`width`); logo → `scale`. Posities schalen mee
    /// t.o.v. het anker. Geeft nieuwe `BannerLayers` terug (puur).
    static func scaled(
        _ layers: BannerLayers,
        refs: Set<BannerElementRef>,
        canvas: CGSize,
        factor: CGFloat,
        anchor: CGPoint
    ) -> BannerLayers {
        let k = Double(factor)
        guard k > 0 else { return layers }
        let ax = Double(anchor.x), ay = Double(anchor.y)
        let cw = Double(canvas.width), ch = Double(canvas.height)
        var out = layers

        for ref in refs {
            switch ref {
            case let .text(id):
                guard let i = out.texts.firstIndex(where: { $0.id == id }) else { continue }
                out.texts[i].fontSize = max(8, out.texts[i].fontSize * k)
                if let w = out.texts[i].width { out.texts[i].width = w * k }
                let cx = out.texts[i].x * cw
                let cy = out.texts[i].y * ch
                out.texts[i].x = ((ax + (cx - ax) * k) / cw).clamped01
                out.texts[i].y = ((ay + (cy - ay) * k) / ch).clamped01
            case .logo:
                guard var logo = out.logo else { continue }
                logo.scale = min(0.95, max(0.02, logo.scale * k))
                let cx = logo.x * cw
                let cy = logo.y * ch
                logo.x = ((ax + (cx - ax) * k) / cw).clamped01
                logo.y = ((ay + (cy - ay) * k) / ch).clamped01
                out.logo = logo
            }
        }
        return out
    }

    /// Lijnt alle elementen uit t.o.v. de gezamenlijke selectie-bounds.
    static func aligned(
        _ layers: BannerLayers,
        refs: Set<BannerElementRef>,
        doc: BannerDoc,
        canvas: CGSize,
        axis: AlignAxis
    ) -> BannerLayers {
        guard refs.count >= 2, let bounds = combinedRect(refs, doc: doc, canvas: canvas) else { return layers }
        let cw = Double(canvas.width), ch = Double(canvas.height)
        var out = layers

        for ref in refs {
            guard let r = rect(of: ref, doc: doc, canvas: canvas) else { continue }
            var cx = Double(r.midX)
            var cy = Double(r.midY)
            switch axis {
            case .left:    cx = Double(bounds.minX + r.width / 2)
            case .centerH: cx = Double(bounds.midX)
            case .right:   cx = Double(bounds.maxX - r.width / 2)
            case .top:     cy = Double(bounds.minY + r.height / 2)
            case .centerV: cy = Double(bounds.midY)
            case .bottom:  cy = Double(bounds.maxY - r.height / 2)
            }
            switch ref {
            case let .text(id):
                guard let i = out.texts.firstIndex(where: { $0.id == id }) else { continue }
                out.texts[i].x = (cx / cw).clamped01
                out.texts[i].y = (cy / ch).clamped01
            case .logo:
                guard out.logo != nil else { continue }
                out.logo!.x = (cx / cw).clamped01
                out.logo!.y = (cy / ch).clamped01
            }
        }
        return out
    }
}

private extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
