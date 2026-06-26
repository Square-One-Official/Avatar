// Stylize quality helpers — long-edge gate, shared stylize source, dimension
// logging, and post-stylize boost eligibility. Blur detection lives behind
// `blurDetectionEnabled` until calibrated (not shipped in v1).

import AppKit
import os.log

enum StylizeQuality {
    /// Long edge below this → pre-stylize quality sheet (v1 gate).
    static let lowResLongEdge = 1024

    /// Laplacian blur gate — off until calibrated (false positives on bokeh/busy texture).
    static var blurDetectionEnabled = false

    private static let log = Logger(subsystem: "nl.avatar.Avatar2", category: "StylizeQuality")

    // MARK: - Dimensions

    struct PixelSize: Equatable, Sendable {
        let width: Int
        let height: Int

        var longEdge: Int { max(width, height) }
        var pixelCount: Int { width * height }
    }

    static func pixelSize(of image: NSImage) -> PixelSize? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return PixelSize(width: cg.width, height: cg.height)
    }

    static func isLowResolution(_ image: NSImage) -> Bool {
        guard let size = pixelSize(of: image) else { return false }
        return size.longEdge < lowResLongEdge
    }

    /// True when the stylize result has fewer pixels than the cutout before edit.
    static func shouldOfferPostBoost(result: NSImage, cutoutBefore: NSImage) -> Bool {
        guard let r = pixelSize(of: result), let c = pixelSize(of: cutoutBefore) else { return false }
        return r.longEdge < c.longEdge
    }

    // MARK: - Stylize source (Effects + shared inspection)

    /// Which image to send to `/v1/stylize` for Effects.
    enum EffectsSourceChoice: Equatable {
        case original
        case cutout
    }

    /// Prefer the full original for scene styling; fall back to cutout when absent.
    /// When `choice == .cutout`, always use the cutout (explicit user opt-in for low-res originals).
    static func effectsStylizeSource(
        portrait: Portrait2?,
        cutout: NSImage,
        choice: EffectsSourceChoice = .original
    ) -> NSImage {
        switch choice {
        case .cutout:
            return cutout
        case .original:
            if let data = portrait?.originalData, let img = NSImage(data: data) { return img }
            return cutout
        }
    }

    /// Hair / Clothes / Face: the current cutout on the canvas.
    static func editStylizeSource(cutout: NSImage) -> NSImage { cutout }

    /// Original is low-res but cutout may be higher (e.g. after Boost).
    static func shouldOfferEffectsCutoutChoice(portrait: Portrait2?, cutout: NSImage) -> Bool {
        guard let data = portrait?.originalData, let original = NSImage(data: data) else { return false }
        guard isLowResolution(original) else { return false }
        guard let o = pixelSize(of: original), let c = pixelSize(of: cutout) else { return false }
        return c.longEdge > o.longEdge || !isLowResolution(cutout)
    }

    // MARK: - Instrumentation

    struct DimensionLog: Sendable {
        let input: PixelSize
        let output: PixelSize
        let cutout: PixelSize?
    }

    static func logStylizeDimensions(_ entry: DimensionLog) {
        if let cutout = entry.cutout {
            log.info(
                "stylize_dims input=\(entry.input.width)x\(entry.input.height) output=\(entry.output.width)x\(entry.output.height) cutout=\(cutout.width)x\(cutout.height)"
            )
        } else {
            log.info(
                "stylize_dims input=\(entry.input.width)x\(entry.input.height) output=\(entry.output.width)x\(entry.output.height)"
            )
        }
    }

    static func logStylizeDimensions(
        input: NSImage,
        output: NSImage,
        cutoutBefore: NSImage?
    ) {
        guard let inSize = pixelSize(of: input), let outSize = pixelSize(of: output) else { return }
        logStylizeDimensions(DimensionLog(
            input: inSize,
            output: outSize,
            cutout: cutoutBefore.flatMap { pixelSize(of: $0) }
        ))
    }

    /// Cutout dimensions for `/v1/stylize` telemetry (`cutout_w` / `cutout_h`).
    static func cutoutDimensions(for cutout: NSImage) -> (width: Int?, height: Int?) {
        guard let size = pixelSize(of: cutout) else { return (nil, nil) }
        return (size.width, size.height)
    }
}

// MARK: - Transform adjustment when keeping a higher-res cutout

extension ShellModel {
    /// Adjusts `Portrait2.scale` so canvas position stays fixed when cutout width
    /// changes W → W′ (center-anchored layout in EditorCanvasView).
    nonisolated static func adjustedScaleForResolutionChange(
        oldWidth: Int,
        newWidth: Int,
        currentScale: Double
    ) -> Double {
        guard oldWidth > 0, newWidth > 0, currentScale > 0 else { return currentScale }
        return currentScale * (Double(oldWidth) / Double(newWidth))
    }
}
