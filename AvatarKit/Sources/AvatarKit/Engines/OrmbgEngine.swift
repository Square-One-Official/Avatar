import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Foundation

/// Engine B uit pipeline-audit-2.0.md: het gedownloade ORMBG-matting-model
/// (Apache-2.0, DIS-familie, portret-getraind), opt-in "High-fidelity edges".
///
/// Het 3-staps pad uit v1's `subjectLiftDownloaded`, ongewijzigd: model-matte
/// → lichte guided filter → composite. Bewust géén V2-refinement erbovenop —
/// de v1-historie documenteert dat die lagen op ORMBG-output actief schadelijk
/// waren (halo's): het model levert zelf al continue α.
public struct OrmbgEngine: CutoutEngine {
    public enum Failure: Error, Equatable {
        /// Geen bruikbare matte in de model-output gevonden.
        case maskExtractionFailed
        /// Core Image kon input of eindresultaat niet renderen.
        case renderFailed
    }

    public let kind: CutoutEngineKind = .ormbg

    private let store: OrmbgModelStore

    public init(store: OrmbgModelStore = .shared) {
        self.store = store
    }

    /// Beschikbaar zodra het model (in de huidige versie) op schijf staat.
    /// Download verloopt via `OrmbgModelStore.download()` (settings-flow).
    public var isAvailable: Bool {
        get async { store.installedModelURL() != nil }
    }

    public func cutout(_ image: CGImage) async throws -> CGImage {
        let model = try await store.model()
        let original = CIImage(cgImage: image)
        let extent = original.extent

        // 1. Bron naar 1024×1024 — ORMBG (en de meeste DIS-matting-heads)
        //    is op die vaste resolutie getraind. De ×1/255-preprocessing
        //    zit in het model gebakken, dus de buffer draagt gewone sRGB
        //    0–255 zonder verdere normalisatie.
        let inputSize: CGFloat = 1024
        let resized = original
            .transformed(by: CGAffineTransform(scaleX: inputSize / extent.width,
                                               y: inputSize / extent.height))
            .cropped(to: CGRect(x: 0, y: 0, width: inputSize, height: inputSize))
        guard let inputBuffer = Self.pixelBuffer(from: resized,
                                                 size: CGSize(width: inputSize, height: inputSize)) else {
            throw Failure.renderFailed
        }

        // 2. Inference + matte-extractie. Output-naamgeving wisselt per
        //    converter (netjes "alpha", of een opaak tensor-nummer), dus:
        //    bekende aliassen → eerste image-typed output → MultiArray-scan.
        let prediction = try await model.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "input": MLFeatureValue(pixelBuffer: inputBuffer)
        ]))
        guard let rawMask = Self.extractMask(from: prediction) else {
            throw Failure.maskExtractionFailed
        }

        // 3. Matte terug naar bron-extent, lichte guided filter (losse ε —
        //    de matte is al edge-aware, dit ruimt alleen sub-pixel
        //    schaal-artefacten op) en composite over transparant.
        let mask = EngineRendering.scaled(rawMask, to: extent)
        let guided = mask.applyingFilter("CIGuidedFilter", parameters: [
            "inputGuideImage": original,
            kCIInputRadiusKey: 2.0,
            "inputEpsilon": 0.01
        ]).cropped(to: extent)

        let clearBackground = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: extent)
        let alphaMatte = guided.applyingFilter("CIMaskToAlpha")
        let composed = original.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clearBackground,
            "inputMaskImage": alphaMatte
        ]).cropped(to: extent)

        let outputColorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let result = EngineRendering.linearContext.createCGImage(
            composed, from: extent, format: .RGBA8, colorSpace: outputColorSpace
        ) else {
            throw Failure.renderFailed
        }
        return result
    }

    // MARK: - Matte-extractie

    /// Zoekt de matte in de model-output: bekende namen eerst, dan elke
    /// image-typed feature, dan de MultiArray-route.
    static func extractMask(from prediction: MLFeatureProvider) -> CIImage? {
        let candidateNames = ["alpha", "output", "sigmoid_output", "out"]
        for name in candidateNames {
            if let buffer = prediction.featureValue(for: name)?.imageBufferValue {
                return CIImage(cvPixelBuffer: buffer)
            }
        }
        for name in prediction.featureNames {
            if let buffer = prediction.featureValue(for: name)?.imageBufferValue {
                return CIImage(cvPixelBuffer: buffer)
            }
        }
        return extractMaskFromMultiArray(prediction: prediction)
    }

    /// Grayscale-masker uit de eerste MLMultiArray-output. Ondersteunt
    /// shapes als (1,1,H,W), (1,H,W) of (H,W), in Float32 en Float16.
    static func extractMaskFromMultiArray(prediction: MLFeatureProvider) -> CIImage? {
        for name in prediction.featureNames {
            guard let multiArray = prediction.featureValue(for: name)?.multiArrayValue else { continue }

            let shape = multiArray.shape.map { $0.intValue }
            guard shape.count >= 2 else { continue }
            let h = shape[shape.count - 2]
            let w = shape[shape.count - 1]
            let count = w * h
            guard count > 0 else { continue }

            var bytes = [UInt8](repeating: 0, count: count)
            let ptr = multiArray.dataPointer
            switch multiArray.dataType {
            case .float32:
                let fp = ptr.assumingMemoryBound(to: Float.self)
                for i in 0..<count {
                    bytes[i] = UInt8(min(255, max(0, fp[i] * 255)))
                }
            case .float16:
                // Float16 als UInt16-bitpatroon, handmatig gedecodeerd —
                // `Float16` is niet beschikbaar op de x86_64-slice van een
                // universal build.
                let fp = ptr.assumingMemoryBound(to: UInt16.self)
                for i in 0..<count {
                    let f = float16BitsToFloat(fp[i])
                    bytes[i] = UInt8(min(255, max(0, f * 255)))
                }
            default:
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
            return CIImage(cgImage: cgMask)
        }
        return nil
    }

    static func float16BitsToFloat(_ bits: UInt16) -> Float {
        let sign = UInt32(bits >> 15) & 0x1
        let exponent = UInt32(bits >> 10) & 0x1F
        let mantissa = UInt32(bits) & 0x3FF
        let f32Sign = sign << 31
        let result: UInt32
        if exponent == 0 {
            if mantissa == 0 {
                result = f32Sign
            } else {
                // Subnormaal — normaliseer de mantisse naar een
                // float32-exponent.
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
            // Oneindig of NaN — mantissebits propageren.
            result = f32Sign | (0xFF << 23) | (mantissa << 13)
        } else {
            let f32Exp = (exponent &+ (127 &- 15)) << 23
            result = f32Sign | f32Exp | (mantissa << 13)
        }
        return Float(bitPattern: result)
    }

    private static func pixelBuffer(from image: CIImage, size: CGSize) -> CVPixelBuffer? {
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
        EngineRendering.standardContext.render(image, to: pb)
        return pb
    }
}
