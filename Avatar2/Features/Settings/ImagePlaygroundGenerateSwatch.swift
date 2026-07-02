// Tier 2: Image Playground swatch (genereren of bewerken met bronafbeelding).

import AppKit
import AvatarUI
import SwiftUI

struct ImagePlaygroundGenerateSwatch: View {
    var entitlement: EntitlementModel?
    var feature: AIFeature = .imagePlaygroundGenerate
    var sourceImage: NSImage?
    var swatchSize: CGFloat = 36
    var help: String?
    var onGenerated: (Data) -> Void

    private var resolvedHelp: String {
        help ?? feature.uiLabel
    }

    var body: some View {
        if AppleIntelligenceAvailability.supportsApplePrivateCloud {
            #if canImport(ImagePlayground)
            if #available(macOS 15.1, *) {
                ImagePlaygroundGenerateSwatchAvailable(
                    entitlement: entitlement,
                    feature: feature,
                    sourceImage: sourceImage,
                    swatchSize: swatchSize,
                    help: resolvedHelp,
                    onGenerated: onGenerated
                )
            }
            #endif
        }
    }
}

#if canImport(ImagePlayground)
@available(macOS 15.1, *)
private struct ImagePlaygroundGenerateSwatchAvailable: View {
    var entitlement: EntitlementModel?
    var feature: AIFeature
    var sourceImage: NSImage?
    var swatchSize: CGFloat
    var help: String
    var onGenerated: (Data) -> Void

    @State private var showSheet = false

    var body: some View {
        Button(action: requestPlayground) {
            RoundedRectangle(cornerRadius: DSRadius.lg)
                .fill(DSColor.Background.neutral)
                .frame(width: swatchSize, height: swatchSize)
                .overlay {
                    DSIcon(.privacyAppleCloud, size: 14, weight: .bold)
                        .foregroundStyle(DSColor.Foreground.subtle)
                }
        }
        .buttonStyle(.plain)
        .dsHoverScale()
        .help(help)
        .imagePlaygroundGenerationSheet(
            isPresented: $showSheet,
            sourceImage: sourceImage.map { Image(nsImage: $0) },
            onCompletion: handleCompletion,
            onCancellation: {}
        )
    }

    private func requestPlayground() {
        guard let entitlement else { return }
        guard entitlement.allowAIFeature(feature) else { return }
        showSheet = true
    }

    private func handleCompletion(_ url: URL) {
        showSheet = false
        guard let data = ImagePlaygroundEntry.pngData(from: url) else { return }
        onGenerated(data)
    }
}
#endif

/// Compacte chip-variant voor het Enhance-paneel (bewerken met bronafbeelding).
struct ImagePlaygroundEditChip: View {
    var entitlement: EntitlementModel?
    let sourceImage: NSImage
    var onEdited: (Data) -> Void

    var body: some View {
        if AppleIntelligenceAvailability.supportsApplePrivateCloud {
            #if canImport(ImagePlayground)
            if #available(macOS 15.1, *) {
                ImagePlaygroundEditChipAvailable(
                    entitlement: entitlement,
                    sourceImage: sourceImage,
                    onEdited: onEdited
                )
            }
            #endif
        }
    }
}

#if canImport(ImagePlayground)
@available(macOS 15.1, *)
private struct ImagePlaygroundEditChipAvailable: View {
    var entitlement: EntitlementModel?
    let sourceImage: NSImage
    var onEdited: (Data) -> Void

    @State private var showSheet = false

    var body: some View {
        Button(action: requestEdit) {
            HStack(spacing: DSSpacing.gap1) {
                DSIcon(.privacyAppleCloud, size: 12, weight: .bold)
                Text("Edit with Apple Intelligence").dsTextStyle(.labelSmall)
                DSPrivacyBadge(tier: .appleCloud)
            }
            .foregroundStyle(DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 32)
            .background(DSColor.Background.neutral, in: Capsule())
        }
        .buttonStyle(.plain)
        .dsHoverScale()
        .imagePlaygroundGenerationSheet(
            isPresented: $showSheet,
            sourceImage: Image(nsImage: sourceImage),
            onCompletion: handleCompletion,
            onCancellation: {}
        )
    }

    private func requestEdit() {
        guard let entitlement else { return }
        guard entitlement.allowAIFeature(.imagePlaygroundEdit) else { return }
        showSheet = true
    }

    private func handleCompletion(_ url: URL) {
        showSheet = false
        guard let data = ImagePlaygroundEntry.pngData(from: url) else { return }
        onEdited(data)
    }
}
#endif
