import CoreGraphics
import CoreImage
import Foundation

/// Achtergrond-compositing (E07.2): zet een cutout (RGBA met alpha) over
/// een kleur óf een achtergrondafbeelding en levert een ondoorzichtig,
/// vierkant exportbeeld. Het canvas is 1:1 (zelfde conventie als de editor,
/// E06.4): de cutout-transform leeft in een vierkante "canvas-units"-ruimte
/// en wordt naar de exportresolutie geschaald, zodat de WYSIWYG-preview en
/// de export identiek kaderen.
///
/// Exportkwaliteit: alles wordt op de volle `outputSize` in linear-sRGB
/// samengesteld (geen tussentijdse downscale), met hoge-kwaliteit
/// resampling van zowel de achtergrond als de cutout.
public enum BackgroundCompositor {

    /// Achtergrondbron.
    public enum Background: Sendable {
        case color(red: Double, green: Double, blue: Double)
        case image(CGImage)
    }

    /// Cutout-plaatsing in canvas-units (vierkant). `offset`/`scale` zijn
    /// exact de Portrait2-velden uit E06.4; `canvasUnit` is de breedte van
    /// die ruimte (FramingConstants.editCanvas = 1024). `scale == 0`
    /// betekent "geen transform" → de compositor doet een fill-fit.
    public struct Placement: Sendable {
        public var offsetX: Double
        public var offsetY: Double
        public var scale: Double
        public var canvasUnit: Double

        public init(offsetX: Double, offsetY: Double, scale: Double, canvasUnit: Double = 1024) {
            self.offsetX = offsetX
            self.offsetY = offsetY
            self.scale = scale
            self.canvasUnit = canvasUnit
        }
    }

    public enum Failure: Error, Equatable {
        case renderFailed
    }

    /// Compositeert `cutout` over `background` op een vierkant van
    /// `outputSize`×`outputSize` pixels.
    public static func composite(
        cutout: CGImage,
        over background: Background,
        placement: Placement,
        outputSize: Int = 2048
    ) throws -> CGImage {
        let side = CGFloat(outputSize)
        let canvasRect = CGRect(x: 0, y: 0, width: side, height: side)

        // Achtergrond als CIImage, schaal-gevuld over het hele vierkant.
        let backgroundCI: CIImage
        switch background {
        case let .color(r, g, b):
            backgroundCI = CIImage(color: CIColor(red: r, green: g, blue: b))
                .cropped(to: canvasRect)
        case let .image(image):
            backgroundCI = aspectFill(CIImage(cgImage: image), into: canvasRect)
        }

        // Cutout-plaatsing: canvas-units → exportpixels. CoreImage heeft
        // een bottom-left origin; de transform (en Portrait2) rekenen
        // top-left, dus de Y wordt gespiegeld.
        let unit = placement.canvasUnit > 0 ? placement.canvasUnit : 1024
        let factor = side / CGFloat(unit)
        let cutoutCI = CIImage(cgImage: cutout)
        let cw = CGFloat(cutout.width)
        let ch = CGFloat(cutout.height)

        let resolved = resolvedPlacement(placement, cutoutWidth: cw, cutoutHeight: ch, unit: CGFloat(unit))
        let drawScale = resolved.scale * factor
        let drawW = cw * drawScale
        let drawH = ch * drawScale
        let drawX = resolved.offsetX * factor
        // Top-left offsetY → bottom-left: y = side - (offsetY*factor + drawH).
        let drawY = side - (resolved.offsetY * factor + drawH)

        let placed = cutoutCI
            .transformed(by: CGAffineTransform(scaleX: drawScale, y: drawScale))
            .transformed(by: CGAffineTransform(translationX: drawX, y: drawY))

        let composite = placed
            .composited(over: backgroundCI)
            .cropped(to: canvasRect)

        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let out = EngineRendering.linearContext.createCGImage(
            composite, from: canvasRect, format: .RGBA8, colorSpace: cs
        ) else {
            throw Failure.renderFailed
        }
        return out
    }

    /// E24.18: frame-ademruimte-padding (moet gelijk zijn aan de app-zijdige
    /// `FramingConstants.frameFitPadding`; AvatarKit kent die niet).
    public static let fitPadding: CGFloat = 0.85

    /// `scale == 0` → fit-met-marge (zelfde regel als de editor, E24.18):
    /// cutout past binnen de canvas met frame-ademruimte, gecentreerd.
    private static func resolvedPlacement(
        _ p: Placement, cutoutWidth cw: CGFloat, cutoutHeight ch: CGFloat, unit: CGFloat
    ) -> (offsetX: CGFloat, offsetY: CGFloat, scale: CGFloat) {
        if p.scale > 0 {
            return (CGFloat(p.offsetX), CGFloat(p.offsetY), CGFloat(p.scale))
        }
        guard cw > 0, ch > 0 else { return (0, 0, 1) }
        let s = min(unit / cw, unit / ch) * fitPadding
        return ((unit - cw * s) / 2, (unit - ch * s) / 2, s)
    }

    /// Schaalt en centreert een CIImage zodat hij `rect` volledig vult
    /// (aspect-fill), met hoge-kwaliteit resampling.
    private static func aspectFill(_ image: CIImage, into rect: CGRect) -> CIImage {
        let ext = image.extent
        guard ext.width > 0, ext.height > 0 else { return image.cropped(to: rect) }
        let scale = max(rect.width / ext.width, rect.height / ext.height)
        let scaled = image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let s = scaled.extent
        let dx = rect.midX - s.midX
        let dy = rect.midY - s.midY
        return scaled
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
            .cropped(to: rect)
    }
}
