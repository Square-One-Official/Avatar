import CoreGraphics

/// Heuristic: does this cutout already look like a colour photo (vs B&W /
/// greyscale)? Samples opaque pixels and measures chroma (the max-min
/// channel spread). Deliberately biased toward requiring *strong* colour
/// evidence so genuinely black-and-white photos — including slightly
/// sepia/tinted scans — never trip the Colorise "already in colour" hint.
/// A missed colour photo simply behaves as before (no hint), so the cost
/// of a false negative is the status quo.
public enum ColourDetector {
    /// A pixel counts as "coloured" once its channel spread exceeds this
    /// (out of 255). ~25 clears JPEG noise and faint sepia tints.
    private static let chromaThreshold: UInt8 = 25
    /// The image is treated as colour once this fraction of opaque samples
    /// are coloured. 0.15 keeps mostly-grey photos with a stray colour
    /// speck from being flagged.
    private static let colourFraction = 0.15

    public static func isLikelyColour(_ image: CGImage) -> Bool {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return false }

        // Render into a known RGBA8 layout so channel indexing is reliable.
        let bpr = w * 4
        var pixels = [UInt8](repeating: 0, count: h * bpr)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: bpr,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return false }

        let step = max(1, w / 64)
        var opaque = 0
        var coloured = 0
        for row in stride(from: 0, to: h, by: step) {
            for col in stride(from: 0, to: w, by: step) {
                let offset = row * bpr + col * 4
                let a = pixels[offset + 3]
                guard a > 20 else { continue } // skip transparent background
                opaque += 1
                let r = pixels[offset]
                let g = pixels[offset + 1]
                let b = pixels[offset + 2]
                let chroma = max(r, g, b) - min(r, g, b)
                if chroma > chromaThreshold { coloured += 1 }
            }
        }

        guard opaque > 0 else { return false }
        return Double(coloured) / Double(opaque) > colourFraction
    }
}
