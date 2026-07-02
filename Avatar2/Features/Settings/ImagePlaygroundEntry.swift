// Tier 2: Image Playground ingang achter privacy-gate.

import AppKit

enum ImagePlaygroundEntry {

    @MainActor
    static func requestGenerate(entitlement: EntitlementModel) {
        _ = entitlement.allowAIFeature(.imagePlaygroundGenerate)
    }

    @MainActor
    static func requestEdit(entitlement: EntitlementModel) {
        _ = entitlement.allowAIFeature(.imagePlaygroundEdit)
    }

    static func pngData(from url: URL) -> Data? {
        #if canImport(ImagePlayground)
        if #available(macOS 15.1, *) {
            return ImagePlaygroundBridge.pngData(from: url)
        }
        #endif
        return NSImage(contentsOf: url)?.pngData()
    }
}

