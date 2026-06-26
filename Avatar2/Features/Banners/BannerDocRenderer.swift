// BannerDoc → wijde PNG (E37.1). Componeert de laag-stack (fill · logo · tekst)
// op de canvas-maat tot één ondoorzichtige CGImage. De fill loopt via het
// bestaande `BannerCompositor`-pad (linear-sRGB, aspect-fill) — zelfde
// export-contract als de portret/social-preview-pijplijn; tekst via CoreText
// (spiegelt het watermerk-`CTLine`-pad in PortraitExporter); logo als geschaalde
// CGImage. Off-main aan te roepen.
//
// NB: de procedurale shaders (`layers.shaders`) worden in E38.2 in deze render
// gehaakt; in 37.1 worden ze overgeslagen (forward-compat datamodel).

import AppKit
import CoreGraphics
import CoreText
import AvatarKit

enum BannerDocRenderer {

    /// Rendert `doc` naar een ondoorzichtige wijde CGImage. `size` overschrijft de
    /// canvas-maat (bv. een platform-exportmaat); default = `doc.canvasSize`.
    /// `watermark` stempelt het free-tier "Made with Aaavatar"-merk rechtsonder.
    /// `excludingTextIDs` laat tekstlagen weg die op het canvas live worden bewerkt
    /// (het `NSTextField` toont die scherp; meebakken zou dubbel/wazig geven).
    static func render(
        _ doc: BannerDoc,
        size: CGSize? = nil,
        watermark: Bool = false,
        excludingTextIDs: Set<UUID> = []
    ) -> CGImage? {
        let target = size ?? doc.canvasSize
        let w = max(1, Int(target.width.rounded()))
        let h = max(1, Int(target.height.rounded()))
        let canvas = CGSize(width: w, height: h)
        let layers = doc.layers

        guard let base = renderFill(
            layers.fill,
            fillImageData: doc.fillImageData,
            fillImageFocal: CGPoint(x: doc.fillImageFocalX, y: doc.fillImageFocalY),
            size: canvas
        ) else {
            return nil
        }

        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))

        if let logo = layers.logo, let data = doc.logoImageData, let cg = Self.cgImage(from: data) {
            drawLogo(cg, layer: logo, in: ctx, canvas: canvas)
        }
        for text in layers.texts where !excludingTextIDs.contains(text.id) {
            drawText(text, in: ctx, canvas: canvas)
        }

        if watermark { drawWatermark(in: ctx, canvas: canvas) }

        return ctx.makeImage()
    }

    /// Stempelt het free-tier watermerk op een reeds-gerenderd beeld (bv. NÁ de
    /// shader-bake, E38.2), zodat het merk scherp bovenop blijft i.p.v. mee te
    /// vervormen met een distortion-shader.
    static func stampWatermark(on cg: CGImage) -> CGImage? {
        let w = cg.width, h = cg.height
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return cg }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        drawWatermark(in: ctx, canvas: CGSize(width: w, height: h))
        return ctx.makeImage()
    }

    /// Free-tier hoek-watermerk rechtsonder (spiegelt PortraitExporter): wit op
    /// 85% met een lichte schaduw, hoogte-relatief geschaald.
    private static func drawWatermark(in ctx: CGContext, canvas: CGSize) {
        let fontSize = max(14, canvas.height * 0.05)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Made with Aaavatar", attributes: attrs))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let margin = canvas.height * 0.06
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.textPosition = CGPoint(x: canvas.width - bounds.width - margin, y: margin)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: - Fill

    private static func renderFill(
        _ fill: BannerFill,
        fillImageData: Data?,
        fillImageFocal: CGPoint,
        size: CGSize
    ) -> CGImage? {
        switch fill {
        case let .solid(hex):
            let (r, g, b, _) = rgba(hex: hex)
            return try? BannerCompositor.composite(fill: .color(red: r, green: g, blue: b), size: size)
        case .image:
            guard let data = fillImageData, let cg = cgImage(from: data) else {
                return try? BannerCompositor.composite(fill: .color(red: 0.11, green: 0.10, blue: 0.09), size: size)
            }
            return try? BannerCompositor.composite(fill: .image(cg), size: size, imageFocal: fillImageFocal)
        case let .meshGradient(stops):
            return renderMesh(stops, size: size)
        }
    }

    /// Vereenvoudigde mesh-gradient (37.1): een diagonale lineaire blend over de
    /// stop-kleuren. De échte N-punts mesh komt als shader in E38.
    private static func renderMesh(_ stops: [MeshStop], size: CGSize) -> CGImage? {
        let w = max(1, Int(size.width)); let h = max(1, Int(size.height))
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let colors = stops.map { cgColor(hex: $0.hex) }
        if let first = colors.first {
            ctx.setFillColor(first)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        } else {
            ctx.setFillColor(cgColor(hex: "#1C1917"))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        if colors.count >= 2 {
            let locations: [CGFloat] = colors.indices.map { CGFloat($0) / CGFloat(colors.count - 1) }
            if let grad = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locations) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: 0, y: h),
                    end: CGPoint(x: w, y: 0),
                    options: []
                )
            }
        }
        return ctx.makeImage()
    }

    // MARK: - Tekst

    private static func drawText(_ layer: BannerTextLayer, in ctx: CGContext, canvas: CGSize) {
        guard !BannerTextPresets.isEmptyOrPlaceholder(layer.string) else { return }
        let weight = nsFontWeight(layer.weightRaw)
        let font = layer.fontName.flatMap { NSFont(name: $0, size: layer.fontSize) }
            ?? NSFont.systemFont(ofSize: layer.fontSize, weight: weight)
        let color = nsColor(hex: layer.colorHex)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: layer.tracking,
        ]
        // Eén regel (37.1-foundation; meerregelig + alignering = 37.4).
        let single = layer.string.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? layer.string
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: single, attributes: attrs))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        // Genormaliseerd anker; y=0 = BOVEN → CG-bottom-left omrekenen.
        let anchorX = layer.x * canvas.width
        let cy = canvas.height * (1 - layer.y)

        let textX: CGFloat
        switch layer.alignRaw {
        case 0: textX = -bounds.minX
        case 2: textX = -bounds.width - bounds.minX
        default: textX = -bounds.width / 2 - bounds.minX
        }

        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: anchorX, y: cy)
        if layer.rotation != 0 { ctx.rotate(by: -layer.rotation * .pi / 180) }
        ctx.textPosition = CGPoint(x: textX, y: -bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: - Logo

    private static func drawLogo(_ cg: CGImage, layer: BannerLogoLayer, in ctx: CGContext, canvas: CGSize) {
        let targetW = max(1, layer.scale * canvas.width)
        let aspect = CGFloat(cg.height) / CGFloat(max(1, cg.width))
        let targetH = targetW * aspect
        let cx = layer.x * canvas.width
        let cy = canvas.height * (1 - layer.y)
        let rect = CGRect(x: cx - targetW / 2, y: cy - targetH / 2, width: targetW, height: targetH)
        ctx.draw(cg, in: rect)
    }

    // MARK: - Helpers

    static func cgImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func nsFontWeight(_ raw: Int) -> NSFont.Weight {
        switch raw {
        case ..<(-1): return .light
        case -1: return .regular
        case 0: return .regular
        case 1: return .medium
        case 2: return .semibold
        case 3: return .bold
        default: return .heavy
        }
    }

    /// Parseert `#RRGGBB`/`#RRGGBBAA` (en zonder `#`) naar 0…1-componenten.
    private static func rgba(hex: String) -> (Double, Double, Double, Double) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let value = UInt64(s, radix: 16) else { return (0, 0, 0, 1) }
        switch s.count {
        case 8:
            let r = Double((value >> 24) & 0xFF) / 255
            let g = Double((value >> 16) & 0xFF) / 255
            let b = Double((value >> 8) & 0xFF) / 255
            let a = Double(value & 0xFF) / 255
            return (r, g, b, a)
        default: // 6 (of korter, links-genuld door UInt64)
            let r = Double((value >> 16) & 0xFF) / 255
            let g = Double((value >> 8) & 0xFF) / 255
            let b = Double(value & 0xFF) / 255
            return (r, g, b, 1)
        }
    }

    private static func cgColor(hex: String) -> CGColor {
        let (r, g, b, a) = rgba(hex: hex)
        return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func nsColor(hex: String) -> NSColor {
        let (r, g, b, a) = rgba(hex: hex)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
