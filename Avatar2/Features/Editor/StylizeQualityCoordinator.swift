// Coordinates pre-stylize quality sheets and post-stylize boost offers across
// Effects / Hair / Clothes / Face panels. Owned by EditorView; panels await
// decisions before calling the backend.

import AppKit
import AvatarKit
import AvatarUI
import SwiftUI

enum PreStylizeDecision: Equatable {
    case proceed
    case boostFirst
    /// Effects only: stylize the cutout instead of the low-res original (no scene styling).
    case useCutoutSource
}

enum PreStylizeGateKind: Equatable {
    case lowResolution
    case effectsLowResOriginal
}

struct PreStylizeGate: Identifiable {
    let id = UUID()
    let kind: PreStylizeGateKind
}

struct PostStylizeBoostOffer: Identifiable {
    let id = UUID()
    let message: String
}

@MainActor
@Observable
final class StylizeQualityCoordinator {
    var preGate: PreStylizeGate?
    var postBoostOffer: PostStylizeBoostOffer?

    /// Wired by EditorView — runs Real-ESRGAN on the current cutout (1 credit).
    var onBoostCutout: (() async -> Void)?

    private var preGateContinuation: CheckedContinuation<PreStylizeDecision, Never>?

    func presentPreGate(_ kind: PreStylizeGateKind) async -> PreStylizeDecision {
        preGate = PreStylizeGate(kind: kind)
        return await withCheckedContinuation { continuation in
            preGateContinuation = continuation
        }
    }

    func resolvePreGate(_ decision: PreStylizeDecision) {
        preGate = nil
        preGateContinuation?.resume(returning: decision)
        preGateContinuation = nil
    }

    func offerPostBoostIfNeeded(result: NSImage, cutoutBefore: NSImage) {
        guard StylizeQuality.shouldOfferPostBoost(result: result, cutoutBefore: cutoutBefore) else {
            return
        }
        postBoostOffer = PostStylizeBoostOffer(
            message: "The effect was generated at lower resolution. Sharpen the result? (1 credit)"
        )
    }

    func dismissPostBoost() {
        postBoostOffer = nil
    }

    /// Run the pre-stylize gate for a generative edit source image.
    func gateBeforeStylize(
        source: NSImage,
        portrait: Portrait2?,
        cutout: NSImage,
        isEffects: Bool
    ) async -> (decision: PreStylizeDecision, effectsSource: StylizeQuality.EffectsSourceChoice) {
        if isEffects, StylizeQuality.shouldOfferEffectsCutoutChoice(portrait: portrait, cutout: cutout) {
            let decision = await presentPreGate(.effectsLowResOriginal)
            switch decision {
            case .useCutoutSource:
                return (.proceed, .cutout)
            case .boostFirst:
                await onBoostCutout?()
                return (.proceed, .original)
            case .proceed:
                return (.proceed, .original)
            }
        }
        if StylizeQuality.isLowResolution(source) {
            let decision = await presentPreGate(.lowResolution)
            if decision == .boostFirst {
                await onBoostCutout?()
            }
            return (decision == .useCutoutSource ? .proceed : decision, .original)
        }
        return (.proceed, .original)
    }
}

// MARK: - Sheets

struct PreStylizeQualitySheet: View {
    let gate: PreStylizeGate
    let onDecision: (PreStylizeDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            Text(title)
                .dsTextStyle(.h3)
            Text(message)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.subtle)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DSSpacing.gap2) {
                if gate.kind == .effectsLowResOriginal {
                    Button("Use cutout instead") { onDecision(.useCutoutSource) }
                        .buttonStyle(.bordered)
                }
                Button("Continue anyway") { onDecision(.proceed) }
                    .buttonStyle(.bordered)
                Button(boostLabel) { onDecision(.boostFirst) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(DSSpacing.gap6)
        .frame(width: 380)
    }

    private var title: String {
        switch gate.kind {
        case .lowResolution: return "Low resolution photo"
        case .effectsLowResOriginal: return "Low resolution original"
        }
    }

    private var message: String {
        switch gate.kind {
        case .lowResolution:
            return "This photo is low resolution. Boosting may improve sharpness before editing (1 credit). Results are not guaranteed."
        case .effectsLowResOriginal:
            return "Your original photo is low resolution. You can boost it first (1 credit), continue with the original (background will be styled), or stylize the cutout instead — the background and scene will not be restyled."
        }
    }

    private var boostLabel: String {
        "Boost resolution (\(CreditMeter.chipLabel(for: .upscale)))"
    }
}

struct PostStylizeBoostBanner: View {
    let offer: PostStylizeBoostOffer
    let onSharpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DSSpacing.gap3) {
            Text(offer.message)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.primary)
            Spacer(minLength: DSSpacing.gap2)
            Button("Not now", action: onDismiss)
                .buttonStyle(.borderless)
            Button("Sharpen (\(CreditMeter.chipLabel(for: .upscale)))", action: onSharpen)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, DSSpacing.gap4)
        .padding(.vertical, DSSpacing.gap2)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
    }
}
