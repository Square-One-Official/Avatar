// Coordinates pre-stylize quality sheets across Effects / Hair / Clothes /
// Face panels. Owned by EditorView; panels await decisions before calling
// the backend.

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

@MainActor
@Observable
final class StylizeQualityCoordinator {
    var preGate: PreStylizeGate?

    /// Wired by EditorView — cloud-boost van het huidige cutout (Topaz, 3 credits; E41.5).
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
        VStack(alignment: .leading, spacing: DSSpacing.gap5) {
            Text(title)
                .dsTextStyle(.h3)
                .foregroundStyle(DSColor.Foreground.primary)
            Text(message)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: DSSpacing.gap3) {
                if gate.kind == .effectsLowResOriginal {
                    DSGhostButton("Use cutout instead", fullWidth: true) { onDecision(.useCutoutSource) }
                }
                DSNeutralButton("Continue anyway", fullWidth: true) { onDecision(.proceed) }
                DSPrimaryButton(boostLabel, fullWidth: true) { onDecision(.boostFirst) }
            }
        }
        .padding(DSSpacing.gap8)
        .frame(width: 420)
        .background(DSColor.Background.app)
        .appliedAppearancePreference()
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
            return "This photo is low resolution. Boosting may improve sharpness before editing (\(CreditMeter.chipLabel(for: .upscaleHigh))). Results are not guaranteed."
        case .effectsLowResOriginal:
            return "Your original photo is low resolution. You can boost it first (\(CreditMeter.chipLabel(for: .upscaleHigh))), continue with the original (background will be styled), or stylize the cutout instead — the background and scene will not be restyled."
        }
    }

    private var boostLabel: String {
        "Boost resolution (\(CreditMeter.chipLabel(for: .upscaleHigh)))"
    }
}
