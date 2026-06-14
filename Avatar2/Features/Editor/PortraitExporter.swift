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

/// E19.1: export-vorm (v1-pariteit). Circle maskeert de vierkante output.
enum ExportShape: String, CaseIterable, Identifiable {
    case square, circle
    var id: String { rawValue }
    var label: String { self == .square ? "Square" : "Circle" }
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
        guard let cutout = NSImage(data: portrait.cutoutData)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let placement = BackgroundCompositor.Placement(
            offsetX: portrait.offsetX,
            offsetY: portrait.offsetY,
            scale: portrait.scale,
            canvasUnit: 1024
        )

        var composited: CGImage
        if let data = portrait.backgroundImageData,
           let bg = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            composited = (try? BackgroundCompositor.composite(
                cutout: cutout, over: .image(bg), placement: placement, outputSize: side
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

        if shape == .circle { composited = circleMasked(composited) ?? composited }

        let final = watermark ? applyWatermark(to: composited) : composited
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

    /// Presenteert het macOS share sheet vanaf een view-anker.
    @MainActor
    static func share(_ data: Data, from view: NSView?) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Aaavatar-portrait.png")
        try? data.write(to: url)
        let picker = NSSharingServicePicker(items: [url])
        let anchor = view ?? NSApp.keyWindow?.contentView
        if let anchor {
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
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
            let fit = max(CGFloat(unit) / cw, CGFloat(unit) / ch)
            drawScale = fit * factor
            offX = (s - cw * drawScale) / 2
            offY = (s - ch * drawScale) / 2
        }
        let drawW = cw * drawScale, drawH = ch * drawScale
        // top-left offsetY → CG bottom-left.
        ctx.draw(cutout, in: CGRect(x: offX, y: s - (offY + drawH), width: drawW, height: drawH))
        return ctx.makeImage()
    }

    private static func applyWatermark(to image: CGImage) -> CGImage {
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
        ctx.textPosition = CGPoint(x: CGFloat(w) - bounds.width - margin, y: margin)
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
