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
import AvatarUI

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
        render(renderInput(from: doc, size: size), watermark: watermark, excludingTextIDs: excludingTextIDs)
    }

    /// Sendable momentopname van alles wat `render` nodig heeft. `BannerDoc` is
    /// een SwiftData `@Model` (niet Sendable): snapshot op de main-actor, render
    /// het daarna veilig off-main (`composedImageAsync`).
    struct RenderInput: Sendable {
        let targetSize: CGSize
        let logicalCanvasWidth: Double
        let layers: BannerLayers
        let fillImageData: Data?
        let fillFocal: CGPoint
        let fillZoom: Double
        let logoImageData: Data?
    }

    /// Leest het document synchroon → roep aan waar `doc` veilig is (de main-actor).
    static func renderInput(from doc: BannerDoc, size: CGSize? = nil) -> RenderInput {
        RenderInput(
            targetSize: size ?? doc.canvasSize,
            logicalCanvasWidth: doc.canvasWidth,
            layers: doc.layers,
            fillImageData: doc.fillImageData,
            fillFocal: CGPoint(x: doc.fillImageFocalX, y: doc.fillImageFocalY),
            fillZoom: doc.fillImageZoom,
            logoImageData: doc.logoImageData
        )
    }

    /// Pure, off-main render van een Sendable `RenderInput` — identiek beeld als
    /// de doc-variant, maar zonder `BannerDoc`-toegang (dus thread-safe).
    static func render(
        _ input: RenderInput,
        watermark: Bool = false,
        excludingTextIDs: Set<UUID> = []
    ) -> CGImage? {
        let target = input.targetSize
        let w = max(1, Int(target.width.rounded()))
        let h = max(1, Int(target.height.rounded()))
        let canvas = CGSize(width: w, height: h)
        let layers = input.layers

        guard let base = renderFill(
            layers.fill,
            fillImageData: input.fillImageData,
            fillImageFocal: input.fillFocal,
            fillImageZoom: input.fillZoom,
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

        // Schaalfactor t.o.v. de logische canvasbreedte: bij supersampling (de
        // on-screen preview wordt op displayresolutie gerenderd) of een andere
        // exportmaat moeten absolute tekst-maten (fontgrootte, tracking) mee­schalen.
        let renderScale = canvas.width / CGFloat(max(1, input.logicalCanvasWidth))

        if let logo = layers.logo, let data = input.logoImageData, let cg = Self.cgImage(from: data) {
            drawLogo(cg, layer: logo, in: ctx, canvas: canvas)
        }
        for text in layers.texts where !excludingTextIDs.contains(text.id) {
            drawText(text, in: ctx, canvas: canvas, scale: renderScale)
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
        fillImageZoom: Double,
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
            return try? BannerCompositor.composite(
                fill: .image(cg),
                size: size,
                imageFocal: fillImageFocal,
                imageZoom: CGFloat(fillImageZoom)
            )
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

    private static func drawText(_ rawLayer: BannerTextLayer, in ctx: CGContext, canvas: CGSize, scale: CGFloat) {
        guard !BannerTextPresets.isEmptyOrPlaceholder(rawLayer.string) else { return }
        // Absolute maten meeschalen met de doelresolutie (supersample/export).
        var layer = rawLayer
        layer.fontSize *= Double(scale)
        layer.tracking *= Double(scale)
        layer.lineSpacing *= Double(scale)
        let color = nsColor(hex: layer.colorHex)

        // Vaste breedte → word-wrap binnen een gecentreerde box (CTFramesetter).
        if BannerLayoutMetrics.wrapsText(at: layer) {
            drawWrappedText(layer, color: color, in: ctx, canvas: canvas)
            return
        }

        let font = BannerLayoutMetrics.nsFont(for: layer)

        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: layer.tracking,
        ]
        if layer.underline == true { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        // Eén regel (37.1-foundation; meerregelig + alignering = 37.4).
        let single = layer.string.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? layer.string
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: single, attributes: attrs))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let boxW = BannerLayoutMetrics.textBoxWidth(for: layer, canvas: canvas)
        let boxH = BannerLayoutMetrics.textBoxHeight(for: layer, canvas: canvas, boxW: boxW)

        // Genormaliseerd anker; y=0 = BOVEN → CG-bottom-left omrekenen.
        let anchorX = layer.x * canvas.width
        let cy = canvas.height * (1 - layer.y)

        let textX = BannerLayoutMetrics.lineXInCenteredBox(
            bounds: bounds, boxW: boxW, alignRaw: layer.alignRaw
        )
        // Regel verticaal centreren binnen het kader (niet het kader verschuiven).
        let textY = -boxH / 2 + (boxH - bounds.height) / 2 - bounds.minY

        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: anchorX, y: cy)
        if layer.rotation != 0 { ctx.rotate(by: -layer.rotation * .pi / 180) }
        ctx.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// Word-wrap render binnen een vaste, op het anker gecentreerde box.
    private static func drawWrappedText(_ layer: BannerTextLayer, color: NSColor, in ctx: CGContext, canvas: CGSize) {
        guard let widthFrac = layer.width else { return }
        let boxW = max(20, CGFloat(widthFrac) * canvas.width)
        let attr = BannerLayoutMetrics.attributedString(for: layer, color: color)
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: boxW, height: .greatestFiniteMagnitude), nil
        )
        let boxH = ceil(suggested.height)

        // Anker (genormaliseerd, y boven) → CG bottom-left middelpunt.
        let cx = layer.x * canvas.width
        let cy = canvas.height * (1 - layer.y)
        let boxRect = CGRect(x: cx - boxW / 2, y: cy - boxH / 2, width: boxW, height: boxH)
        let path = CGPath(rect: boxRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)

        ctx.saveGState()
        ctx.textMatrix = .identity
        if layer.rotation != 0 {
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: -layer.rotation * .pi / 180)
            ctx.translateBy(x: -cx, y: -cy)
        }
        CTFrameDraw(frame, ctx)
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

    /// Parseert `#RRGGBB`/`#RRGGBBAA` (en zonder `#`) naar 0…1-componenten.
    /// UXS-22: de parser zelf is gedeeld (`DSHexColor`); alleen de
    /// zwart-fallback voor onparsebare invoer blijft hier, want een render mag
    /// niet halverwege stoppen op één kapotte kleurwaarde.
    private static func rgba(hex: String) -> (Double, Double, Double, Double) {
        guard let c = DSHexColor(hex) else { return (0, 0, 0, 1) }
        return (c.red, c.green, c.blue, c.alpha)
    }

    private static func cgColor(hex: String) -> CGColor {
        let (r, g, b, a) = rgba(hex: hex)
        return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func nsColor(hex: String) -> NSColor {
        let (r, g, b, a) = rgba(hex: hex)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// Fill + tekst + logo + shader-stack — zelfde contract als de Studio-canvas
    /// en export (E38.2). De zware CPU-render (`render`) en de PNG-vrije watermark-
    /// stap draaien OFF-main via `Task.detached`; alleen de doc-snapshot en de
    /// shader-bake (`BannerShaderRenderer.bake`, SwiftUI `ImageRenderer`) lopen op
    /// de main-actor. Beeld identiek aan de oude synchrone variant.
    @MainActor
    static func composedImageAsync(
        _ doc: BannerDoc,
        size: CGSize? = nil,
        watermark: Bool = false,
        excludingTextIDs: Set<UUID> = []
    ) async -> CGImage? {
        let input = renderInput(from: doc, size: size)
        let shaders = doc.layers.shaders
        let exclude = excludingTextIDs

        let baseTask = Task.detached(priority: .userInitiated) {
            render(input, excludingTextIDs: exclude).map(SendableCGImage.init)
        }
        guard let baseBox = await baseTask.value else { return nil }
        let base = baseBox.cgImage

        let active = shaders.filter(\.enabled)
        let shaded = active.isEmpty
            ? base
            : (BannerShaderRenderer.bake(base, shaders: shaders, size: CGSize(width: base.width, height: base.height)) ?? base)

        guard watermark else { return shaded }
        let shadedBox = SendableCGImage(cgImage: shaded)
        let stampTask = Task.detached(priority: .userInitiated) {
            SendableCGImage(cgImage: stampWatermark(on: shadedBox.cgImage) ?? shadedBox.cgImage)
        }
        return await stampTask.value.cgImage
    }
}
