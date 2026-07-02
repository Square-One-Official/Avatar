import CoreGraphics
import CoreImage
import Foundation

/// Banner-compositing (E34.1): rendert een WIJDE, ondoorzichtige cover-
/// afbeelding (LinkedIn 1584×396, X 1500×500) uit een vlak (kleur) of een
/// achtergrondafbeelding (aspect-fill). Bewust een aparte engine náást
/// `BackgroundCompositor`: die laatste is strak vierkant-gekoppeld (de
/// `Placement`-wiskunde, de Y-flip en `canvasRect` gaan uit van één zijde) en
/// wordt door export + board gedeeld — 'm verbreden naar willekeurige `CGSize`
/// zou daar regressies riskeren. De banner heeft géén cutout-plaatsing: het
/// onderwerp staat NIET in de cover (LinkedIn/X leggen de profielfoto er zelf
/// overheen), dus dit is puur de achtergrond-vulling.
///
/// Exportkwaliteit: alles wordt op de volle doelmaat in linear-sRGB
/// samengesteld (geen tussentijdse downscale), met hoge-kwaliteit resampling
/// van de achtergrond — zelfde contract als `BackgroundCompositor`.
public enum BannerCompositor {

    /// Banner-vulling: een vlakke kleur óf een afbeelding (aspect-fill).
    public enum Fill: Sendable {
        case color(red: Double, green: Double, blue: Double)
        /// Backdrop (upload/gradient/CMS/AI): aspect-fill over de hele cover.
        case image(CGImage)
    }

    public enum Failure: Error, Equatable {
        case renderFailed
    }

    /// Compositeert `fill` tot een ondoorzichtige cover van `size` pixels.
    /// `imageFocal` verschuift het brandpunt bij aspect-fill (0.5 = gecentreerd).
    public static func composite(
        fill: Fill,
        size: CGSize,
        imageFocal: CGPoint = CGPoint(x: 0.5, y: 0.5),
        imageZoom: CGFloat = 1
    ) throws -> CGImage {
        let w = max(1, Int(size.width.rounded()))
        let h = max(1, Int(size.height.rounded()))
        let rect = CGRect(x: 0, y: 0, width: w, height: h)

        let content: CIImage
        switch fill {
        case let .color(r, g, b):
            content = CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: rect)
        case let .image(image):
            content = aspectFill(CIImage(cgImage: image), into: rect, focal: imageFocal, zoom: imageZoom)
        }

        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let out = EngineRendering.linearContext.createCGImage(
            content, from: rect, format: .RGBA8, colorSpace: cs
        ) else {
            throw Failure.renderFailed
        }
        return out
    }

    /// Schaalt en centreert een CIImage zodat hij `rect` volledig vult
    /// (aspect-fill), met hoge-kwaliteit resampling. Spiegelt
    /// `BackgroundCompositor.aspectFill`.
    private static func aspectFill(
        _ image: CIImage,
        into rect: CGRect,
        focal: CGPoint,
        zoom: CGFloat = 1
    ) -> CIImage {
        let ext = image.extent
        guard ext.width > 0, ext.height > 0 else { return image.cropped(to: rect) }
        let scale = max(rect.width / ext.width, rect.height / ext.height) * max(1, zoom)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let s = scaled.extent
        let focalX = s.minX + focal.x * s.width
        let focalY = s.minY + focal.y * s.height
        let tx = rect.midX - focalX
        let ty = rect.midY - focalY
        return scaled
            .transformed(by: CGAffineTransform(translationX: tx, y: ty))
            .cropped(to: rect)
    }
}
