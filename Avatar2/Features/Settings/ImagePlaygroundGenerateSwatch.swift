// Tier 2: Image Playground swatch (genereren of bewerken met bronafbeelding).
//
// E53.8: beide knoppen presenteren de sheet niet meer zelf. Ze vragen
// `ImagePlaygroundPresenter` om 'm te tonen; de sheet hangt op ShellView. Zo
// overleeft een lopende generatie een tab-/lens-wissel — de knop mag intussen
// gerust uit de view-hiërarchie verdwijnen. Daarmee vervalt ook de
// `@available`-splitsing per knop: de OS-check zit nu op de host.

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
            Button(action: request) {
                RoundedRectangle(cornerRadius: DSRadius.lg)
                    .fill(DSColor.Background.neutral)
                    .frame(width: swatchSize, height: swatchSize)
                    .overlay {
                        DSIcon(.privacyAppleCloud, size: DSIconSize.base, weight: .bold)
                            .foregroundStyle(DSColor.Foreground.subtle)
                    }
            }
            .buttonStyle(.plain)
            .dsFocusEffectDisabled()
            .dsHoverScale()
            .help(resolvedHelp)
            .accessibilityLabel(resolvedHelp)
            .cloudFeatureMuted()
        }
    }

    private func request() {
        guard let entitlement, entitlement.allowAIFeature(feature, retry: request) else { return }
        ImagePlaygroundPresenter.shared.present(sourceImage: sourceImage, onCompleted: onGenerated)
    }
}

/// Compacte chip-variant voor het Enhance-paneel (bewerken met bronafbeelding).
struct ImagePlaygroundEditChip: View {
    var entitlement: EntitlementModel?
    let sourceImage: NSImage
    var onEdited: (Data) -> Void

    var body: some View {
        if AppleIntelligenceAvailability.supportsApplePrivateCloud {
            Button(action: request) {
                HStack(spacing: DSSpacing.gap1) {
                    DSIcon(.privacyAppleCloud, size: DSIconSize.sm, weight: .bold)
                    Text("Edit with Apple Intelligence").dsTextStyle(.labelSmall)
                    DSPrivacyBadge(tier: .thirdParty)
                }
                .foregroundStyle(DSColor.Foreground.primary)
                .padding(.horizontal, DSSpacing.gap2)
                .frame(height: 32)
                .background(DSColor.Background.neutral, in: Capsule())
            }
            .buttonStyle(.plain)
            .dsFocusEffectDisabled()
            .dsHoverScale()
            .cloudFeatureMuted()
            .accessibilityLabel("Edit with Apple Intelligence")
        }
    }

    private func request() {
        guard let entitlement, entitlement.allowAIFeature(
            .imagePlaygroundEdit,
            retry: request
        ) else { return }
        ImagePlaygroundPresenter.shared.present(sourceImage: sourceImage, onCompleted: onEdited)
    }
}
