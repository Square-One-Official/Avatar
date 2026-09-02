import CoreImage
import CoreImage.CIFilterBuiltins

/// Lokale, on-device portret-enhancers (E12.1) — Core Image-port van de v1
/// `ImageProcessor.magicRetouch`. Geen cloud, geen credits: instant en
/// niet-destructief (de caller bewaart het origineel en kan vergelijken /
/// undo'en). Twee niveaus:
///   - `magicRetouch`: de volledige v1-keten (auto-adjust + vibrance +
///     highlight/shadow + warmte + micro-sharpen);
///   - `improveLighting`: alleen het tonale deel (auto-adjust + shadow-lift
///     + lichte warmte), zonder vibrance/sharpen.
public enum PortraitEnhancer {
    private static let context = CIContext()

    /// Volledige one-click retouch (v1-pariteit). nil bij renderfout.
    public static func magicRetouch(_ image: CGImage) -> CGImage? {
        let source = CIImage(cgImage: image)
        var current = source

        // 1. Apple auto-adjustment (gezichtsbalans, tone curve, vibrance…).
        //    Red-eye uit: cutouts hebben geen flits-rode ogen.
        for filter in source.autoAdjustmentFilters(options: [.redEye: false]) {
            filter.setValue(current, forKey: kCIInputImageKey)
            if let out = filter.outputImage { current = out }
        }
        // 2. Vibrance — slimme verzadiging voor doffe kantoortinten.
        let vibrance = CIFilter.vibrance()
        vibrance.inputImage = current
        vibrance.amount = 0.3
        if let out = vibrance.outputImage { current = out }
        // 3. Highlight/shadow — subtiele shadow-lift (onderkin/wenkbrauw).
        let hlShadow = CIFilter.highlightShadowAdjust()
        hlShadow.inputImage = current
        hlShadow.shadowAmount = 0.15
        hlShadow.highlightAmount = 1.0
        if let out = hlShadow.outputImage { current = out }
        // 4. Temperatuur — +200K warmte weg van koel TL-licht.
        let temp = CIFilter.temperatureAndTint()
        temp.inputImage = current
        temp.neutral = CIVector(x: 6500, y: 0)
        temp.targetNeutral = CIVector(x: 6700, y: 0)
        if let out = temp.outputImage { current = out }
        // 5. Micro-contrast voor gevoelsmatige scherpte.
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = current
        sharpen.sharpness = 0.25
        sharpen.radius = 1.0
        if let out = sharpen.outputImage { current = out }

        return render(current, like: image)
    }

    /// Alleen belichting/toon — auto-adjust + shadow-lift + lichte warmte.
    /// Geen vibrance/sharpen, zodat dit duidelijk verschilt van de volle
    /// retouch. nil bij renderfout.
    public static func improveLighting(_ image: CGImage) -> CGImage? {
        let source = CIImage(cgImage: image)
        var current = source

        for filter in source.autoAdjustmentFilters(options: [.redEye: false]) {
            filter.setValue(current, forKey: kCIInputImageKey)
            if let out = filter.outputImage { current = out }
        }
        let hlShadow = CIFilter.highlightShadowAdjust()
        hlShadow.inputImage = current
        hlShadow.shadowAmount = 0.25
        hlShadow.highlightAmount = 1.0
        if let out = hlShadow.outputImage { current = out }
        let temp = CIFilter.temperatureAndTint()
        temp.inputImage = current
        temp.neutral = CIVector(x: 6500, y: 0)
        temp.targetNeutral = CIVector(x: 6700, y: 0)
        if let out = temp.outputImage { current = out }

        return render(current, like: image)
    }

    /// E22.3: handmatige live color-correctie (Edit-paneel). Brightness/
    /// contrast/saturation via CIColorControls, temperature via
    /// temperatureAndTint. Neutrale defaults: brightness 0, contrast 1,
    /// saturation 1, temperatureShift 0 (−1…1 ≈ ±1500K). nil bij renderfout.
    /// Let op (E50.3-meting): CIColorControls rekent in LINEAIR licht —
    /// brightness telt op (tilt zwart mee), contrast draait om 0.5 lineair
    /// (≈ sRGB 0.735). Een belichtings-gain (CIExposureAdjust) is hier bewust
    /// NIET ingevoerd: de Match-lighting-feature is geschrapt en de slider
    /// houdt z'n uitgeleverde gedrag.
    public static func colorAdjust(
        _ image: CGImage,
        brightness: Double,
        contrast: Double,
        saturation: Double,
        temperatureShift: Double
    ) -> CGImage? {
        var current = CIImage(cgImage: image)

        let controls = CIFilter.colorControls()
        controls.inputImage = current
        controls.brightness = Float(brightness)
        controls.contrast = Float(contrast)
        controls.saturation = Float(saturation)
        if let out = controls.outputImage { current = out }

        if temperatureShift != 0 {
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage = current
            temp.neutral = CIVector(x: 6500, y: 0)
            temp.targetNeutral = CIVector(x: 6500 + temperatureShift * 1500, y: 0)
            if let out = temp.outputImage { current = out }
        }

        return render(current, like: image)
    }

    /// Rendert terug naar CGImage op de oorspronkelijke extent/kleurruimte
    /// (auto-adjust kan de extent oneindig maken → croppen).
    private static func render(_ ci: CIImage, like image: CGImage) -> CGImage? {
        let extent = CIImage(cgImage: image).extent
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return context.createCGImage(
            ci.cropped(to: extent), from: extent, format: .RGBA8, colorSpace: colorSpace
        )
    }
}
