import CoreGraphics

/// E02.5 (audit-B1): synthetische niet-RGB-fixtures voor de
/// kleurruimte-normalisatietests. Zelfde geometrie als de bewezen
/// Vision-detecteerbare `portraitFixture` uit VisionCutoutEngineTests
/// (donker hoofd+schouders-silhouet op een licht verlopende achtergrond),
/// maar getekend in een DeviceGray- respectievelijk DeviceCMYK-context —
/// de twee bronsoorten (grayscale-PNG, CMYK-JPEG) die vóór de fix op
/// `createCGImage(.RGBA8, bronkleurruimte)` = nil stukliepen.
enum ColorSpaceFixtures {
    /// Hoofd+schouders-silhouet als échte DeviceGray-CGImage (8 bpc, 1 kanaal).
    static func grayPortrait(width: Int, height: Int) -> CGImage {
        let gray = CGColorSpaceCreateDeviceGray()
        return silhouette(
            width: width, height: height,
            space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue,
            backgroundTop: CGColor(colorSpace: gray, components: [0.93, 1])!,
            backgroundBottom: CGColor(colorSpace: gray, components: [0.81, 1])!,
            subject: CGColor(colorSpace: gray, components: [0.13, 1])!
        )
    }

    /// Hoofd+schouders-silhouet als échte DeviceCMYK-CGImage (8 bpc, 4 kanalen).
    static func cmykPortrait(width: Int, height: Int) -> CGImage {
        let cmyk = CGColorSpaceCreateDeviceCMYK()
        return silhouette(
            width: width, height: height,
            space: cmyk, bitmapInfo: CGImageAlphaInfo.none.rawValue,
            backgroundTop: CGColor(colorSpace: cmyk, components: [0.03, 0.02, 0.02, 0.05, 1])!,
            backgroundBottom: CGColor(colorSpace: cmyk, components: [0.07, 0.05, 0.04, 0.18, 1])!,
            subject: CGColor(colorSpace: cmyk, components: [0.55, 0.65, 0.65, 0.85, 1])!
        )
    }

    /// Vlak DeviceGray-beeld (voor helper-tests zonder Vision-onderwerp).
    static func grayFlat(width: Int, height: Int, white: CGFloat) -> CGImage {
        let gray = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: gray,
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(CGColor(colorSpace: gray, components: [white, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// Vlak beeld in een opgegeven RGB-kleurruimte (sRGB, Display P3, …).
    static func rgbFlat(width: Int, height: Int, space: CGColorSpace) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(colorSpace: space, components: [0.2, 0.5, 0.8, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // Zelfde geometrie als `portraitFixture` in VisionCutoutEngineTests.
    private static func silhouette(
        width: Int, height: Int,
        space: CGColorSpace, bitmapInfo: UInt32,
        backgroundTop: CGColor, backgroundBottom: CGColor, subject: CGColor
    ) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: bitmapInfo)!
        let w = CGFloat(width), h = CGFloat(height)
        let gradient = CGGradient(
            colorsSpace: space,
            colors: [backgroundTop, backgroundBottom] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        ctx.setFillColor(subject)
        ctx.fillEllipse(in: CGRect(x: w * 0.15, y: -h * 0.25, width: w * 0.7, height: h * 0.55))
        ctx.fillEllipse(in: CGRect(x: w * 0.32, y: h * 0.30, width: w * 0.36, height: h * 0.42))
        return ctx.makeImage()!
    }
}
