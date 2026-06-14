// Sidebar-thumbnail-cache (E19.6). De sidebar-rijen tekenden hun thumbnail uit
// `NSImage(data: portrait.cutoutData)` — een volle-resolutie-PNG-decode bij
// ÉLKE render. Een DSSidebarRow her-rendert o.a. op hover (DSStateOpacity-
// ButtonStyle), dus elke muisbeweging over de lijst decodeerde meerdere
// full-res PNG's → hover-lag. Deze cache decodeert + downscalet één keer per
// (portret, versie) en bewaart een kleine bitmap; hover-renders zijn daarna
// allocatie-vrij.

import AppKit
import AvatarKit

enum SidebarThumbnailCache {
    private static let cache = NSCache<NSString, NSImage>()

    /// Gedownscalede thumbnail (default 96px = 2× de 48pt-slot). Key bevat
    /// `updatedAt` zodat een bewerkt portret automatisch een verse thumb krijgt.
    static func thumbnail(for portrait: Portrait2, side: CGFloat = 96) -> NSImage? {
        let key = "\(portrait.persistentModelID.hashValue)-\(portrait.updatedAt.timeIntervalSince1970)-\(Int(side))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let full = NSImage(data: portrait.cutoutData),
              let cg = full.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let scale = side / CGFloat(max(cg.width, cg.height, 1))
        let w = max(1, Int(CGFloat(cg.width) * scale))
        let h = max(1, Int(CGFloat(cg.height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return full }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return full }

        let thumb = NSImage(cgImage: out, size: NSSize(width: w, height: h))
        cache.setObject(thumb, forKey: key)
        return thumb
    }
}
