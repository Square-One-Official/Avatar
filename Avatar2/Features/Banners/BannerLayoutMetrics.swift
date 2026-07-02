// E37.8 — Layout-rects voor canvas-hit-testing (tekst + logo), top-left coords.

import AppKit
import CoreGraphics
import CoreText

enum BannerLayoutMetrics {

    /// Diagonale stap (canvas-pixels) waarmee opeenvolgende tekstlagen
    /// trapgewijs verschuiven — zoals Freeform bij meerdere “Type to enter text”.
    private static let textStackStepPx: CGFloat = 32

    /// Genormaliseerd midden voor een tekstlaag in de standaard-stapel (`stackIndex`
    /// 0 = canvas-midden, 1 = één stap naar rechts-onder, enz.).
    static func staggeredTextPosition(stackIndex: Int, canvas: CGSize) -> (x: Double, y: Double) {
        let dx = Double(textStackStepPx / max(1, canvas.width))
        let dy = Double(textStackStepPx / max(1, canvas.height))
        let x = 0.5 + dx * Double(max(0, stackIndex))
        let y = 0.5 + dy * Double(max(0, stackIndex))
        return (min(1, max(0, x)), min(1, max(0, y)))
    }

    /// Volgende vrije plek in de stapel: telt welke stap-slots al bezet zijn door
    /// bestaande tekstlagen (binnen tolerantie) en geeft het eerste vrije index terug.
    static func nextTextStackIndex(in texts: [BannerTextLayer], canvas: CGSize) -> Int {
        guard !texts.isEmpty else { return 0 }
        let dx = Double(textStackStepPx / max(1, canvas.width))
        let dy = Double(textStackStepPx / max(1, canvas.height))
        let tolerance = min(dx, dy) * 0.45
        var used = Set<Int>()
        for text in texts {
            for slot in 0...texts.count {
                let pos = staggeredTextPosition(stackIndex: slot, canvas: canvas)
                if abs(text.x - pos.x) <= tolerance, abs(text.y - pos.y) <= tolerance {
                    used.insert(slot)
                }
            }
        }
        var slot = 0
        while used.contains(slot) { slot += 1 }
        return slot
    }

    /// Font voor een tekstlaag (custom font of systeem-font met gewicht).
    static func nsFont(for layer: BannerTextLayer) -> NSFont {
        let weight = nsFontWeight(layer.weightRaw)
        let base = layer.fontName.flatMap { NSFont(name: $0, size: layer.fontSize) }
            ?? NSFont.systemFont(ofSize: layer.fontSize, weight: weight)
        guard layer.italic == true else { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }

    /// Gedeelde attributed string (font · kern · uitlijning · regelafstand) zodat
    /// de gebakken render, de layout-meting én de inline editor identiek wrappen.
    static func attributedString(for layer: BannerTextLayer, color: NSColor? = nil) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        switch layer.alignRaw {
        case 0: paragraph.alignment = .left
        case 2: paragraph.alignment = .right
        default: paragraph.alignment = .center
        }
        paragraph.lineSpacing = layer.lineSpacing
        var attrs: [NSAttributedString.Key: Any] = [
            .font: nsFont(for: layer),
            .kern: layer.tracking,
            .paragraphStyle: paragraph,
        ]
        if layer.underline == true { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if let color { attrs[.foregroundColor] = color }
        return NSAttributedString(string: layer.string, attributes: attrs)
    }

    /// Bepaalt de box-breedte: expliciete `width`-fractie, anders minimaal de
    /// placeholder-breedte zodat uitlijning binnen een stabiel kader kan werken.
    static func textBoxWidth(for layer: BannerTextLayer, canvas: CGSize) -> CGFloat {
        if let widthFrac = layer.width {
            return max(20, CGFloat(widthFrac) * canvas.width)
        }
        let contentW = measuredLineWidth(for: layer)
        var placeholderLayer = layer
        placeholderLayer.string = BannerTextPresets.placeholder
        let placeholderW = measuredLineWidth(for: placeholderLayer)
        return max(24, contentW, placeholderW)
    }

    /// Word-wrap binnen de box-breedte (blauwe zij-handvatten), niet bij hoek-schaal.
    static func wrapsText(at layer: BannerTextLayer) -> Bool {
        if layer.wrapsLines == true { return true }
        if layer.wrapsLines == false { return false }
        return layer.string.contains("\n") || layer.width != nil
    }

    /// Zet een vaste kaderbreedte (zonder wrap) op basis van de huidige inhoud/
    /// placeholder — voor nieuwe lagen zodat hoek-schaal alleen `fontSize` wijzigt.
    static func withInitialFrame(_ layer: BannerTextLayer, canvas: CGSize) -> BannerTextLayer {
        var copy = layer
        guard copy.width == nil else { return copy }
        let boxW = textBoxWidth(for: copy, canvas: canvas)
        copy.width = Double(boxW / max(1, canvas.width))
        copy.wrapsLines = false
        return copy
    }

    /// Canvas-breedte (px) van het kader vóór een hoek-schaal-gesture.
    static func scaleFrameWidthCanvas(for layer: BannerTextLayer, canvas: CGSize) -> Double {
        if let widthFrac = layer.width {
            return Double(widthFrac) * Double(canvas.width)
        }
        return Double(textBoxWidth(for: layer, canvas: canvas))
    }

    /// Box-hoogte voor layout/render (wrap of enkele regel).
    static func textBoxHeight(for layer: BannerTextLayer, canvas: CGSize, boxW: CGFloat) -> CGFloat {
        if wrapsText(at: layer) {
            let framesetter = CTFramesetterCreateWithAttributedString(attributedString(for: layer))
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(location: 0, length: 0), nil,
                CGSize(width: boxW, height: .greatestFiniteMagnitude), nil
            )
            let font = nsFont(for: layer)
            return max(ceil(suggested.height), font.ascender - font.descender)
        }
        let font = nsFont(for: layer)
        let single = layer.string.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? layer.string
        let measure = BannerTextPresets.isEmptyOrPlaceholder(single) ? BannerTextPresets.placeholder : single
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: layer.tracking]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: measure, attributes: attrs))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        return max(font.ascender - font.descender, bounds.height)
    }

    /// Tekst-bounding box in canvas-pixels; oorsprong linksboven (SwiftUI).
    /// Het kader is altijd gecentreerd op `(layer.x, layer.y)`; `alignRaw` beïnvloedt
    /// alleen de tekst binnen het kader, niet de positie van het kader zelf.
    static func textRect(layer: BannerTextLayer, canvas: CGSize) -> CGRect {
        let boxW = textBoxWidth(for: layer, canvas: canvas)
        let boxH = textBoxHeight(for: layer, canvas: canvas, boxW: boxW)
        let anchorX = layer.x * canvas.width
        let centerYTop = layer.y * canvas.height
        return CGRect(x: anchorX - boxW / 2, y: centerYTop - boxH / 2, width: boxW, height: boxH)
    }

    /// X-offset (canvas-px, relatief aan anker) voor één regel binnen een box die
    /// op het anker is gecentreerd. `alignRaw` schuift de regel binnen het kader.
    static func lineXInCenteredBox(bounds: CGRect, boxW: CGFloat, alignRaw: Int) -> CGFloat {
        let boxLeft = -boxW / 2
        switch alignRaw {
        case 0: return boxLeft - bounds.minX
        case 2: return boxLeft + boxW - bounds.width - bounds.minX
        default: return -bounds.width / 2 - bounds.minX
        }
    }

    private static func measuredLineWidth(for layer: BannerTextLayer) -> CGFloat {
        let font = nsFont(for: layer)
        let single = layer.string.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? layer.string
        let measure = BannerTextPresets.isEmptyOrPlaceholder(single) ? BannerTextPresets.placeholder : single
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: layer.tracking]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: measure, attributes: attrs))
        return max(24, CTLineGetBoundsWithOptions(line, .useOpticalBounds).width)
    }

    /// Hit-target/box rond een lege of placeholder-tekst — zelfde gecentreerde kader.
    static func fallbackTextRect(layer: BannerTextLayer, canvas: CGSize) -> CGRect {
        textRect(layer: layer, canvas: canvas)
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
    /// Alleen punten binnen het banner-vlak (0…canvas) tellen mee — anders kan
    /// overflow-tekst klikken buiten de banner onbereikbaar maken voor deselect.
    static func hitTest(at point: CGPoint, doc: BannerDoc, canvas: CGSize) -> BannerElementRef? {
        let canvasBounds = CGRect(origin: .zero, size: canvas)
        guard canvasBounds.contains(point) else { return nil }
        let layers = doc.layers
        for text in layers.texts.reversed() {
            let rect = textRect(layer: text, canvas: canvas).insetBy(dx: -8, dy: -8)
            let visible = rect.intersection(canvasBounds)
            guard visible.width > 0, visible.height > 0, visible.contains(point) else { continue }
            return .text(text.id)
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
