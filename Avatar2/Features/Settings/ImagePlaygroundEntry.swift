// Tier 2: Image Playground ingang achter privacy-gate.

import AppKit
import AvatarUI
import SwiftUI

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

struct ImagePlaygroundEntryButton: View {
    let entitlement: EntitlementModel
    var label: String = "Generate with Apple Intelligence"
    var onGenerated: ((Data) -> Void)?

    var body: some View {
        if AppleIntelligenceAvailability.supportsApplePrivateCloud {
            #if canImport(ImagePlayground)
            if #available(macOS 15.1, *) {
                ImagePlaygroundEntryButtonAvailable(
                    entitlement: entitlement,
                    label: label,
                    onGenerated: onGenerated
                )
            }
            #endif
        }
    }
}

#if canImport(ImagePlayground)
@available(macOS 15.1, *)
private struct ImagePlaygroundEntryButtonAvailable: View {
    let entitlement: EntitlementModel
    var label: String
    var onGenerated: ((Data) -> Void)?

    @State private var showSheet = false

    var body: some View {
        Button(label) {
            guard entitlement.allowAIFeature(.imagePlaygroundGenerate) else { return }
            showSheet = true
        }
        .buttonStyle(.plain)
        .imagePlaygroundGenerationSheet(isPresented: $showSheet) { url in
            showSheet = false
            guard let data = ImagePlaygroundEntry.pngData(from: url) else { return }
            onGenerated?(data)
        }
    }
}
#endif
