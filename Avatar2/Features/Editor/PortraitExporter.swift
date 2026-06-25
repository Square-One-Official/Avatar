// Export barebones (E08.2). Eén preset: vierkant PNG 1024, via de
// E07.2-BackgroundCompositor zodat de export exact de canvas-WYSIWYG volgt
// (achtergrond + cutout-transform). Free-tier krijgt een watermerk. Daarna
// een macOS share sheet (NSSharingServicePicker).
//
// Geen eigen achtergrond ingesteld → transparante vierkante PNG (cutout op
// zijn transform); mét achtergrond → ondoorzichtige composite.

import AppKit
import AvatarKit
import SwiftUI

/// E19.1: export-vorm (v1-pariteit). Circle/rounded maskeren de vierkante output.
/// `.rounded` (Slack/Discord-stijl) is export-only — de canvas-frame biedt alleen
/// square/circle, en alle canvas-checks zijn binair `== .circle` (rounded valt daar
/// dus terug op square). Alleen de export-picker itereert over `allCases`.
enum ExportShape: String, CaseIterable, Identifiable {
    case square, circle, rounded
    var id: String { rawValue }
    var label: String {
        switch self {
        case .square: return "Square"
        case .circle: return "Circle"
        case .rounded: return "Rounded"
        }
    }
}

enum PortraitExporter {
    static let exportSide = 1024
    /// E19.1: aangeboden maten in de export-popup.
    static let sizeOptions = [512, 1024, 2048]

    /// Bouwt de export-PNG voor een portret. nil als er geen cutout is.
    @MainActor
    static func makePNG(
        for portrait: Portrait2,
        watermark: Bool,
        side: Int = exportSide,
        shape: ExportShape = .square
    ) -> Data? {
        guard var cutout = NSImage(data: portrait.cutoutData)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        // E24.14: pas de niet-destructieve Adjust-laag toe vóór compositing,
        // zodat de export exact het canvas volgt (WYSIWYG). cutoutData zelf
        // blijft rauw; de params leven op het portret.
        let adjust = portrait.adjust
        if !adjust.isNeutral,
           let adjusted = PortraitEnhancer.colorAdjust(
            cutout, brightness: adjust.brightness, contrast: adjust.contrast,
            saturation: adjust.saturation, temperatureShift: adjust.temperature
           ) {
            cutout = adjusted
        }

        let placement = BackgroundCompositor.Placement(
            offsetX: portrait.offsetX,
            offsetY: portrait.offsetY,
            scale: portrait.scale,
            canvasUnit: 1024
        )

        let blur = portrait.portraitBlur
        // "Originele foto"-achtergrondlaag: bij een actief effect de gestylede volle
        // foto (backdrop past bij het effect), anders de rauwe originele foto. Beide
        // delen het cutout-frame/-ratio → de aligned-render registreert gelijk.
        let originalCG = (portrait.effectBackgroundData ?? portrait.originalData).flatMap {
            NSImage(data: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        // AchtergrondLAAG-beeld (spiegelt EditorView.backgroundLayerImage): custom
        // upload, óf de (evt. gestylede) originele foto bij Original-modus en bij
        // Portrait zonder expliciete achtergrond. nil = vlakke kleur of geen achtergrond.
        let backgroundImage: CGImage? = {
            if let data = portrait.backgroundImageData,
               let bg = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return bg
            }
            if portrait.backgroundColorHex != nil { return nil }
            if portrait.useOriginalBackground { return originalCG }
            if blur { return originalCG }
            return nil
        }()

        // De achtergrondLAAG ÍS de originele foto (Original-modus / Portrait zonder
        // eigen achtergrond) → uitgelijnd op de cutout-rect tekenen (registreert,
        // niet dubbel). Custom upload → aspect-fill. Spiegelt EditorView.
        let bgIsAlignedOriginal = portrait.backgroundImageData == nil
            && portrait.backgroundColorHex == nil
            && (portrait.useOriginalBackground || blur)

        var composited: CGImage
        if var bg = backgroundImage {
            // Scherp onderwerp over de achtergrond. Portrait: vervaag die achtergrond
            // eerst (onderwerp blijft scherp).
            if blur { bg = BackgroundBlur.blurred(bg) ?? bg }
            let background: BackgroundCompositor.Background =
                bgIsAlignedOriginal ? .alignedImage(bg) : .image(bg)
            composited = (try? BackgroundCompositor.composite(
                cutout: cutout, over: background, placement: placement, outputSize: side
            )) ?? cutout
        } else if let hex = portrait.backgroundColorHex, let rgb = rgbComponents(hex) {
            composited = (try? BackgroundCompositor.composite(
                cutout: cutout, over: .color(red: rgb.r, green: rgb.g, blue: rgb.b),
                placement: placement, outputSize: side
            )) ?? cutout
        } else {
            // Geen achtergrond → transparante vierkante PNG.
            composited = transparentSquare(cutout: cutout, placement: placement, side: side) ?? cutout
        }

        switch shape {
        case .circle: composited = circleMasked(composited) ?? composited
        case .rounded: composited = roundedMasked(composited) ?? composited
        case .square: break
        }

        let final = watermark ? applyWatermark(to: composited, shape: shape) : composited
        return png(from: final)
    }

    /// E19.1: maskeer de output tot een cirkel (transparant eromheen).
    private static func circleMasked(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.addEllipse(in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.clip()
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Maskeer de output tot een afgeronde vierkant (Slack/Discord-stijl,
    /// transparant in de hoeken). Hoekradius ≈ 22% van de zijde.
    private static func roundedMasked(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        let radius = CGFloat(min(w, h)) * 0.22
        let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                          cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - Helpers

    private static func transparentSquare(cutout: CGImage, placement: BackgroundCompositor.Placement, side: Int) -> CGImage? {
        let s = CGFloat(side)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))
        let unit = placement.canvasUnit > 0 ? placement.canvasUnit : 1024
        let factor = s / CGFloat(unit)
        let cw = CGFloat(cutout.width), ch = CGFloat(cutout.height)
        let drawScale: CGFloat
        let offX: CGFloat, offY: CGFloat
        if placement.scale > 0 {
            drawScale = CGFloat(placement.scale) * factor
            offX = CGFloat(placement.offsetX) * factor
            offY = CGFloat(placement.offsetY) * factor
        } else {
            // E24.18: fit-met-marge (i.p.v. FILL) zodat de export de canvas-
            // ademruimte volgt (WYSIWYG). Canonieke padded-fit in unit-space
            // (gedeeld met EditorCanvasView/-Overlay) × factor → pixel-space.
            let unitFit = AutoFramer.fitTransform(
                cutoutSize: CGSize(width: cw, height: ch),
                canvas: CGSize(width: CGFloat(unit), height: CGFloat(unit))
            )
            drawScale = unitFit.scale * factor
            offX = unitFit.offset.width * factor
            offY = unitFit.offset.height * factor
        }
        let drawW = cw * drawScale, drawH = ch * drawScale
        // top-left offsetY → CG bottom-left.
        ctx.draw(cutout, in: CGRect(x: offX, y: s - (offY + drawH), width: drawW, height: drawH))
        return ctx.makeImage()
    }

    private static func applyWatermark(to image: CGImage, shape: ExportShape = .square) -> CGImage {
        let w = image.width, h = image.height
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let text = "Made with Aaavatar"
        let fontSize = CGFloat(w) * 0.035
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let bounds = CTLineGetImageBounds(line, ctx)
        let margin = CGFloat(w) * 0.03
        // E24.16: bij een cirkel/afgeronde vorm valt de hoek-positie buiten (of in
        // de wegmaskeerde hoek van) de zichtbare vorm → centreer horizontaal en til
        // de tekst omhoog (≈10% van onder, ruim binnen de breedte op die hoogte).
        // Vierkant = hoek rechtsonder zoals voorheen.
        if shape != .square {
            ctx.textPosition = CGPoint(x: (CGFloat(w) - bounds.width) / 2, y: CGFloat(h) * 0.10)
        } else {
            ctx.textPosition = CGPoint(x: CGFloat(w) - bounds.width - margin, y: margin)
        }
        // Subtiele schaduw voor leesbaarheid op lichte achtergronden.
        ctx.setShadow(offset: .zero, blur: fontSize * 0.3, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        CTLineDraw(line, ctx)
        return ctx.makeImage() ?? image
    }

    private static func png(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private static func rgbComponents(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}
