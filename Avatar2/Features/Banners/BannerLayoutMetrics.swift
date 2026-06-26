// E37.8 — Layout-rects voor canvas-hit-testing (tekst + logo), top-left coords.

import AppKit
import CoreGraphics
import CoreText

enum BannerLayoutMetrics {

    /// Tekst-bounding box in canvas-pixels; oorsprong linksboven (SwiftUI).
    static func textRect(layer: BannerTextLayer, canvas: CGSize) -> CGRect {
        if BannerTextPresets.isEmptyOrPlaceholder(layer.string) {
            return fallbackTextRect(layer: layer, canvas: canvas)
        }
        let weight = nsFontWeight(layer.weightRaw)
        let font = layer.fontName.flatMap { NSFont(name: $0, size: layer.fontSize) }
            ?? NSFont.systemFont(ofSize: layer.fontSize, weight: weight)
        let single = layer.string.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? layer.string
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: layer.tracking]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: single, attributes: attrs))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let anchorX = layer.x * canvas.width
        let centerYTop = layer.y * canvas.height
        let textX: CGFloat
        switch layer.alignRaw {
        case 0: textX = anchorX - bounds.minX
        case 2: textX = anchorX - bounds.width - bounds.minX
        default: textX = anchorX - bounds.width / 2 - bounds.minX
        }
        let textY = centerYTop - bounds.height / 2 - bounds.minY
        return CGRect(x: textX, y: textY, width: bounds.width, height: bounds.height)
    }

    /// Minimale hit-target rond tekstanker (placeholder / lege string tijdens edit).
    static func fallbackTextRect(layer: BannerTextLayer, canvas: CGSize) -> CGRect {
        let fontH = layer.fontSize
        let fontW = max(120, CGFloat(layer.string.count) * layer.fontSize * 0.55)
        let anchorX = layer.x * canvas.width
        let centerYTop = layer.y * canvas.height
        return CGRect(
            x: anchorX - fontW / 2,
            y: centerYTop - fontH / 2,
            width: fontW,
            height: fontH
        )
    }

    static func logoRect(layer: BannerLogoLayer, logoImage: CGImage, canvas: CGSize) -> CGRect {
        let targetW = max(1, layer.scale * canvas.width)
        let aspect = CGFloat(logoImage.height) / CGFloat(max(1, logoImage.width))
        let targetH = targetW * aspect
        let cx = layer.x * canvas.width
        let cyTop = layer.y * canvas.height
        return CGRect(x: cx - targetW / 2, y: cyTop - targetH / 2, width: targetW, height: targetH)
    }

    /// Hit-test in canvas-pixels (top-left). Tekst boven logo (paint order).
    static func hitTest(at point: CGPoint, doc: BannerDoc, canvas: CGSize) -> BannerCanvasSelection? {
        let layers = doc.layers
        for text in layers.texts.reversed() {
            let rect = textRect(layer: text, canvas: canvas)
            if rect.insetBy(dx: -8, dy: -8).contains(point) {
                return .text(text.id)
            }
        }
        if let logo = layers.logo,
           let data = doc.logoImageData,
           let cg = BannerDocRenderer.cgImage(from: data) {
            let rect = logoRect(layer: logo, logoImage: cg, canvas: canvas)
            if rect.insetBy(dx: -8, dy: -8).contains(point) {
                return .logo
            }
        }
        return nil
    }

    private static func nsFontWeight(_ raw: Int) -> NSFont.Weight {
        switch raw {
        case 1: return .medium
        case 2: return .semibold
        case 3: return .bold
        default: return .regular
        }
    }
}
