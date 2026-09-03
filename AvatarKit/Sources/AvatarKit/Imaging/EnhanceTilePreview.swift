import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import os
import Vision

/// Lokale demo-previews voor Enhance-tegels. Geen cloud, geen credits:
/// downscale + Core Image, resultaat in een proces-cache.
///
/// E53.10: per actie twee statische lagen — `base` (ruststand) en `reveal`
/// (eindstand van de hover-animatie) — plus het transparante subject en het
/// gezichts-rect. De beweging zelf (wipe/shimmer/dissolve) leeft in SwiftUI;
/// hier worden alleen pixels gerenderd.
public enum EnhanceTilePreview {
    public enum Action: String, Sendable, Hashable, CaseIterable {
        case retouch
        case studioLight
        case portrait
        case colorise
        case boost
        case fillBody
        case removeBackground
        case appleIntelligence
    }

    /// Lagen voor één tegel. `focus` is het gezichts-rect genormaliseerd
    /// (0…1, oorsprong linksboven) in de ruimte van `base`; nil zonder gezicht.
    public struct Layers: @unchecked Sendable {
        public let base: CGImage
        public let reveal: CGImage?
        /// Head-crop mét alpha (geen stone) — masker voor shimmer/glow.
        public let subject: CGImage
        public let focus: CGRect?
        /// Tussenstappen tussen `base` en `reveal` (Boost: steeds fijnere
        /// pixelblokken). Leeg voor acties zonder stappen-animatie.
        public let steps: [CGImage]

        public init(base: CGImage, reveal: CGImage?, subject: CGImage, focus: CGRect?, steps: [CGImage] = []) {
            self.base = base
            self.reveal = reveal
            self.subject = subject
            self.focus = focus
            self.steps = steps
        }
    }

    public static let maxDimension: CGFloat = 256

    /// `background/inset` (#292524) — achter transparante cutout-pixels.
    /// AvatarKit importeert geen UI-tokens.
    public static let stone = (r: 0.161, g: 0.145, b: 0.141)
    public static let stoneDark = (r: 0.110, g: 0.098, b: 0.090)
    /// Lichte checker-cel (≈ #4D4745): zichtbaar naast stone, geen brand-lime.
    public static let stoneLight = (r: 0.30, g: 0.28, b: 0.27)

    /// Deel van de (vierkante) plaat dat bij Fill in body al "af" is, van boven
    /// gemeten. De tegel toont de bovenste ~73 % van het vierkant; de breuklijn
    /// valt door neus/mond: halve kop solid, rest stippel.
    public static let fillBodySplit: CGFloat = 0.38
    /// Boost: pixel-schaal in rust, en de ladder waarlangs de rechterhelft op
    /// hover "scherper en scherper" wordt (laatste stap = `reveal`, scherp).
    public static let boostPixelScale: Float = 14
    public static let boostResolveScales: [Float] = [10, 7, 4.5, 2.5]
    /// Blur-fracties voor Portrait: rust (scherp) en hover-eind (leesbare bokeh —
    /// zwaarder en de scène "verdwijnt", feedback Thierry 2026-09-02).
    public static let portraitBlurRest: CGFloat = 0
    public static let portraitBlurFull: CGFloat = 0.07

    private static let context = CIContext(options: [.useSoftwareRenderer: false])
    private static let cache: NSCache<NSString, CachedLayers> = {
        let cache = NSCache<NSString, CachedLayers>()
        cache.countLimit = 64
        return cache
    }()
    /// Compat-pad (`renderLayers(action:subject:backdrop:)`): memo van de
    /// voorbereiding per bron-identiteit, zodat 7 tegels van dezelfde bron
    /// niet 7× downscalen + detecteren. Klein: elke entry houdt de vol-res
    /// bron vast (identiteitscheck tegen adres-hergebruik).
    private static let preparedCache: NSCache<NSString, CachedPrepared> = {
        let cache = NSCache<NSString, CachedPrepared>()
        cache.countLimit = 2
        return cache
    }()

    /// Eén keer per bron: downscale + gezichtsdetectie. Alle tegels delen dit.
    /// Vóór deze struct deed élke tegel bij paneel-open z'n eigen Lanczos op de
    /// vol-res cutout plus een eigen Vision-pass (7× parallel, koud → >1 s;
    /// feedback Thierry 2026-09-03).
    public struct PreparedSubject: @unchecked Sendable {
        /// Cutout op tegelformaat (langste zijde ≤ `maxDimension`), mét alpha.
        public let small: CGImage
        /// Grootste gezicht in `small`-pixels (top-left); nil zonder gezicht.
        public let face: CGRect?

        public init(small: CGImage, face: CGRect?) {
            self.small = small
            self.face = face
        }
    }

    /// Downscale + gezichtsdetectie op de bron. Zwaar (vol-res Lanczos +
    /// Vision) → off-main aanroepen; het resultaat is klein en herbruikbaar.
    public static func prepare(subject: CGImage) -> PreparedSubject? {
        guard let small = downscale(subject) else { return nil }
        return PreparedSubject(small: small, face: largestFaceRect(in: small))
    }

    /// Backdrop (originele foto / scène) op tegelformaat, voor
    /// `renderLayers(action:prepared:backdrop:)`.
    public static func prepareBackdrop(_ image: CGImage) -> CGImage? {
        downscale(image)
    }

    /// Rendert alleen de ruststand (compat / smoke).
    public static func render(
        action: Action,
        subject: CGImage,
        backdrop: CGImage? = nil
    ) -> CGImage? {
        renderLayers(action: action, subject: subject, backdrop: backdrop)?.base
    }

    /// Compat-pad: bereidt de bron zelf voor (gememoïseerd op identiteit van
    /// `subject`) en downscalet de backdrop. De app-paden gebruiken
    /// `prepare` + `renderLayers(action:prepared:backdrop:)` zodat de
    /// voorbereiding één keer per portret gebeurt, vóór het paneel opent.
    public static func renderLayers(
        action: Action,
        subject: CGImage,
        backdrop: CGImage? = nil
    ) -> Layers? {
        guard let prepared = memoizedPrepare(subject: subject) else { return nil }
        return renderLayers(
            action: action, prepared: prepared,
            backdrop: backdrop.flatMap(prepareBackdrop)
        )
    }

    /// Rendert alle lagen voor een tegel uit een voorbereide bron. `backdrop`
    /// staat al op tegelformaat (`prepareBackdrop`): Portrait = scène-foto
    /// (geblurd), Remove background = originele foto (achter het subject in
    /// rust). Ontbreekt die, dan stone (Remove background) of een blur van het
    /// subject zelf (Portrait). Goedkoop (alles ≤ 256 px): ms-werk per tegel.
    public static func renderLayers(
        action: Action,
        prepared: PreparedSubject,
        backdrop: CGImage? = nil
    ) -> Layers? {
        renderLayers(action: action, prepared: prepared, backdrop: backdrop, useCache: true)
    }

    static func renderLayers(
        action: Action,
        prepared: PreparedSubject,
        backdrop smallBackdrop: CGImage?,
        useCache: Bool
    ) -> Layers? {
        let small = prepared.small
        let key = cacheKey(action: action, small: small, backdrop: smallBackdrop)
        if useCache, let hit = cache.object(forKey: key),
           hit.small === small, hit.backdrop === smallBackdrop {
            return hit.layers
        }
        let face = prepared.face
        let focusRect = action == .fillBody
            ? bodyFocusRect(in: small, face: face)
            : headFocusRect(in: small, face: face)
        let head = zoomTo(small, source: focusRect)
        let focus = face.map { normalize($0, crop: focusRect, side: head.width) }

        var base: CGImage?
        var reveal: CGImage?
        var steps: [CGImage] = []
        switch action {
        case .boost:
            base = boost(head)
            reveal = head
            steps = boostResolveScales.compactMap { scale in
                pixellate(head, scale: scale).flatMap { splitHorizontal(left: head, right: $0) }
            }
        case .colorise:
            base = colorise(head)
            reveal = head
        case .retouch:
            // Geen magicRetouch (overbelichtte de onderkant van het gezicht):
            // subtiele beauty-preview op landmarks — warme wangen, rodere
            // lippen, kleurrijkere ogen. Het gezicht is al bekend (uit
            // `prepared`, omgerekend naar head-crop-pixels): geen tweede
            // Vision-pass.
            let side = CGFloat(head.width)
            let faceInHead = focus.map {
                CGRect(x: $0.minX * side, y: $0.minY * side, width: $0.width * side, height: $0.height * side)
            }
            let enhanced = retouchPreview(head, face: faceInHead) ?? head
            base = splitHorizontal(left: head, right: enhanced)
            reveal = enhanced
        case .portrait:
            // Volledige scène als blur-laag, niet de head-crop (anders is de
            // bokeh alleen een wazig gezicht).
            let scene = smallBackdrop ?? small
            base = portrait(subject: head, backdrop: scene, blurFraction: portraitBlurRest)
            reveal = portrait(subject: head, backdrop: scene, blurFraction: portraitBlurFull)
        case .studioLight:
            base = studioLight(head)
            reveal = nil
        case .fillBody:
            base = fillBody(head)
            reveal = head
        case .removeBackground:
            // Rust = checker (reveal); hover lost de originele achtergrond op.
            let original = smallBackdrop.flatMap { bd -> CGImage? in
                guard bd.width == small.width, bd.height == small.height else { return nil }
                return composite(head, over: zoomTo(bd, source: focusRect))
            }
            base = original ?? head
            reveal = removeBackground(head)
        case .appleIntelligence:
            base = head
            reveal = nil
        }
        guard let baseImage = base.flatMap(compositeOverStone) else { return nil }
        let layers = Layers(
            base: baseImage,
            reveal: reveal.flatMap(compositeOverStone),
            subject: head,
            focus: focus,
            steps: steps.compactMap(compositeOverStone)
        )
        if useCache {
            cache.setObject(CachedLayers(layers, small: small, backdrop: smallBackdrop), forKey: key)
        }
        return layers
    }

    private static func memoizedPrepare(subject: CGImage) -> PreparedSubject? {
        let key = "\(Unmanaged.passUnretained(subject).toOpaque())|\(subject.width)x\(subject.height)" as NSString
        if let hit = preparedCache.object(forKey: key), hit.subject === subject {
            return hit.prepared
        }
        guard let prepared = prepare(subject: subject) else { return nil }
        preparedCache.setObject(CachedPrepared(prepared, subject: subject), forKey: key)
        return prepared
    }

    // MARK: - Warm-up

    /// Laadt het Vision-gezichtsmodel, de CIContext en de Core Image-kernels
    /// (Lanczos, gaussian, pixellate, morphology, …) op een synthetische
    /// 128 px-bron, zodat de eerste échte paneel-open van een sessie de koude
    /// start (gemeten ~0,4 s los, meer onder 7× parallelle druk) niet betaalt.
    /// Synchroon en zwaar → vanaf een achtergrond-task aanroepen.
    public static func warmUp() {
        guard let subject = syntheticSubject(side: 128),
              let prepared = prepare(subject: subject)
        else { return }
        let backdrop = syntheticBackdrop(side: 128)
        for action in Action.allCases {
            _ = renderLayers(action: action, prepared: prepared, backdrop: backdrop, useCache: false)
        }
    }

    private static let warmUpState = OSAllocatedUnfairLock(initialState: false)

    /// Eénmalig per proces, fire-and-forget op utility-prioriteit (app-launch).
    public static func warmUpInBackground() {
        let first = warmUpState.withLock { started -> Bool in
            defer { started = true }
            return !started
        }
        guard first else { return }
        Task.detached(priority: .utility) { warmUp() }
    }

    /// Transparante plaat met een huidkleurige ellips (geen gezicht → ook het
    /// `opaqueBounds`-pad wordt geraakt).
    static func syntheticSubject(side: Int) -> CGImage? {
        guard let ctx = makeContext(width: side, height: side) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.setFillColor(red: 0.85, green: 0.68, blue: 0.58, alpha: 1)
        let s = CGFloat(side)
        ctx.fillEllipse(in: CGRect(x: s * 0.25, y: s * 0.2, width: s * 0.5, height: s * 0.65))
        return ctx.makeImage()
    }

    static func syntheticBackdrop(side: Int) -> CGImage? {
        guard let ctx = makeContext(width: side, height: side) else { return nil }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [
            CGColor(colorSpace: cs, components: [0.35, 0.45, 0.6, 1])!,
            CGColor(colorSpace: cs, components: [0.8, 0.7, 0.55, 1])!
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(
                gradient, start: .zero, end: CGPoint(x: side, y: side), options: []
            )
        }
        return ctx.makeImage()
    }

    // MARK: - Effects

    /// Links scherp, rechts overdreven pixelate (Wave 765:7655).
    static func boost(_ image: CGImage) -> CGImage? {
        guard let pixelated = pixellate(image, scale: boostPixelScale) else { return nil }
        return splitHorizontal(left: image, right: pixelated)
    }

    /// Links zwart-wit, rechts kleur.
    static func colorise(_ image: CGImage) -> CGImage? {
        guard let mono = saturate(image, amount: 0) else { return nil }
        return splitHorizontal(left: mono, right: image)
    }

    /// Links raw, rechts magic-retouch.
    static func retouch(_ image: CGImage) -> CGImage? {
        guard let enhanced = PortraitEnhancer.magicRetouch(image) else { return image }
        return splitHorizontal(left: image, right: enhanced)
    }

    /// Scherpe cutout over een geblurde, uitvergrote scène (Wave 765:7693).
    /// `blurFraction` × langste zijde = blur-radius. Stone vult transparante hoeken.
    static func portrait(
        subject: CGImage,
        backdrop: CGImage?,
        blurFraction: CGFloat = portraitBlurFull
    ) -> CGImage? {
        let w = subject.width, h = subject.height
        guard let ctx = makeContext(width: w, height: h) else { return nil }
        fillStone(ctx, width: w, height: h)

        let photo = backdrop ?? subject
        let radius = blurFraction * CGFloat(max(photo.width, photo.height))
        if let blurred = radius > 0 ? gaussianBlur(photo, radius: radius) : photo {
            // Scène vult de plaat (scaledToFill) met wat extra zoom zodat
            // randen van de blur buiten beeld vallen.
            let zoom: CGFloat = 1.6
            let scale = max(CGFloat(w) / CGFloat(blurred.width), CGFloat(h) / CGFloat(blurred.height)) * zoom
            let bw = CGFloat(blurred.width) * scale
            let bh = CGFloat(blurred.height) * scale
            ctx.draw(blurred, in: CGRect(x: (CGFloat(w) - bw) / 2, y: (CGFloat(h) - bh) / 2, width: bw, height: bh))
        }
        ctx.draw(subject, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Retouch-preview: huid gladder (edge-preserving blur binnen het
    /// gezichtsvlak — ogen, wenkbrauwen en baard blijven scherp) + een lichte
    /// lift van de huid. Geen kleurtinten (die lazen als een clown, feedback
    /// Thierry 2026-09-02). Zonder gezicht: milde smoothing over het hele beeld.
    static func retouchPreview(_ image: CGImage) -> CGImage? {
        retouchPreview(image, face: largestFaceRect(in: image))
    }

    /// `face`: gezichts-rect in `image`-pixels (top-left), nil = geen gezicht.
    static func retouchPreview(_ image: CGImage, face: CGRect?) -> CGImage? {
        let w = image.width, h = image.height
        let extent = CGRect(x: 0, y: 0, width: w, height: h)
        let ci = CIImage(cgImage: image)
        let side = CGFloat(max(w, h))

        // Zachte versie (huid). Klein: bij 0.014 werd het hele gezicht een waas.
        let smooth = ci.clampedToExtent()
            .applyingGaussianBlur(sigma: side * 0.0075)
            .cropped(to: extent)

        // Randen bewaren: CIEdges → grijs → licht blur → versterken → inverteren.
        let edges = ci
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 4])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .clampedToExtent()
            .applyingGaussianBlur(sigma: side * 0.006)
            .cropped(to: extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 2.5, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 2.5, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 2.5, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
        let keepFlat = edges.applyingFilter("CIColorInvert")

        // Huidvlak: ellips op het gezicht (Vision-rect), zacht uitlopend, mét
        // ogen- en mondzone eruit — die blijven altijd scherp.
        let skin: CIImage? = face.flatMap { f in
            softMask(width: w, height: h, blur: f.width * 0.08) { ctx in
                let cw = f.width * 1.0, ch = f.height * 1.22
                // Vision-rect is top-left; CG-context bottom-left.
                let cy = CGFloat(h) - f.midY
                ctx.fillEllipse(in: CGRect(x: f.midX - cw / 2, y: cy - ch / 2 - f.height * 0.04, width: cw, height: ch))
                ctx.setFillColor(gray: 0, alpha: 1)
                // Ogen (band op ~0.32–0.52 van de gezichtshoogte, van boven) en mond (~0.68–0.90).
                let eyesTop = CGFloat(h) - (f.minY + f.height * 0.30)
                ctx.fillEllipse(in: CGRect(x: f.minX + f.width * 0.08, y: eyesTop - f.height * 0.24, width: f.width * 0.84, height: f.height * 0.24))
                let mouthTop = CGFloat(h) - (f.minY + f.height * 0.66)
                ctx.fillEllipse(in: CGRect(x: f.minX + f.width * 0.24, y: mouthTop - f.height * 0.26, width: f.width * 0.52, height: f.height * 0.26))
            }
        }
        // Beauty-retouch i.p.v. blur (feedback Thierry): het origineel blijft
        // volledig scherp; op de huid komt (1) een soft-light "glow" van een
        // geblurde, iets lichtere kopie — egaliseert toon en licht de huid op
        // zonder randen te verliezen, (2) mildere verzadiging van rode vlekjes,
        // (3) alleen in vlakke huid een lichte textuur-demping.
        func scaled(_ mask: CIImage, _ k: CGFloat) -> CIImage {
            mask.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0)
            ])
        }
        var current = ci
        if let skin {
            let glow = ci.clampedToExtent()
                .applyingGaussianBlur(sigma: side * 0.02)
                .cropped(to: extent)
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.3])
            let glowed = glow.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: ci])
            current = blend(glowed, over: current, mask: scaled(skin, 0.6))
            let even = current.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.88])
            current = blend(even, over: current, mask: scaled(skin, 0.7))
            let flat = skin.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: keepFlat])
            current = blend(smooth, over: current, mask: scaled(flat, 0.45))
        } else {
            current = blend(smooth, over: current, mask: scaled(keepFlat, 0.5))
        }
        return render(current.cropped(to: extent), extent: extent, like: image)
    }

    static func blend(_ foreground: CIImage, over background: CIImage, mask: CIImage) -> CIImage {
        foreground.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask
        ])
    }

    /// Grijswaarde-masker (wit = effect), bottom-left zoals CI; optioneel geblurd.
    static func softMask(width w: Int, height h: Int, blur: CGFloat, draw: (CGContext) -> Void) -> CIImage? {
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(gray: 1, alpha: 1)
        draw(ctx)
        guard let cg = ctx.makeImage() else { return nil }
        var mask = CIImage(cgImage: cg)
        if blur > 0 {
            mask = mask.clampedToExtent().applyingGaussianBlur(sigma: blur)
                .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return mask
    }

    /// Belichting via `PortraitEnhancer.improveLighting` + zachte vignette
    /// naar de hoeken. Geen flare/blob meer (E53.10).
    static func studioLight(_ image: CGImage) -> CGImage? {
        let lit = PortraitEnhancer.improveLighting(image) ?? image
        let w = image.width, h = image.height
        guard let ctx = makeContext(width: w, height: h) else { return nil }
        fillStone(ctx, width: w, height: h)
        ctx.draw(lit, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Vignette: transparant in het midden, stoneDark-α0.35 aan de rand.
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [
            CGColor(colorSpace: cs, components: [stoneDark.r, stoneDark.g, stoneDark.b, 0])!,
            CGColor(colorSpace: cs, components: [stoneDark.r, stoneDark.g, stoneDark.b, 0.35])!
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0.45, 1.0]) {
            let center = CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) * 0.55)
            ctx.drawRadialGradient(
                gradient, startCenter: center, startRadius: 0,
                endCenter: center, endRadius: CGFloat(max(w, h)) * 0.78,
                options: [.drawsAfterEndLocation]
            )
        }
        return ctx.makeImage()
    }

    /// Donkere stone achter transparante pixels, zodat de tegel-plaat volliopt
    /// zonder brand-lime.
    static func compositeOverStone(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = makeContext(width: w, height: h) else { return nil }
        fillStone(ctx, width: w, height: h)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Bovenste `fillBodySplit` solid; daaronder het silhouet als dot-stipple
    /// + dunne contourlijn ("nog in te tekenen lichaam"). Over stone.
    static func fillBody(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = makeContext(width: w, height: h),
              let alpha = alphaBuffer(of: image)
        else { return nil }
        fillStone(ctx, width: w, height: h)

        // CG-rijen lopen van onder naar boven; de breuklijn zit (van boven
        // gemeten) op `fillBodySplit`.
        let splitY = CGFloat(h) * (1 - fillBodySplit)

        // Contour (buitenrand van het silhouet) onder de breuklijn.
        if let edge = silhouetteEdge(of: image) {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: CGFloat(w), height: splitY))
            ctx.setAlpha(0.6)
            ctx.draw(edge, in: CGRect(x: 0, y: 0, width: w, height: h))
            ctx.restoreGState()
        }

        // Stipple: dots op een raster waar het subject opaque is.
        let cell = max(3, min(w, h) / 40)
        let radius = CGFloat(cell) * 0.28
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.45)
        var y = cell / 2
        while CGFloat(y) < splitY {
            var x = cell / 2
            while x < w {
                // alphaBuffer is top-left georiënteerd; CG-y omrekenen.
                let row = h - 1 - y
                if alpha[row * w + x] > 128 {
                    ctx.fillEllipse(in: CGRect(
                        x: CGFloat(x) - radius, y: CGFloat(y) - radius,
                        width: radius * 2, height: radius * 2
                    ))
                }
                x += cell
            }
            y += cell
        }

        // Bovenste deel solid.
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: splitY, width: CGFloat(w), height: CGFloat(h) - splitY))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
        return ctx.makeImage()
    }

    /// Cutout op stone/stoneLight-checker — toont isolatie, zonder brand-lime.
    static func removeBackground(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = makeContext(width: w, height: h) else { return nil }
        let cell = max(8, min(w, h) / 10)
        for y in stride(from: 0, to: h, by: cell) {
            for x in stride(from: 0, to: w, by: cell) {
                let light = ((x / cell) + (y / cell)) % 2 == 0
                if light {
                    ctx.setFillColor(red: stoneLight.r, green: stoneLight.g, blue: stoneLight.b, alpha: 1)
                } else {
                    ctx.setFillColor(red: stone.r, green: stone.g, blue: stone.b, alpha: 1)
                }
                ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
            }
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - Primitives

    static func makeContext(width w: Int, height h: Int) -> CGContext? {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        return CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    static func fillStone(_ ctx: CGContext, width w: Int, height h: Int) {
        ctx.setFillColor(red: stone.r, green: stone.g, blue: stone.b, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }

    static func downscale(_ image: CGImage) -> CGImage? {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let ci = CIImage(cgImage: image)
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = ci
        lanczos.scale = Float(scale)
        lanczos.aspectRatio = 1
        guard let out = lanczos.outputImage else { return image }
        return render(out, extent: out.extent, like: image)
    }

    static func pixellate(_ image: CGImage, scale: Float) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let filter = CIFilter.pixellate()
        filter.inputImage = ci
        filter.center = CGPoint(x: ci.extent.midX, y: ci.extent.midY)
        filter.scale = scale
        guard let out = filter.outputImage?.cropped(to: ci.extent) else { return nil }
        return render(out, extent: ci.extent, like: image)
    }

    static func saturate(_ image: CGImage, amount: Float) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let filter = CIFilter.colorControls()
        filter.inputImage = ci
        filter.saturation = amount
        guard let out = filter.outputImage else { return nil }
        return render(out, extent: ci.extent, like: image)
    }

    static func gaussianBlur(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = CIImage(cgImage: image).clampedToExtent()
        filter.radius = Float(radius)
        guard let out = filter.outputImage else { return nil }
        return context.createCGImage(out, from: extent)
    }

    /// Witte buitenrand van het silhouet (morphology-gradient op het alpha-
    /// kanaal), met alpha = randsterkte.
    static func silhouetteEdge(of image: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let extent = ci.extent
        // Alpha → wit-met-alpha (premultiplied: rgb = a).
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = ci
        matrix.rVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        guard let mask = matrix.outputImage else { return nil }
        let gradient = CIFilter.morphologyGradient()
        gradient.inputImage = mask
        gradient.radius = Float(max(1, CGFloat(min(image.width, image.height)) / 160))
        guard let edge = gradient.outputImage?.cropped(to: extent) else { return nil }
        return render(edge, extent: extent, like: image)
    }

    /// Alpha-kanaal als top-left-georiënteerde buffer (rij 0 = bovenkant).
    static func alphaBuffer(of image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        let bpr = w * 4
        var pixels = [UInt8](repeating: 0, count: h * bpr)
        let ok: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        var alpha = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            // CG-bitmap rij 0 = onderkant → omdraaien naar top-left.
            let src = (h - 1 - y) * bpr
            for x in 0..<w {
                alpha[y * w + x] = pixels[src + x * 4 + 3]
            }
        }
        return alpha
    }

    static func splitHorizontal(left: CGImage, right: CGImage) -> CGImage? {
        let w = left.width, h = left.height
        guard right.width == w, right.height == h else { return nil }
        guard let ctx = makeContext(width: w, height: h) else { return nil }
        let mid = w / 2
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: mid, height: h))
        ctx.draw(left, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
        ctx.saveGState()
        ctx.clip(to: CGRect(x: mid, y: 0, width: w - mid, height: h))
        ctx.draw(right, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
        return ctx.makeImage()
    }

    static func composite(_ foreground: CGImage, over background: CGImage) -> CGImage? {
        let w = max(foreground.width, background.width)
        let h = max(foreground.height, background.height)
        guard let ctx = makeContext(width: w, height: h) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(background, in: rect)
        ctx.draw(foreground, in: rect)
        return ctx.makeImage()
    }

    private static func render(_ ci: CIImage, extent: CGRect, like image: CGImage) -> CGImage? {
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return context.createCGImage(
            ci.cropped(to: extent), from: extent, format: .RGBA8, colorSpace: colorSpace
        )
    }

    /// Sleutel op identiteit van de (kleine) bron + backdrop; de cache-entry
    /// houdt beide vast en checkt `===`, zodat adres-hergebruik na een
    /// portret-wissel geen verkeerde lagen teruggeeft.
    private static func cacheKey(action: Action, small: CGImage, backdrop: CGImage?) -> NSString {
        let s = Unmanaged.passUnretained(small).toOpaque()
        let b = backdrop.map { Unmanaged.passUnretained($0).toOpaque() }
        return "\(action.rawValue)|v15|\(s)|\(String(describing: b))|\(small.width)x\(small.height)" as NSString
    }

    // MARK: - Head / body crop

    /// Pixel-rect (top-left) rond gezicht + haar, anders de bovenkant van de cutout.
    static func headFocusRect(in image: CGImage) -> CGRect {
        headFocusRect(in: image, face: largestFaceRect(in: image))
    }

    static func headFocusRect(in image: CGImage, face: CGRect?) -> CGRect {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        if let face {
            let padX = face.width * 0.38
            let padTop = face.height * 0.55
            let padBottom = face.height * 0.4
            let rect = CGRect(
                x: face.minX - padX,
                y: face.minY - padTop,
                width: face.width + padX * 2,
                height: face.height + padTop + padBottom
            )
            return rect.intersection(bounds).integral
        }
        let box = opaqueBounds(of: image) ?? bounds
        let headH = max(box.height * 0.38, min(box.height, bounds.height * 0.4))
        let y = max(bounds.minY, box.minY - box.height * 0.04)
        return CGRect(x: box.minX, y: y, width: box.width, height: headH)
            .intersection(bounds).integral
    }

    /// Ruimere crop voor Fill in body: gezicht + schouders, zodat de breuklijn
    /// op `fillBodySplit` rond kin/hals valt en het "in te vullen" deel écht
    /// het lichaam is.
    static func bodyFocusRect(in image: CGImage, face: CGRect?) -> CGRect {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        if let face {
            let padX = face.width * 0.75
            let padTop = face.height * 0.45
            let padBottom = face.height * 1.0
            let rect = CGRect(
                x: face.minX - padX,
                y: face.minY - padTop,
                width: face.width + padX * 2,
                height: face.height + padTop + padBottom
            )
            return rect.intersection(bounds).integral
        }
        let box = opaqueBounds(of: image) ?? bounds
        let h = min(box.height, box.width * 1.15)
        return CGRect(x: box.minX, y: box.minY, width: box.width, height: h)
            .intersection(bounds).integral
    }

    /// Vierkante crop mét alpha (geen stone-vulling): de plaat/`compositeOverStone`
    /// vult transparant later, zodat dezelfde crop ook als masker dient.
    static func zoomTo(_ image: CGImage, source: CGRect) -> CGImage {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let src = source.integral.intersection(bounds)
        guard src.width >= 2, src.height >= 2,
              let piece = image.cropping(to: src)
        else { return image }
        let side = max(piece.width, piece.height)
        guard let ctx = makeContext(width: side, height: side) else { return image }
        let x = (CGFloat(side) - CGFloat(piece.width)) / 2
        let y = (CGFloat(side) - CGFloat(piece.height)) / 2
        ctx.draw(piece, in: CGRect(x: x, y: y, width: CGFloat(piece.width), height: CGFloat(piece.height)))
        return ctx.makeImage() ?? image
    }

    /// Rect in bron-pixels (top-left) → genormaliseerd (0…1) in de vierkante
    /// `zoomTo`-crop van `crop` met zijde `side`.
    static func normalize(_ rect: CGRect, crop: CGRect, side: Int) -> CGRect {
        guard side > 0 else { return .zero }
        let s = CGFloat(side)
        let src = crop.integral
        let offX = (s - src.width) / 2
        let offY = (s - src.height) / 2
        return CGRect(
            x: (rect.minX - src.minX + offX) / s,
            y: (rect.minY - src.minY + offY) / s,
            width: rect.width / s,
            height: rect.height / s
        )
    }

    static func largestFaceRect(in image: CGImage) -> CGRect? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        _ = try? handler.perform([request])
        guard let bb = request.results?.max(by: {
            $0.boundingBox.width * $0.boundingBox.height
                < $1.boundingBox.width * $1.boundingBox.height
        })?.boundingBox else { return nil }
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        return CGRect(
            x: bb.origin.x * w,
            y: (1 - bb.origin.y - bb.height) * h,
            width: bb.width * w,
            height: bb.height * h
        )
    }

    static func opaqueBounds(of image: CGImage, threshold: UInt8 = 8) -> CGRect? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        let bpr = w * 4
        var pixels = [UInt8](repeating: 0, count: h * bpr)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let stepX = max(1, w / 64)
        let stepY = max(1, h / 64)
        var minX = w, minY = h, maxX = -1, maxY = -1
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                if pixels[y * bpr + x * 4 + 3] > threshold {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
                x += stepX
            }
            y += stepY
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        minX = max(0, minX - (stepX - 1))
        minY = max(0, minY - (stepY - 1))
        maxX = min(w - 1, maxX + stepX - 1)
        maxY = min(h - 1, maxY + stepY - 1)
        // Bitmap-rij 0 is de onderkant; CGImage.cropping is top-left.
        let top = h - 1 - maxY
        return CGRect(
            x: minX, y: top,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }
}

private final class CachedLayers: NSObject {
    let layers: EnhanceTilePreview.Layers
    /// Identiteits-ankers (zie `cacheKey`).
    let small: CGImage
    let backdrop: CGImage?
    init(_ layers: EnhanceTilePreview.Layers, small: CGImage, backdrop: CGImage?) {
        self.layers = layers
        self.small = small
        self.backdrop = backdrop
    }
}

private final class CachedPrepared: NSObject {
    let prepared: EnhanceTilePreview.PreparedSubject
    let subject: CGImage
    init(_ prepared: EnhanceTilePreview.PreparedSubject, subject: CGImage) {
        self.prepared = prepared
        self.subject = subject
    }
}
