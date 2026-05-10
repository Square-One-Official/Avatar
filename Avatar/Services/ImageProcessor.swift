import Foundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreML
import AppKit

enum ImageProcessorError: Error {
    case noSubjectFound
    case maskGenerationFailed
    case cgImageCreationFailed
}

struct ProcessedSubject {
    /// Cutout image (RGBA with transparent background) sized to the source image.
    let cutout: CGImage
    /// Face rect in cutout image coordinates (origin top-left, in pixels).
    /// nil if no face was detected.
    let faceRect: CGRect?
    /// Midpoint between the two eyes in cutout-pixel coordinates (top-left origin).
    /// nil when face-landmark detection couldn't locate both eyes.
    let eyeCenter: CGPoint?
    /// Pixel distance between left- and right-eye centres.  A much more stable
    /// metric than face-rect height for normalising head size across people
    /// (beards, hair, jaw shape don't affect it).
    let interEyeDistance: CGFloat?
    /// Y coordinate (top-left origin, pixels) of the lowest visible body content.
    /// Determined by body-pose detection or alpha-channel scan.
    let bodyBottomY: CGFloat
}

/// Intermediate result from combined face-rect + landmark detection.
struct FaceDetectionResult {
    let faceRect: CGRect           // image pixels, origin top-left
    let eyeCenter: CGPoint?        // midpoint between eyes, pixels, top-left
    let interEyeDistance: CGFloat?  // pixel distance between eye centres
}

enum ImageProcessor {
    static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Linear-sRGB working-space context used **only** by `subjectLiftV2`.
    /// All matte arithmetic — guided filter, gaussian blur, multiply
    /// composites, the custom blur-fusion / colour-attenuation kernels — is
    /// mathematically correct only in linear light. Rendering through this
    /// context applies the sRGB→linear transform on input, runs every filter
    /// in linear, then applies linear→sRGB on output, so a 50/50 blend at a
    /// hair edge is the *physical* 50/50 instead of the perceptually-darker
    /// gamma-encoded one. 16-bit half-float intermediate avoids 8-bit banding
    /// in the soft alpha around wispy strands.
    /// `subjectLiftV1`, `birefnetLift`, `magicRetouch`, and the orientation /
    /// PNG helpers stay on the default-sRGB `ciContext` so we don't perturb
    /// downstream features that were tuned against it.
    private static let liftContext: CIContext = {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let srgb   = CGColorSpace(name: CGColorSpace.sRGB)!
        return CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: linear,
            .outputColorSpace: srgb,
            .workingFormat: NSNumber(value: CIFormat.RGBAh.rawValue),
        ])
    }()

    /// Removes the background using Vision's foreground instance mask. Public
    /// entry point used by the import pipeline. Defaults to `subjectLiftV2`
    /// (linear-sRGB context, pinned Vision revisions, adaptive resolution,
    /// extended hair zone, alpha gamma, full-silhouette colour
    /// decontamination) — accepted after a fixture-set A/B against V1.
    /// V1 stays available behind an explicit `subjectLiftV2 = false` opt-out
    /// so we can revert instantly if a real-world regression surfaces. V1
    /// gets removed in a follow-up once V2 has been default-on for a
    /// release cycle without bug reports.
    static func subjectLift(image: CGImage) throws -> CGImage {
        // `object(forKey:) as? Bool` distinguishes "not set" (→ true, V2
        // default) from "set to false" (→ V1 opt-out). `bool(forKey:)`
        // would conflate the two.
        let useV2 = (UserDefaults.standard.object(forKey: "subjectLiftV2") as? Bool) ?? true
        if useV2 {
            return try subjectLiftV2(image: image)
        }
        return try subjectLiftV1(image: image)
    }

    /// V1 — original Apple Vision pipeline, **bit-for-bit identical** to the
    /// pre-split implementation. Kept around behind the `subjectLiftV2` flag
    /// so the EdgeBenchmark harness can A/B against V2, and so we can revert
    /// instantly if V2 regresses on real-world imports.
    ///
    /// Uses `VNGenerateForegroundInstanceMaskRequest` (the same "Subject
    /// Lift" model the Photos app uses, macOS 14+) and refines the matte
    /// with `VNGeneratePersonSegmentationRequest(.accurate)` for smoother
    /// hair edges. Falls back to the raw foreground mask when person
    /// segmentation has nothing useful (e.g. non-person subjects).
    static func subjectLiftV1(image: CGImage) throws -> CGImage {
        let foreground = VNGenerateForegroundInstanceMaskRequest()
        let personSeg = VNGeneratePersonSegmentationRequest()
        personSeg.qualityLevel = .accurate
        personSeg.outputPixelFormat = kCVPixelFormatType_OneComponent8
        // Face detection is co-loaded so `refineAlphaMatte` can build a
        // spatial "hair zone" that surgically softens only head/beard
        // silhouette edges. Body and face skin remain on the strict path.
        let faceReq = VNDetectFaceRectanglesRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        // Run in one perform() so Vision can share resources; person seg
        // and face detection are both allowed to fail without aborting.
        try handler.perform([foreground, personSeg, faceReq])

        guard let fgObservation = foreground.results?.first else {
            throw ImageProcessorError.noSubjectFound
        }

        // 1. Grab the foreground instance mask as a soft grayscale CIImage.
        let fgMaskPB = try fgObservation.generateScaledMaskForImage(
            forInstances: fgObservation.allInstances,
            from: handler
        )
        let fgMaskRaw = CIImage(cvPixelBuffer: fgMaskPB)
        let originalCI = CIImage(cgImage: image)
        let extent = originalCI.extent

        // Vision returns masks at the model's native resolution. Scale them up
        // (and pin the extent) so every later composite aligns with the source.
        let fgMask = scaleMaskToExtent(fgMaskRaw, extent: extent)

        // 2. Person segmentation matte — optional refinement for hair edges.
        let personMask: CIImage? = {
            guard let buffer = (personSeg.results?.first)?.pixelBuffer else { return nil }
            return scaleMaskToExtent(CIImage(cvPixelBuffer: buffer), extent: extent)
        }()

        // 3. Largest face rect (image-pixel coords, top-left origin). nil
        //    when no face was found — the matte refinement falls back to
        //    the strict-everywhere pipeline so non-portraits behave as today.
        let faceRect = largestFaceRect(observations: faceReq.results,
                                       imageSize: extent.size)

        // 4. Combine the masks into a single refined alpha matte.
        //    Inside the hair zone (above the head + around the chin) we
        //    keep the soft guided-filter matte so fine hair/beard strands
        //    survive against background. Outside the zone, and anywhere
        //    away from the silhouette edge, we use the existing strict
        //    matte so shoulders/shirt/face remain crisp and untouched.
        let refined = refineAlphaMatte(foreground: fgMask, personSeg: personMask,
                                       guide: originalCI, faceRect: faceRect,
                                       extent: extent)

        // 5. Foreground RGB. By default we use the original photo so the
        //    cutout colours match the source exactly. When a hair zone
        //    was detected we additionally run blur-fusion (Forte & Pitié,
        //    ICIP 2021) to recover the *unmixed* foreground colour at
        //    semi-transparent strands — without this, the original photo
        //    background bleeds through because each hair-edge pixel is
        //    `α·F + (1−α)·B_old`. The decontaminated RGB is then mixed in
        //    only inside the hair edge ring, so face/skin/shoulder colours
        //    stay byte-for-byte identical to the source.
        let foregroundRGB: CIImage = {
            guard let softAlpha = refined.softAlpha,
                  let region = refined.decontamRegion else {
                return originalCI
            }
            // Aggressive blur-fusion radii: portraits typically fill the
            // frame, so the standard 90px first-pass is barely 15% of the
            // head — not enough to reliably gather solid (α≈1) hair pixels
            // for the F_hat estimate. 180px gives enough range to sample
            // interior hair colour from far enough away that blonde tones
            // dominate over edge-contaminated samples. 8px second pass
            // recovers local detail.
            let unmixed = refineForeground(source: originalCI, alpha: softAlpha,
                                            extent: extent,
                                            pass1Radius: 180, pass2Radius: 8)
            return unmixed.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: originalCI,  // region=0 → original
                "inputMaskImage": region                 // region=1 → unmixed
            ]).cropped(to: extent)
        }()

        // 6. Re-composite the (possibly-decontaminated) RGB with the new
        //    alpha. `CIMaskToAlpha` turns the grayscale matte into an
        //    alpha channel so `CIBlendWithMask` reads opacity correctly
        //    regardless of whether Vision gave us a luminance- or alpha-
        //    coded buffer.
        let clearBG = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: extent)
        let alphaMatte = refined.matte.applyingFilter("CIMaskToAlpha")
        let composed = foregroundRGB.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": clearBG,
            "inputMaskImage": alphaMatte
        ]).cropped(to: extent)

        let outputCS = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cg = ciContext.createCGImage(composed, from: extent, format: .RGBA8, colorSpace: outputCS) else {
            throw ImageProcessorError.maskGenerationFailed
        }
        return cg
    }

    /// V2 — same algorithmic skeleton as V1 with four targeted upgrades:
    ///
    /// 1. **Linear-sRGB working colour space** via `liftContext`. Every CI
    ///    filter (guided filter, gaussian blur, multiply composites, the
    ///    blur-fusion + colour-attenuation kernels) does its arithmetic in
    ///    physically linear light. Without this, a hair-edge 50/50 blend
    ///    reads darker than the physical 50/50 because sRGB is gamma-encoded.
    /// 2. **Pinned Vision request revisions** so future macOS doesn't silently
    ///    re-tune behaviour. 16-bit half person-seg buffer for smoother soft
    ///    alpha at the edge band.
    /// 3. **Adaptive Vision input resolution** — tiny inputs (<1500 px) get
    ///    upscaled before Vision sees them so the mask isn't chunky;
    ///    monstrous inputs (>4096 px) get downsampled because Vision's mask
    ///    network has fixed feature size and the extra cost buys nothing.
    /// 4. **Extended hair zone** (via person-seg) and **soft-matte gamma lift**
    ///    inside `refineAlphaMatte`, so long hair / ponytails / afros that
    ///    fall outside the radial-gradient ellipses still get the soft-matte
    ///    treatment, and wispy strands get pulled above the perceptual floor.
    ///
    /// Compositing happens against the *original* image regardless of what
    /// resolution Vision saw — Vision only ever sees the resized version, the
    /// final alpha is up-/down-sampled back to the source extent, and colour
    /// fidelity comes from the unmodified source pixels.
    static func subjectLiftV2(image: CGImage) throws -> CGImage {
        let originalCI = CIImage(cgImage: image)
        let extent = originalCI.extent

        // 1. Adaptive Vision input — see `visionInput` for the policy.
        let (visionImage, _) = visionInput(from: image)

        // 2. Vision requests with pinned revisions + 16-bit half person-seg.
        let foreground = VNGenerateForegroundInstanceMaskRequest()
        foreground.revision = VNGenerateForegroundInstanceMaskRequestRevision1

        let personSeg = VNGeneratePersonSegmentationRequest()
        personSeg.revision = VNGeneratePersonSegmentationRequestRevision1
        personSeg.qualityLevel = .accurate
        // 16-bit half retains soft-edge precision the 8-bit V1 buffer
        // discards. Negligible memory cost vs the perceptual win on the
        // edge-band where continuous α actually matters.
        personSeg.outputPixelFormat = kCVPixelFormatType_OneComponent16Half

        let faceReq = VNDetectFaceRectanglesRequest()
        faceReq.revision = VNDetectFaceRectanglesRequestRevision3

        let handler = VNImageRequestHandler(cgImage: visionImage, options: [:])
        try handler.perform([foreground, personSeg, faceReq])

        guard let fgObservation = foreground.results?.first else {
            throw ImageProcessorError.noSubjectFound
        }

        // 3. Foreground instance mask → CIImage at original extent.
        let fgMaskPB = try fgObservation.generateScaledMaskForImage(
            forInstances: fgObservation.allInstances,
            from: handler
        )
        let fgMaskRaw = CIImage(cvPixelBuffer: fgMaskPB)
        let fgMask = scaleMaskToExtent(fgMaskRaw, extent: extent)

        // 4. Optional person-seg refinement matte at original extent.
        let personMask: CIImage? = {
            guard let buffer = (personSeg.results?.first)?.pixelBuffer else { return nil }
            return scaleMaskToExtent(CIImage(cvPixelBuffer: buffer), extent: extent)
        }()

        // 5. Largest face rect in original-image pixels (top-left origin).
        //    Vision face boundingBox is normalized [0,1] so the resize doesn't
        //    perturb the result.
        let faceRect = largestFaceRect(observations: faceReq.results,
                                       imageSize: extent.size)

        // 6. Refinement options scaled to source size. The 2048 pivot keeps
        //    the band visually consistent — a 4032×3024 phone photo gets
        //    ~40px, a 1024×1024 preview keeps ~20px, a 6048×4032 export
        //    pegs at ~60px which is wide enough to encompass long hair
        //    strands without bleeding into clean shoulder lines.
        let longSide = max(extent.width, extent.height)
        let scale = max(1.0, longSide / 2048.0)
        let options = RefinementOptions(
            edgeBandRadius: 20.0 * scale,
            useExtendedHairZone: true,
            softMatteGamma: 0.85,
            widerDecontamination: true
        )
        let refined = refineAlphaMatte(foreground: fgMask, personSeg: personMask,
                                        guide: originalCI, faceRect: faceRect,
                                        extent: extent, options: options)

        // 7. Foreground RGB. Same blur-fusion decontamination as V1 — the
        //    math works regardless of which mask the soft alpha came from.
        let foregroundRGB: CIImage = {
            guard let softAlpha = refined.softAlpha,
                  let region = refined.decontamRegion else {
                return originalCI
            }
            let unmixed = refineForeground(source: originalCI, alpha: softAlpha,
                                            extent: extent,
                                            pass1Radius: 180, pass2Radius: 8)
            return unmixed.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: originalCI,
                "inputMaskImage": region
            ]).cropped(to: extent)
        }()

        // 8. Composite refined RGB + new alpha.
        let clearBG = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: extent)
        let alphaMatte = refined.matte.applyingFilter("CIMaskToAlpha")
        let composed = foregroundRGB.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": clearBG,
            "inputMaskImage": alphaMatte
        ]).cropped(to: extent)

        // Render through the linear-sRGB context so every filter above ran
        // in linear light.
        let outputCS = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cg = liftContext.createCGImage(composed, from: extent,
                                                  format: .RGBA8,
                                                  colorSpace: outputCS) else {
            throw ImageProcessorError.maskGenerationFailed
        }
        return cg
    }

    /// Returns the image Vision should see, plus the scale that was applied
    /// (for record-keeping; the mask scaling at the end always targets the
    /// **original** extent so callers don't need to compose anything against
    /// this scale themselves).
    ///
    /// Policy: Vision's instance-mask network has a fixed internal feature
    /// resolution. Inputs much smaller than that produce a chunky upscaled
    /// mask; inputs much larger waste wall-time without recovering detail.
    /// 1500–4096 px on the long edge is the sweet spot we've observed.
    private static func visionInput(from cg: CGImage) -> (image: CGImage, scale: CGFloat) {
        let longEdge = max(cg.width, cg.height)
        let target: Int
        switch longEdge {
        case ..<1500:  target = 2048
        case ..<4097:  target = longEdge   // pass through
        default:       target = 4096
        }
        if target == longEdge { return (cg, 1.0) }

        let scale = CGFloat(target) / CGFloat(longEdge)
        let newW = Int(round(CGFloat(cg.width) * scale))
        let newH = Int(round(CGFloat(cg.height) * scale))
        let outRect = CGRect(x: 0, y: 0, width: newW, height: newH)

        // CILanczosScaleTransform is the standard high-quality up/down
        // sampler in Core Image — better than CIAffineTransform for both
        // upscale (sharper) and downscale (less aliasing).
        let ci = CIImage(cgImage: cg).applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1.0
        ])
        let cs = cg.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        // Render through the linear-sRGB context so the resample is
        // colour-correct. Falling back to the original on render failure
        // keeps Vision running rather than aborting the whole import.
        guard let resized = liftContext.createCGImage(ci, from: outRect,
                                                       format: .RGBA8,
                                                       colorSpace: cs) else {
            return (cg, 1.0)
        }
        return (resized, scale)
    }

    /// Subject lift via the optional downloadable BiRefNet_lite-matting
    /// CoreML model. Produces a real continuous-α matte that handles wispy
    /// hair edges Apple Vision can't (Vision is a segmentation network with
    /// near-binary alpha; BiRefNet is a matting network trained for the
    /// kind of flowing-hair / curly-flyaway edges V2 still bleeds on).
    ///
    /// Caller is responsible for gating on `ModelManager.cachedModelURL()
    /// != nil` — this function will throw if the model file is missing or
    /// malformed. ImportFlow handles the fallback to V2 when the model
    /// isn't present.
    ///
    /// Performance: ~1-2s on M1 at 1024x1024 (fp16, ANE/GPU dispatch via
    /// `computeUnits = .all`). MLModel loading is amortized via
    /// `cachedDownloadedModel` — first call after a fresh launch pays
    /// ~200ms cold-start, subsequent calls are inference-only. Cache is
    /// invalidated when the URL changes (e.g. user re-downloads after a
    /// `modelVersion` bump).
    static func subjectLiftDownloaded(image: CGImage, modelURL: URL) throws -> CGImage {
        let originalCI = CIImage(cgImage: image)
        let extent = originalCI.extent

        // 1. Load (or reuse cached) MLModel.
        let model = try loadOrReuseDownloadedModel(at: modelURL)

        // 2. Resize source to 1024×1024 — BiRefNet was trained at this
        //    fixed resolution. The conversion script bakes ImageNet
        //    normalization into the model's preprocessing, so the buffer
        //    we hand over carries plain RGB 0-255.
        let inputSize: CGFloat = 1024
        let scaleX = inputSize / extent.width
        let scaleY = inputSize / extent.height
        let resized = originalCI
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(x: 0, y: 0, width: inputSize, height: inputSize))
        guard let inputBuffer = createPixelBuffer(from: resized,
                                                    size: CGSize(width: inputSize, height: inputSize)) else {
            throw ImageProcessorError.maskGenerationFailed
        }

        // 3. Inference.
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input": MLFeatureValue(pixelBuffer: inputBuffer)
        ])
        let prediction = try model.prediction(from: input)

        // 4. Extract the alpha matte. Output naming varies: a custom
        //    converter can name it cleanly ("alpha"), but a prebuilt
        //    torch→CoreML model (e.g. john-rocky's IS-Net) often emits
        //    opaque tensor names like `var_4090`. Try known aliases
        //    first, then scan every output for the first image-typed
        //    feature, then fall through to the MultiArray scan. Logged
        //    with the resolved name so misnamed outputs are visible
        //    in the log without changing code.
        let candidateNames = ["alpha", "output", "sigmoid_output", "out"]
        var maskCI: CIImage?
        var resolvedName: String?
        for name in candidateNames {
            if let feature = prediction.featureValue(for: name),
               let buffer = feature.imageBufferValue {
                maskCI = CIImage(cvPixelBuffer: buffer)
                resolvedName = name
                break
            }
        }
        if maskCI == nil {
            for name in prediction.featureNames {
                if let feature = prediction.featureValue(for: name),
                   let buffer = feature.imageBufferValue {
                    maskCI = CIImage(cvPixelBuffer: buffer)
                    resolvedName = "\(name) (scan)"
                    break
                }
            }
        }
        if maskCI == nil {
            maskCI = extractMaskFromMultiArray(prediction: prediction)
            resolvedName = "MultiArray"
        }
        guard let rawMask = maskCI else {
            throw ImageProcessorError.maskGenerationFailed
        }
        dlog("[Downloaded] Got mask via '\(resolvedName ?? "?")'")

        // 5. Scale mask back to source extent. BiRefNet's output is the
        //    same continuous-α we want — no need for the multi-mask
        //    union / hair zone gating dance V2 needs to coax a soft matte
        //    out of Vision's near-binary mask.
        let mask = scaleMaskToExtent(rawMask, extent: extent)

        // 6. Light guided-filter refinement to snap the matte onto real
        //    luminance edges. Loose epsilon — the matting model's output
        //    is already edge-aware, we're just cleaning up sub-pixel
        //    scaling artifacts from step 5.
        let guidedRaw = mask.applyingFilter("CIGuidedFilter", parameters: [
            "inputGuideImage": originalCI,
            kCIInputRadiusKey: 2.0,
            "inputEpsilon": 0.01
        ]).cropped(to: extent)

        // 6b. Tighten the silhouette by ~3px to clip the warm-halo ring.
        //     ORMBG's matte tends to include the outermost pixels of
        //     the silhouette at α=1 even when they're really
        //     background-edge pixels with light bounced off the
        //     subject — those carry a tint of the original
        //     background, which composited over a new backdrop reads
        //     as a coloured glow. The pixels are at α=1 so blur-fusion
        //     can't fix them; the only correct move is to clip them
        //     out of the cutout entirely. Small Gaussian blur after
        //     the morphology gives the new edge a sub-pixel feather
        //     so the cutout doesn't look hard-cut. Cost: hair
        //     flyaways thinner than ~3px get lost — acceptable for
        //     ORMBG's portrait-trained domain (the model already
        //     coalesces wisps into the main hair mass).
        let guided = guidedRaw
            .applyingFilter("CIMorphologyMinimum", parameters: [
                kCIInputRadiusKey: 3.0
            ])
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: 1.0
            ])
            .cropped(to: extent)

        // 7. Blur-fusion RGB decontamination (V2 win, same algorithm).
        //    Recovers unmixed foreground colour at semi-transparent
        //    pixels so wispy strands don't carry the original
        //    background through to the new backdrop. Matches V2's
        //    portrait-tuned radii (180/8) — the earlier 90/6 wasn't
        //    sampling far enough into solid hair pixels for the F̂
        //    estimate, leaving warm-tinted halos around curly hair
        //    edges when the original background was light/warm. 180px
        //    first pass reaches reliably-α=1 pixels for typical head
        //    sizes; 8px second pass cleans up local detail.
        let refinedFG = refineForeground(source: originalCI, alpha: guided,
                                          extent: extent,
                                          pass1Radius: 180, pass2Radius: 8)

        // 8. Composite refined RGB + alpha.
        let clearBG = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: extent)
        let alphaMatte = guided.applyingFilter("CIMaskToAlpha")
        let composed = refinedFG.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": clearBG,
            "inputMaskImage": alphaMatte
        ]).cropped(to: extent)

        // 9. Render through the linear-sRGB context so all the filter
        //    math above runs in physical light — same correctness win
        //    V2 applies, applied here too.
        let outputCS = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cg = liftContext.createCGImage(composed, from: extent,
                                                  format: .RGBA8,
                                                  colorSpace: outputCS) else {
            throw ImageProcessorError.maskGenerationFailed
        }
        return cg
    }

    // MARK: - MLModel cache (downloaded engine)

    /// `MLModel` itself is thread-safe to *use* once loaded; only the
    /// cache lookup needs a lock. Loading is the expensive part (~200ms),
    /// so the cache is critical for the multi-cutout case (re-imports,
    /// reprocess, etc.). Keyed by URL so a `modelVersion` bump that
    /// changes the install path invalidates the cache automatically.
    private static let downloadedModelCacheLock = NSLock()
    nonisolated(unsafe) private static var cachedDownloadedModel: (url: URL, model: MLModel)?

    private static func loadOrReuseDownloadedModel(at url: URL) throws -> MLModel {
        downloadedModelCacheLock.lock()
        if let cached = cachedDownloadedModel, cached.url == url {
            let m = cached.model
            downloadedModelCacheLock.unlock()
            return m
        }
        downloadedModelCacheLock.unlock()

        // Load outside the lock — model compilation / load can be slow
        // and we don't want to serialize callers that arrive while a
        // cold-start is in flight on a different URL (rare, but cheap
        // to handle correctly).
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let loaded = try MLModel(contentsOf: url, configuration: config)

        downloadedModelCacheLock.lock()
        cachedDownloadedModel = (url, loaded)
        downloadedModelCacheLock.unlock()
        return loaded
    }

    /// V2 hair zone: union of the radial-gradient `baseZone` (good for typical
    /// short hair / beards) with a person-seg-derived zone (catches long
    /// hair, side ponytails, afros, braids, flying strands — anything that
    /// falls outside the crown / beard ellipses).
    ///
    /// Earlier revisions clipped the person-seg zone to "above chin + face
    /// height" out of an abundance of caution about the soft matte
    /// touching shoulders. That cutoff dropped attenuation for any hair
    /// flowing below it (long hair, the trailing tips of windswept hair
    /// in landscape portraits) — exactly the cases the user still saw
    /// background bleeding through. The cutoff is no longer needed because
    /// (a) soft-matte selection already gates on `edgeBand × hairZone`, so
    /// only silhouette pixels are touched, and (b) at the body interior
    /// α=1 the colour-attenuation kernel is a mathematical no-op.
    ///
    /// Dilation widened from 0.6× to 1.0× face width so the zone reaches
    /// the flying strand tips that sit a face-width past the silhouette.
    /// Falls back to `baseZone` when person-seg isn't available so non-
    /// portrait subjects behave the same as V1.
    private static func extendedHairZone(
        baseZone: CIImage,
        personSeg: CIImage?,
        faceRect: CGRect?,
        extent: CGRect
    ) -> CIImage {
        guard let personSeg, let faceRect else { return baseZone }

        let dilateR = max(8.0, faceRect.width * 1.0)
        let dilatedPS = personSeg.applyingFilter("CIMorphologyMaximum", parameters: [
            kCIInputRadiusKey: dilateR
        ]).cropped(to: extent)

        // Lighten = max(baseZone, dilatedPS) — pixel is "in hair zone" if
        // EITHER source says so.
        return baseZone.applyingFilter("CILightenBlendMode", parameters: [
            kCIInputBackgroundImageKey: dilatedPS
        ]).cropped(to: extent)
    }

    /// Combines the foreground instance mask with the (optional) person-segmentation
    /// matte and polishes the alpha channel so hair and soft edges survive while
    /// background-colour fringing is knocked back.
    ///
    /// The `guide` parameter is the original RGB image. It drives a guided-filter
    /// pass that snaps the soft matte boundary onto real luminance edges in the
    /// photo — recovering fine hair strands that morphology alone would clip.
    /// Output of the matte refinement: the final alpha matte the composite
    /// uses, plus optional context the caller needs to surgically
    /// decontaminate hair RGB.
    ///
    /// • `softAlpha` is the continuous guided matte (used as the alpha
    ///   input for blur-fusion).
    /// • `decontamRegion` is a wider mask covering every pixel inside the
    ///   hair zone with any visible alpha — this is what scopes the RGB
    ///   decontamination, so flying-out strands that sit beyond the matte-
    ///   blend ring still get unmixed colour.
    ///
    /// Both are nil when no face was detected.
    struct RefinedMatte {
        let matte: CIImage
        let softAlpha: CIImage?
        let decontamRegion: CIImage?
    }

    /// Knobs for the V2 refinement path. Defaulting these to the V1 numerics
    /// keeps `subjectLiftV1` bit-for-bit identical when it calls the shared
    /// `refineAlphaMatte` — V2 passes overrides for the three things it
    /// changes (edge-band radius scales with source size; the hair zone is
    /// extended via person-seg to cover long hair / ponytails / afros; the
    /// soft matte gets a small gamma lift to recover wispy strands above the
    /// perceptual floor in linear-sRGB).
    struct RefinementOptions {
        /// Morphology radius for the edge band (dilate − erode of `combined`).
        /// V1 hard-codes 20.0; V2 scales by `max(longEdge / 2048.0, 1.0)` so a
        /// 4K phone photo gets a wider band than a 1024-px preview.
        var edgeBandRadius: CGFloat = 20.0
        /// When true, union the radial-gradient hair zone with a person-seg-
        /// derived zone (dilated, clipped to above the chin) so the soft-
        /// matte treatment reaches hair the radial gradients miss.
        var useExtendedHairZone: Bool = false
        /// Optional `inputPower` for a `CIGammaAdjust` applied to the soft
        /// matte before the edge-band blend. < 1 lifts wispy strands; only
        /// safe in linear-sRGB working space (V2). nil = no adjust.
        var softMatteGamma: Float? = nil
        /// V2: drop the hair-zone gate on the decontamination region so the
        /// blur-fusion RGB unmixing runs wherever alpha is non-trivially
        /// partial — long hair past the shoulder, flyaways outside the
        /// radial-gradient zone, glasses arms, anything wispy. Without this,
        /// pixels at α=0.4 outside the hair zone keep their original
        /// `α·F + (1−α)·B_old` RGB and ghost the source background through
        /// the new backdrop. Safe at α≈1: blur-fusion math collapses to
        /// `F = I` so body/face/shoulders are byte-for-byte unchanged.
        var widerDecontamination: Bool = false
    }

    private static func refineAlphaMatte(
        foreground: CIImage,
        personSeg: CIImage?,
        guide: CIImage,
        faceRect: CGRect?,
        extent: CGRect,
        options: RefinementOptions = RefinementOptions()
    ) -> RefinedMatte {
        // Union with person segmentation (max) — hair strands the foreground
        // mask chops off usually survive in the person matte. We gate the
        // union through a slightly dilated foreground mask so person-seg
        // false positives elsewhere in the frame don't sneak in.
        var combined = foreground
        if let personSeg = personSeg {
            let gate = foreground.applyingFilter("CIMorphologyMaximum", parameters: [
                kCIInputRadiusKey: 8.0
            ]).cropped(to: extent)
            let gatedPerson = personSeg.applyingFilter("CIDarkenBlendMode", parameters: [
                kCIInputBackgroundImageKey: gate
            ]).cropped(to: extent)
            combined = combined.applyingFilter("CILightenBlendMode", parameters: [
                kCIInputBackgroundImageKey: gatedPerson
            ]).cropped(to: extent)
        }

        // ── Edge-aware refinement via guided filter ──────────────────────
        // The guided filter (He et al. 2010) is a local linear model that
        // transfers edge structure from the guide (original photo) into the
        // matte. Where the photo has a strong luminance edge (hair strand vs
        // background) the filter preserves or sharpens the matte boundary;
        // in smooth regions it acts as an edge-preserving blur.
        //
        // • radius  — neighbourhood size in pixels; 8px covers a few hair
        //             strands without over-smoothing the silhouette.
        // • epsilon — regularisation; small values (1e-4) make the filter
        //             follow guide edges very tightly (good for crisp hair).
        let guided = combined.applyingFilter("CIGuidedFilter", parameters: [
            "inputGuideImage": guide,
            kCIInputRadiusKey: 8.0,
            "inputEpsilon": 0.0001
        ]).cropped(to: extent)

        // ── Strict matte (existing behaviour) ────────────────────────────
        // Tighten the edge: erode by <1px to kill background-colour bleed,
        // then a gentle blur smooths aliasing, then a contrast curve makes
        // the matte commit (either hair or transparent — no muddy halo).
        // This produces clean shoulder/shirt/face boundaries and is what
        // the rest of the silhouette continues to use.
        let eroded = guided.applyingFilter("CIMorphologyMinimum", parameters: [
            kCIInputRadiusKey: 0.7
        ])
        let blurred = eroded.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: 0.6
        ])
        let contrast = blurred.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1.15, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1.15, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1.15, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1.15),
            "inputBiasVector": CIVector(x: -0.05, y: -0.05, z: -0.05, w: -0.05)
        ])
        // Clamp to [0,1] — the contrast boost above can push opaque regions
        // above 1.0 (e.g. 1.0*1.15-0.05 = 1.10). Without clamping, that
        // >1.0 matte value flows into CIBlendWithMask and multiplies the
        // original RGB by >1, causing visible overexposure of the cutout.
        let strictMatte = contrast.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ]).cropped(to: extent)

        // Without a face rect we have no reliable way to delineate the
        // hair zone — return the strict matte everywhere (= today's
        // behaviour). This keeps non-portrait subjects untouched.
        guard let faceRect = faceRect else {
            return RefinedMatte(matte: strictMatte, softAlpha: nil, decontamRegion: nil)
        }

        // ── Soft matte (hair/beard zone only) ────────────────────────────
        // The guided matte preserves continuous alpha — fine hair strands
        // that the strict matte's erosion + 1.15·α-0.05 contrast curve
        // would zap (anything below α≈0.043) survive here. We intentionally
        // skip both transformations to keep the soft falloff intact.
        let softMatteRaw = guided

        // Hair-colour alpha attenuation. Apple's mask treats inter-curl
        // openings inside the head silhouette as foreground (α≈0.4-0.8)
        // even when the actual pixel is the original studio bg colour —
        // composing those pixels makes the old background bleed through
        // the new backdrop. We sample local hair colour from confidently-
        // solid pixels (combined > 0.95, restricted to the hair zone) and
        // attenuate alpha for pixels whose RGB doesn't match. Solid skin
        // / body are protected by gating on softMatte<0.95 inside the
        // kernel.
        let baseHairZone = buildHairZoneMask(faceRect: faceRect, extent: extent)
        let hairZone = options.useExtendedHairZone
            ? extendedHairZone(baseZone: baseHairZone,
                               personSeg: personSeg,
                               faceRect: faceRect,
                               extent: extent)
            : baseHairZone
        let solidHairAmplified = combined.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 20, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 20, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 20, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 20),
            "inputBiasVector": CIVector(x: -19, y: -19, z: -19, w: -19)
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ]).cropped(to: extent)
        let hairOnlyMask = solidHairAmplified.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: hairZone
        ]).cropped(to: extent)
        let hairOnlyRGB = guide.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: hairOnlyMask
        ]).cropped(to: extent)
        let hairBlur = hairOnlyRGB.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: 80.0
        ]).cropped(to: extent)
        let maskBlur = hairOnlyMask.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: 80.0
        ]).cropped(to: extent)
        let softMatteAttenuated = colorAttenuationKernel?.apply(
            extent: extent,
            arguments: [guide, hairBlur, maskBlur, softMatteRaw, hairZone]
        )?.cropped(to: extent) ?? softMatteRaw

        // Optional gamma lift on the soft matte. Only safe in linear-sRGB
        // working space — V1 leaves this nil so behaviour is unchanged. V2
        // passes ~0.85 so wisps that fall in the 0.05–0.30 alpha range get
        // pulled above the perceptual floor before the edge-band blend.
        let softMatte: CIImage = options.softMatteGamma.map { gamma in
            softMatteAttenuated.applyingFilter("CIGammaAdjust", parameters: [
                "inputPower": NSNumber(value: gamma)
            ]).cropped(to: extent)
        } ?? softMatteAttenuated

        // ── Silhouette edge band × the hair zone built above ─────────────
        // Multiplying by the silhouette edge band (dilate − erode of
        // `combined`, default 20px) restricts the soft-matte treatment to
        // actual cutout boundary pixels in that zone — body interior and
        // any non-edge pixel inside the hair zone bounding box are
        // unaffected, so face skin and shoulders never shift. V2 scales
        // the radius by source long-edge so a 4K phone photo gets a wider
        // band than a 1024-px preview.
        let edgeOuter = combined.applyingFilter("CIMorphologyMaximum", parameters: [
            kCIInputRadiusKey: options.edgeBandRadius
        ]).cropped(to: extent)
        let edgeInner = combined.applyingFilter("CIMorphologyMinimum", parameters: [
            kCIInputRadiusKey: options.edgeBandRadius
        ]).cropped(to: extent)
        let edgeBand = edgeOuter.applyingFilter("CISubtractBlendMode", parameters: [
            kCIInputBackgroundImageKey: edgeInner
        ]).cropped(to: extent)
        let hairEdgeRing = hairZone.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: edgeBand
        ]).cropped(to: extent)

        // Blend: where the hair-edge ring is white, take the soft matte;
        // where it's black, take the strict matte. CIBlendWithMask uses
        // its `inputImage` as foreground (white-mask) and its
        // `inputBackgroundImage` as background (black-mask).
        let blended = softMatte.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: strictMatte,
            "inputMaskImage": hairEdgeRing
        ]).cropped(to: extent)

        // ── Decontamination region (wider than the matte-blend ring) ─────
        // Color contamination can extend well past the matte-blend edge
        // ring — flying hair strands 30-50px beyond Apple's silhouette
        // boundary still sit at α=0.005-0.3 and carry the old background.
        // We build a distinct region for the RGB step: every pixel inside
        // the hair zone with any visible soft alpha. Aggressive amplify-
        // and-clamp (×200, [0,1]) is more reliable than CIColorThreshold
        // on the guided matte's RGBA shape — anything above α≈0.005
        // becomes 1.0, anything genuinely 0 stays 0. At α=1 (solid hair
        // interior) blur-fusion is mathematically a no-op (F=I), so it's
        // safe to swap in unmixed RGB across the whole non-zero-alpha
        // zone.
        let alphaPresent = softMatte.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 200, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 200, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 200, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 200)
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ]).cropped(to: extent)
        // V1: scope decontamination to the radial-gradient hair zone so
        // face/shoulder pixels can't possibly shift colour. Side effect:
        // long hair past the shoulder, flyaways, glasses arms — anything
        // outside the ellipses keeps `α·F + (1−α)·B_old` and ghosts the
        // original background through any new backdrop.
        // V2: drop that scope. Blur-fusion at α≈1 is mathematically a no-op
        // (`F = F̂ + 1·(I − F̂) = I`), so body/face are still untouched, but
        // every wispy pixel anywhere in the silhouette gets unmixed RGB.
        let decontamRegion: CIImage = options.widerDecontamination
            ? alphaPresent
            : hairZone.applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: alphaPresent
            ]).cropped(to: extent)

        return RefinedMatte(matte: blended, softAlpha: softMatte, decontamRegion: decontamRegion)
    }

    /// Builds a soft-edged grayscale mask that's 1.0 around the head/hair
    /// and beard territory and 0.0 elsewhere. Two CIRadialGradients (crown
    /// + beard) are unioned via lighten. Coordinates flip from the rest of
    /// the codebase's top-left origin to CIImage's bottom-left origin so
    /// CIRadialGradient places the centres correctly.
    private static func buildHairZoneMask(faceRect: CGRect, extent: CGRect) -> CIImage {
        let imageH = extent.height
        let faceCenterX = faceRect.midX
        let faceTopY_BL    = imageH - faceRect.minY  // top of face in CI coords
        let faceBottomY_BL = imageH - faceRect.maxY  // bottom of face in CI coords
        let faceW = faceRect.width
        let faceH = faceRect.height

        // Crown ellipse — centred a touch above the forehead. Wide enough
        // to catch temple hair (1.4× face width at the soft edge) and tall
        // enough that the crown of the head sits inside the falloff.
        let crownCenter = CIVector(x: faceCenterX, y: faceTopY_BL + faceH * 0.2)
        let crown = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": crownCenter,
            "inputRadius0": faceW * 0.6,   // hard-1.0 interior
            "inputRadius1": faceW * 1.4,   // soft falloff to 0
            "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        ])!.outputImage!.cropped(to: extent)

        // Beard ellipse — smaller, centred just below the chin. Captures
        // beard and stubble that overhangs the neck/background line.
        let beardCenter = CIVector(x: faceCenterX, y: faceBottomY_BL - faceH * 0.1)
        let beard = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": beardCenter,
            "inputRadius0": faceW * 0.3,
            "inputRadius1": faceW * 0.7,
            "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        ])!.outputImage!.cropped(to: extent)

        // Union via lighten = max(crown, beard).
        return crown.applyingFilter("CILightenBlendMode", parameters: [
            kCIInputBackgroundImageKey: beard
        ]).cropped(to: extent)
    }

    /// Picks the largest face from a Vision face-detection result and
    /// returns its rect in image pixel coords with origin TOP-LEFT (the
    /// convention used elsewhere in this file). Returns nil when no face
    /// is detected so the caller can keep the strict matte everywhere.
    private static func largestFaceRect(observations: [VNFaceObservation]?,
                                        imageSize: CGSize) -> CGRect? {
        guard let observations, !observations.isEmpty else { return nil }
        let largest = observations.max {
            $0.boundingBox.width * $0.boundingBox.height
                < $1.boundingBox.width * $1.boundingBox.height
        }!
        // Vision returns normalised coords with origin BOTTOM-LEFT. Flip Y
        // so the rect matches what `detectFace` etc. produce.
        let bb = largest.boundingBox
        let w = imageSize.width
        let h = imageSize.height
        return CGRect(
            x: bb.minX * w,
            y: (1 - bb.maxY) * h,
            width: bb.width * w,
            height: bb.height * h
        )
    }

    /// Scales a Vision-produced mask image up to the source image's extent and
    /// pins the result so subsequent filters see a finite, aligned rect.
    private static func scaleMaskToExtent(_ mask: CIImage, extent: CGRect) -> CIImage {
        let sx = extent.width / mask.extent.width
        let sy = extent.height / mask.extent.height
        return mask
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .cropped(to: extent)
    }

    /// Detects the largest face in the image. Returns rect in image pixel coordinates,
    /// origin at TOP-LEFT (Vision returns bottom-left, we flip).
    static func detectFace(in image: CGImage) -> CGRect? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observations = request.results, !observations.isEmpty else { return nil }

        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)

        // Pick the largest face (most likely the portrait subject).
        let largest = observations.max { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height
                < rhs.boundingBox.width * rhs.boundingBox.height
        }!

        // Vision uses normalized coordinates with origin bottom-left.
        let bb = largest.boundingBox
        let x = bb.origin.x * imgW
        let w = bb.width * imgW
        let h = bb.height * imgH
        // Flip Y to top-left origin.
        let y = (1.0 - bb.origin.y - bb.height) * imgH
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Detects the lowest visible body joint using Vision body-pose estimation.
    /// Returns Y in image pixel coordinates (top-left origin), or nil if no pose found.
    static func detectBodyPoseBottom(in image: CGImage) -> CGFloat? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return nil }

        guard let observation = request.results?.first else { return nil }
        let imgH = CGFloat(image.height)
        var lowestY: CGFloat = 0

        for jointName in observation.availableJointNames {
            guard let point = try? observation.recognizedPoint(jointName),
                  point.confidence > 0.1 else { continue }
            // Vision uses normalized coords with bottom-left origin; flip to top-left.
            let y = (1.0 - point.location.y) * imgH
            lowestY = max(lowestY, y)
        }
        return lowestY > 0 ? lowestY : nil
    }

    /// Scans the alpha channel of a cutout image from the bottom up to find the
    /// lowest row containing non-transparent content. Fast zero-copy fallback when
    /// body-pose detection fails (e.g. non-standard pose, back of head).
    static func contentBottomFromAlpha(of image: CGImage) -> CGFloat? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }

        // Render into a known RGBA layout so we can reliably index the alpha byte.
        let bpr = w * 4
        var pixels = [UInt8](repeating: 0, count: h * bpr)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let sampleStep = max(1, w / 64)
        for row in stride(from: h - 1, through: 0, by: -1) {
            for col in stride(from: 0, to: w, by: sampleStep) {
                let offset = row * bpr + col * 4 + 3 // alpha = last byte in RGBA
                if pixels[offset] > 20 {
                    return CGFloat(row)
                }
            }
        }
        return nil
    }

    // MARK: - Face + Eye Landmark Detection

    /// Detects the largest face **and** eye-landmark positions in a single Vision
    /// pass using `VNDetectFaceLandmarksRequest`.  Returns nil when no face is
    /// found at all; `eyeCenter`/`interEyeDistance` are nil when the eyes
    /// couldn't be located (e.g. face turned away).
    static func detectFaceLandmarks(in image: CGImage) -> FaceDetectionResult? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observations = request.results, !observations.isEmpty else { return nil }

        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)

        // Pick the largest face (most likely the portrait subject).
        let largest = observations.max { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height
                < rhs.boundingBox.width * rhs.boundingBox.height
        }!

        // --- Face bounding box (same conversion as detectFace) ---
        let bb = largest.boundingBox
        let faceX = bb.origin.x * imgW
        let faceW = bb.width   * imgW
        let faceH = bb.height  * imgH
        let faceY = (1.0 - bb.origin.y - bb.height) * imgH
        let faceRect = CGRect(x: faceX, y: faceY, width: faceW, height: faceH)

        // --- Eye landmarks ---
        guard let landmarks = largest.landmarks else {
            return FaceDetectionResult(faceRect: faceRect, eyeCenter: nil, interEyeDistance: nil)
        }

        // Centroid of a landmark region → image pixels (top-left origin).
        // Landmark points are normalised to the face bounding box with origin
        // at bottom-left, matching Vision's coordinate convention.
        func regionCenter(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let region, region.pointCount > 0 else { return nil }
            let pts = region.normalizedPoints
            var sumX: CGFloat = 0, sumY: CGFloat = 0
            for i in 0..<region.pointCount {
                sumX += pts[i].x
                sumY += pts[i].y
            }
            let avgX = sumX / CGFloat(region.pointCount)
            let avgY = sumY / CGFloat(region.pointCount)
            let px = (bb.origin.x + avgX * bb.width)  * imgW
            let py = (1.0 - (bb.origin.y + avgY * bb.height)) * imgH
            return CGPoint(x: px, y: py)
        }

        // Prefer pupils (single point, most precise); fall back to eye-region centroids.
        let leftCenter  = regionCenter(landmarks.leftPupil)  ?? regionCenter(landmarks.leftEye)
        let rightCenter = regionCenter(landmarks.rightPupil) ?? regionCenter(landmarks.rightEye)

        guard let left = leftCenter, let right = rightCenter else {
            return FaceDetectionResult(faceRect: faceRect, eyeCenter: nil, interEyeDistance: nil)
        }

        let eyeCenter = CGPoint(x: (left.x + right.x) / 2,
                                y: (left.y + right.y) / 2)
        let dx = right.x - left.x
        let dy = right.y - left.y
        let ied = sqrt(dx * dx + dy * dy)

        return FaceDetectionResult(faceRect: faceRect, eyeCenter: eyeCenter, interEyeDistance: ied)
    }

    // MARK: - BiRefNet (advanced hair matting)

    /// Removes the background using a BiRefNet CoreML model. Produces a true
    /// alpha matte (0.0–1.0 per pixel) rather than the semi-binary mask that
    /// Apple's Vision pipeline yields. Much better for fine hair strands.
    ///
    /// Falls back to `subjectLift()` when the model fails to produce output.
    static func birefnetLift(image: CGImage, model: MLModel) throws -> CGImage {
        let originalCI = CIImage(cgImage: image)
        let extent = originalCI.extent

        // v5 (RVM) expects 1024×576 input (keeps the 16:9 aspect RVM was
        // trained against and fits ANE tile limits). v4 (BiRefNet) was
        // 1024×1024 square. We distort to fit — the mask is scaled back to
        // the source extent in scaleMaskToExtent() and the aspect artefact
        // on the resized internal tensor does not propagate to the output.
        let inputWidth = 1024
        let inputHeight = 576
        let inputSize = CGSize(width: inputWidth, height: inputHeight)

        // Resize to model input using CIImage (GPU-accelerated).
        let scaleX = CGFloat(inputWidth) / extent.width
        let scaleY = CGFloat(inputHeight) / extent.height
        let resized = originalCI
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(origin: .zero, size: inputSize))

        // Render to a pixel buffer for CoreML input.
        guard let inputBuffer = createPixelBuffer(from: resized, size: inputSize) else {
            dlog("[BiRefNet] Failed to create input buffer, falling back to Vision")
            return try subjectLift(image: image)
        }

        // Run CoreML inference.
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input": MLFeatureValue(pixelBuffer: inputBuffer)
        ])

        let prediction: MLFeatureProvider
        do {
            prediction = try model.prediction(from: input)
        } catch {
            dlog("[BiRefNet] Inference failed: \(error), falling back to Vision")
            return try subjectLift(image: image)
        }

        // Extract the output mask. Both BiRefNet (v4) and RVM (v5) output a
        // single-channel alpha matte, under different feature names:
        //   - BiRefNet: "output" / "sigmoid_output" / "out"
        //   - RVM:      "pha" (alpha) — "fgr" is foreground RGB, ignored here
        //     (see follow-up to wire it in and skip blur-fusion).
        // We try the known names first, then fall through to a scan.
        let outputNames = ["pha", "output", "sigmoid_output", "out"]
        var maskCI: CIImage?

        // Strategy 1: Try CVPixelBuffer output (ImageType in CoreML spec).
        for name in outputNames {
            if let feature = prediction.featureValue(for: name),
               let buffer = feature.imageBufferValue {
                maskCI = CIImage(cvPixelBuffer: buffer)
                dlog("[BiRefNet] Got image output for '\(name)'")
                break
            }
        }
        if maskCI == nil {
            for name in prediction.featureNames {
                if let feature = prediction.featureValue(for: name),
                   let buffer = feature.imageBufferValue {
                    maskCI = CIImage(cvPixelBuffer: buffer)
                    dlog("[BiRefNet] Got image output for '\(name)' (scan)")
                    break
                }
            }
        }

        // Strategy 2: Fall back to MLMultiArray output (tensor).
        if maskCI == nil {
            maskCI = extractMaskFromMultiArray(prediction: prediction)
        }

        guard let rawMask = maskCI else {
            dlog("[BiRefNet] No output mask found, falling back to Vision")
            return try subjectLift(image: image)
        }

        // Scale the mask to the original image resolution.
        let mask = scaleMaskToExtent(rawMask, extent: extent)

        // Apply a light guided-filter pass for hair-fringe refinement. Keep
        // radius small and epsilon loose — an aggressively edge-preserving
        // filter (tiny epsilon) snaps the matte to background color edges
        // and can reinforce leaks when the base matte has any error.
        let guided = mask.applyingFilter("CIGuidedFilter", parameters: [
            "inputGuideImage": originalCI,
            kCIInputRadiusKey: 2.0,
            "inputEpsilon": 0.01
        ]).cropped(to: extent)

        // Synthesise a soft hair fringe without a matting model. The
        // portrait mask is near-bimodal (0 or 1) with a thin stair-step
        // at the silhouette edge — we keep the fully opaque interior
        // (via erosion) and only feather the outer ring (via dilation +
        // blur) so hair gains a photographic falloff but shoulders, face
        // and shirt stay fully opaque when composited over any
        // background. Radii scale with the source resolution so the
        // feather reads consistently on 1024-px previews and 4K imports.
        let longSide = max(extent.width, extent.height)
        let scale = max(1.0, longSide / 1024.0)
        let dilateR = 10.0 * scale
        let erodeR  = 4.0  * scale
        let blurR   = 3.0  * scale

        let outerBand = guided
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: dilateR])
            .cropped(to: extent)
        let innerCore = guided
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: erodeR])
            .cropped(to: extent)
        // Ring = outer − inner, marking the pixels we're allowed to feather.
        let ring = outerBand.applyingFilter("CISubtractBlendMode", parameters: [
            kCIInputBackgroundImageKey: innerCore
        ]).cropped(to: extent)
        let feathered = guided
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurR])
            .cropped(to: extent)
        // Inside the ring use the blurred mask; outside it keep the
        // guided (near-bimodal) mask so the body interior stays solid.
        let softened = feathered.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": guided,
            "inputMaskImage": ring
        ]).cropped(to: extent)

        // Recover unmixed foreground RGB before compositing. Without this,
        // hair strands still carry `α·F + (1−α)·B_old` — the original
        // background bleeds through against any new backdrop. Blur-fusion
        // (Forte & Pitié, ICIP 2021; Photoroom's refine_foreground) solves
        // for F using a wide-then-narrow two-pass weighted average. Driven
        // by the pre-feather guided α so strand transitions stay soft.
        let refinedFG = refineForeground(source: originalCI, alpha: guided, extent: extent)

        // Composite: refined foreground RGB + feathered alpha matte.
        let clearBG = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: extent)
        let alphaMatte = softened.applyingFilter("CIMaskToAlpha")
        let composed = refinedFG.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": clearBG,
            "inputMaskImage": alphaMatte
        ]).cropped(to: extent)

        let outputCS = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cg = ciContext.createCGImage(composed, from: extent, format: .RGBA8, colorSpace: outputCS) else {
            dlog("[BiRefNet] CGImage creation failed, falling back to Vision")
            return try subjectLift(image: image)
        }
        return cg
    }

    // MARK: - Foreground refinement (blur-fusion)

    /// Two-pass blur-fusion foreground estimator (Forte & Pitié, ICIP 2021).
    /// Given the observed image `I = α·F + (1−α)·B` and a soft α matte,
    /// recovers an estimate of the unmixed `F` so the new composite doesn't
    /// carry the old background's colour through semi-transparent strands.
    /// First pass uses a wide kernel to gather long-range colour, the second
    /// a narrow one to recover local detail — same cadence as Photoroom's
    /// `FB_blur_fusion_foreground_estimator_2` and BiRefNet's built-in
    /// `refine_foreground` flag.
    private static func refineForeground(
        source: CIImage, alpha: CIImage, extent: CGRect,
        pass1Radius: Double = 90, pass2Radius: Double = 6
    ) -> CIImage {
        let pass1 = blurFusionPass(I: source, F: source, B: source,
                                   alpha: alpha, radius: pass1Radius, extent: extent)
        let pass2 = blurFusionPass(I: source, F: pass1.F, B: pass1.B,
                                   alpha: alpha, radius: pass2Radius, extent: extent)
        return pass2.F
    }

    /// Single blur-fusion pass. Produces a refined foreground `F` and the
    /// blurred background estimate used as the prior for the next pass.
    private static func blurFusionPass(
        I: CIImage, F: CIImage, B: CIImage, alpha: CIImage,
        radius: Double, extent: CGRect
    ) -> (F: CIImage, B: CIImage) {
        // F·α and B·(1−α) weighted images. Alpha is a grayscale mask so
        // `CIMultiplyCompositing` broadcasts it across the RGB channels.
        let fa = F.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: alpha
        ]).cropped(to: extent)
        let invAlpha = alpha.applyingFilter("CIColorInvert").cropped(to: extent)
        let bInv = B.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: invAlpha
        ]).cropped(to: extent)

        let blur: (CIImage) -> CIImage = { input in
            input.applyingFilter("CIGaussianBlur",
                                 parameters: [kCIInputRadiusKey: radius])
                 .cropped(to: extent)
        }
        let blurredAlpha = blur(alpha)
        let blurredFA    = blur(fa)
        let blurredBInv  = blur(bInv)

        let newF = blurFusionKernel?.apply(
            extent: extent,
            arguments: [I, alpha, blurredAlpha, blurredFA, blurredBInv]
        ) ?? F
        let newB = computeBlurredBKernel?.apply(
            extent: extent,
            arguments: [blurredAlpha, blurredBInv]
        ) ?? B

        return (newF.cropped(to: extent), newB.cropped(to: extent))
    }

    /// Core of the blur-fusion step: divide the blurred weighted images
    /// back out to get `F_hat`, `B_hat`, then add a correction term so the
    /// result reconstructs the observed `I` at the current α.
    private static let blurFusionKernel: CIColorKernel? = {
        let src = """
        kernel vec4 blurFusion(__sample I, __sample alpha,
                               __sample blurredAlpha,
                               __sample blurredFA,
                               __sample blurredBInv) {
            float a   = alpha.r;
            float bA  = blurredAlpha.r;
            float eps = 1e-5;
            vec3 F_hat = blurredFA.rgb   / (bA + eps);
            vec3 B_hat = blurredBInv.rgb / ((1.0 - bA) + eps);
            vec3 F = clamp(F_hat + a * (I.rgb - a * F_hat - (1.0 - a) * B_hat),
                           0.0, 1.0);
            return vec4(F, 1.0);
        }
        """
        return CIColorKernel(source: src)
    }()

    /// Computes the blurred background estimate used as the prior for the
    /// next blur-fusion pass.
    private static let computeBlurredBKernel: CIColorKernel? = {
        let src = """
        kernel vec4 computeBlurredB(__sample blurredAlpha,
                                    __sample blurredBInv) {
            float eps = 1e-5;
            vec3 B = blurredBInv.rgb / ((1.0 - blurredAlpha.r) + eps);
            return vec4(clamp(B, 0.0, 1.0), 1.0);
        }
        """
        return CIColorKernel(source: src)
    }()

    /// Hair-colour-distance alpha attenuation. Inside the hair zone, where
    /// soft alpha is already partial (< 0.95 — i.e. potential edge / inter-
    /// strand opening), we measure how far the pixel's RGB lies from the
    /// locally averaged "solid hair" colour. Far → almost certainly the
    /// original studio background bleeding through Apple's mask in a hair
    /// opening; we attenuate alpha so the pixel becomes transparent and
    /// the new backdrop shows through instead. At α ≥ 0.95 (solid hair,
    /// solid skin, solid body) the gate is 0 and alpha passes through
    /// untouched — face and shoulders cannot be affected.
    ///
    /// `hairBlur` and `maskBlur` are the mask-weighted blurred originals;
    /// the local hair colour is `hairBlur / maskBlur` (mask-weighted mean).
    /// Where `maskBlur` is near 0 (no nearby solid hair) we skip attenuation
    /// rather than emit garbage from a divide-by-zero estimate.
    private static let colorAttenuationKernel: CIColorKernel? = {
        let src = """
        kernel vec4 colorAttenuate(__sample I, __sample hairBlur,
                                   __sample maskBlur, __sample softMatte,
                                   __sample hairZone) {
            float eps = 1e-4;
            float maskW = maskBlur.r + eps;
            vec3 localHair = hairBlur.rgb / maskW;
            float dist = length(I.rgb - localHair);
            // 0.0..0.15 keep, 0.40+ kill. Smooth ramp avoids hard banding.
            float atten = 1.0 - smoothstep(0.15, 0.40, dist);
            // Only attenuate at α<0.95 — protects solid skin/hair/body.
            float partialGate = 1.0 - smoothstep(0.85, 0.99, softMatte.r);
            // Only inside hair zone — protects everything outside.
            float effective = mix(1.0, atten, partialGate * hairZone.r);
            float newAlpha = softMatte.r * effective;
            // Bail out where there's no nearby solid-hair reference.
            if (maskBlur.r < 0.01) newAlpha = softMatte.r;
            return vec4(newAlpha, newAlpha, newAlpha, 1.0);
        }
        """
        return CIColorKernel(source: src)
    }()

    /// Decode an IEEE 754 binary16 (half-precision) bit-pattern to Float32.
    /// We roll this by hand because `Float(Float16(bitPattern:))` does not
    /// compile on the x86_64 slice of a universal build — `Float16` on x86_64
    /// lacks the `init(bitPattern:)` overload. Works on any architecture and
    /// handles subnormals, infinities, and NaN.
    @inline(__always)
    private static func float16BitsToFloat(_ bits: UInt16) -> Float {
        let sign = UInt32(bits >> 15) & 0x1
        let exponent = UInt32(bits >> 10) & 0x1F
        let mantissa = UInt32(bits) & 0x3FF
        let f32Sign = sign << 31
        let result: UInt32
        if exponent == 0 {
            if mantissa == 0 {
                result = f32Sign
            } else {
                // Subnormal — normalize the mantissa into a float32 exponent.
                var e: UInt32 = 0
                var m = mantissa
                while (m & 0x400) == 0 {
                    m <<= 1
                    e &+= 1
                }
                let f32Exp = (127 &- 15 &- e &+ 1) << 23
                result = f32Sign | f32Exp | ((m & 0x3FF) << 13)
            }
        } else if exponent == 0x1F {
            // Infinity or NaN — preserve by propagating mantissa bits.
            result = f32Sign | (0xFF << 23) | (mantissa << 13)
        } else {
            let f32Exp = (exponent &+ (127 &- 15)) << 23
            result = f32Sign | f32Exp | (mantissa << 13)
        }
        return Float(bitPattern: result)
    }

    /// Extracts a grayscale mask CIImage from the first MLMultiArray output
    /// found in the prediction. Handles shapes like (1,1,H,W), (1,H,W), or (H,W)
    /// and both Float32 and Float16 data types.
    private static func extractMaskFromMultiArray(prediction: MLFeatureProvider) -> CIImage? {
        for name in prediction.featureNames {
            guard let feature = prediction.featureValue(for: name),
                  let multiArray = feature.multiArrayValue else { continue }

            let shape = multiArray.shape.map { $0.intValue }
            guard shape.count >= 2 else { continue }

            let h = shape[shape.count - 2]
            let w = shape[shape.count - 1]
            let count = w * h
            guard count > 0 else { continue }

            // Convert the tensor values to 8-bit grayscale bytes.
            var bytes = [UInt8](repeating: 0, count: count)
            let ptr = multiArray.dataPointer

            switch multiArray.dataType {
            case .float32:
                let fp = ptr.assumingMemoryBound(to: Float.self)
                for i in 0..<count {
                    bytes[i] = UInt8(min(255, max(0, fp[i] * 255)))
                }
            case .float16:
                // Float16 is stored as UInt16 bit pattern. We decode manually
                // rather than via `Float(Float16(bitPattern:))` because that
                // initializer isn't available when compiling for x86_64 (the
                // universal-build slice), even on Swift 5.9+.
                let fp = ptr.assumingMemoryBound(to: UInt16.self)
                for i in 0..<count {
                    let f = ImageProcessor.float16BitsToFloat(fp[i])
                    bytes[i] = UInt8(min(255, max(0, f * 255)))
                }
            default:
                dlog("[BiRefNet] Unsupported MultiArray data type: \(multiArray.dataType)")
                continue
            }

            guard let provider = CGDataProvider(data: Data(bytes) as CFData),
                  let cgMask = CGImage(
                      width: w, height: h,
                      bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGBitmapInfo(rawValue: 0),
                      provider: provider, decode: nil,
                      shouldInterpolate: false, intent: .defaultIntent) else {
                continue
            }

            dlog("[BiRefNet] Got MultiArray output for '\(name)' shape=\(shape)")
            return CIImage(cgImage: cgMask)
        }
        return nil
    }

    /// Creates a CVPixelBuffer from a CIImage at the specified size.
    private static func createPixelBuffer(from image: CIImage, size: CGSize) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width), Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let pb = buffer else { return nil }
        ciContext.render(image, to: pb)
        return pb
    }

    // MARK: - Process pipeline

    /// Convenience: lift subject, detect face + eyes, and measure body extent.
    /// When `downloadedModelURL` is provided AND the file at that URL loads
    /// cleanly, runs the BiRefNet matting pipeline for crisper hair edges.
    /// Falls back to Apple Vision (V2 by default) when the URL is nil OR
    /// when the model load / inference fails — failure mode is "the user
    /// gets a result anyway" rather than a hard import error.
    static func process(image: CGImage, downloadedModelURL: URL? = nil) throws -> ProcessedSubject {
        let cutout: CGImage
        if let modelURL = downloadedModelURL {
            do {
                cutout = try subjectLiftDownloaded(image: image, modelURL: modelURL)
                dlog("[Process] Used downloaded BiRefNet pipeline")
            } catch {
                // Soft fallback so a corrupt cache or transient inference
                // failure doesn't block the whole import. The user sees
                // a slightly worse cutout instead of an error chip.
                dlog("[Process] Downloaded model failed (\(error)); falling back to Apple Vision")
                cutout = try subjectLift(image: image)
            }
        } else {
            cutout = try subjectLift(image: image)
            dlog("[Process] Used Apple Vision pipeline")
        }
        // Detect on the original image (better signal than masked cutout);
        // coordinates remain valid because the cutout has the same dimensions.
        let faceResult = detectFaceLandmarks(in: image)
        // Body bottom: prefer body-pose joints, fall back to alpha scan.
        let bodyBottom = detectBodyPoseBottom(in: image)
            ?? contentBottomFromAlpha(of: cutout)
            ?? CGFloat(cutout.height)
        return ProcessedSubject(
            cutout: cutout,
            faceRect: faceResult?.faceRect,
            eyeCenter: faceResult?.eyeCenter,
            interEyeDistance: faceResult?.interEyeDistance,
            bodyBottomY: bodyBottom
        )
    }

    /// Cloud (Magic Cutout) entry point. Sends the image to the backend's
    /// `/api/cutout` endpoint, which proxies to fal.ai BiRefNet and deducts
    /// 1 credit on success.
    ///
    /// Throws `BackendError.noCredits` (caller surfaces the upgrade sheet)
    /// and `BackendError.unauthorized` (caller surfaces the sign-in prompt)
    /// directly. For network/transport/server errors the caller is expected
    /// to fall back to the local `process(image:)` path (Apple Subject Lift)
    /// and show the offline toast — see `ImportFlow` for the policy.
    static func processCloud(
        image: CGImage,
        backend: BackendClient
    ) async throws -> (subject: ProcessedSubject, creditsRemaining: Int) {
        guard let png = pngData(from: image) else {
            throw BackendError.decode
        }
        let (cutoutPNG, creditsRemaining) = try await backend.cutout(imagePNG: png)
        guard let cutout = cgImage(from: cutoutPNG) else {
            throw BackendError.decode
        }
        dlog("[Process] Used Magic Cutout (cloud) — \(creditsRemaining) credits remaining")

        // Detection runs on the original — same rationale as `process(image:)`.
        let faceResult = detectFaceLandmarks(in: image)
        let bodyBottom = detectBodyPoseBottom(in: image)
            ?? contentBottomFromAlpha(of: cutout)
            ?? CGFloat(cutout.height)
        let subject = ProcessedSubject(
            cutout: cutout,
            faceRect: faceResult?.faceRect,
            eyeCenter: faceResult?.eyeCenter,
            interEyeDistance: faceResult?.interEyeDistance,
            bodyBottomY: bodyBottom
        )
        return (subject, creditsRemaining)
    }

    // MARK: - Helpers

    /// Loads a CGImage from raw file data, applying any EXIF orientation so the
    /// image is upright. Without this iPhone/Android portraits often appear sideways.
    static func cgImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return loadOriented(source: src)
    }

    static func cgImage(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return loadOriented(source: src)
    }

    private static func loadOriented(source: CGImageSource) -> CGImage? {
        guard let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationRaw = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        if orientationRaw == 1 { return raw } // already upright
        guard let cgOrientation = CGImagePropertyOrientation(rawValue: orientationRaw) else { return raw }
        // If orientation correction fails, return the raw image rather than nil —
        // a sideways portrait is better than no portrait at all.
        return applyOrientation(raw, orientation: cgOrientation) ?? raw
    }

    private static func applyOrientation(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        let ciImage = CIImage(cgImage: image).oriented(orientation)
        let outputCS = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return ciContext.createCGImage(ciImage, from: ciImage.extent, format: .RGBA8, colorSpace: outputCS)
    }

    static func pngData(from image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Magic Retouch

    /// One-click studio-quality enhancement for a cutout CGImage.
    /// Combines Apple's built-in auto-adjustment analysis with a curated
    /// chain of subtle studio polish filters. Works best on cutout images
    /// (subject on transparent background) because the analysis focuses
    /// on the person, not background noise.
    static func magicRetouch(image: CGImage) -> CGImage? {
        let source = CIImage(cgImage: image)
        let extent = source.extent
        var current = source

        // 1. Apple auto-adjustment — analyses the image and returns optimal
        //    CIFilter corrections (face balance, vibrance, tone curve, etc.).
        //    Red-eye correction disabled since cutouts have no flash red-eye.
        let options: [CIImageAutoAdjustmentOption: Any] = [
            .redEye: false
        ]
        let autoFilters = source.autoAdjustmentFilters(options: options)
        for filter in autoFilters {
            filter.setValue(current, forKey: kCIInputImageKey)
            if let out = filter.outputImage {
                current = out
            }
        }

        // 2. CIVibrance — smart saturation that boosts muted tones (common
        //    in office lighting) without over-saturating vivid colours.
        let vibrance = CIFilter.vibrance()
        vibrance.inputImage = current
        vibrance.amount = 0.3
        if let out = vibrance.outputImage { current = out }

        // 3. CIHighlightShadowAdjust — subtle shadow lift to open up
        //    under-chin and under-brow areas from harsh office lighting.
        let hlShadow = CIFilter.highlightShadowAdjust()
        hlShadow.inputImage = current
        hlShadow.shadowAmount = 0.15
        hlShadow.highlightAmount = 1.0
        if let out = hlShadow.outputImage { current = out }

        // 4. CITemperatureAndTint — gentle warmth (+200K) to shift from
        //    cool fluorescent tones towards a warm studio feel.
        let temp = CIFilter.temperatureAndTint()
        temp.inputImage = current
        temp.neutral = CIVector(x: 6500, y: 0)
        temp.targetNeutral = CIVector(x: 6700, y: 0)
        if let out = temp.outputImage { current = out }

        // 5. CISharpenLuminance — micro-contrast for perceived crispness.
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = current
        sharpen.sharpness = 0.25
        sharpen.radius = 1.0
        if let out = sharpen.outputImage { current = out }

        let outputCS = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return ciContext.createCGImage(current.cropped(to: extent), from: extent, format: .RGBA8, colorSpace: outputCS)
    }
}
