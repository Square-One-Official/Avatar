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
}

enum PreStylizeGateKind: Equatable {
    case lowResolution
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
        // Al geboost (cutout scherper dan een low-res origineel): de gebruiker
        // heeft de kwaliteitskeuze al gemaakt — niet nóg een keer om Boost
        // vragen, en het geboostte cutout is de bron (het origineel is nog
        // steeds klein). Repro: low-res foto → Boost → effect kiezen.
        if isEffects, StylizeQuality.cutoutOutranksLowResOriginal(portrait: portrait, cutout: cutout) {
            return (.proceed, .cutout)
        }
        if StylizeQuality.isLowResolution(source) {
            let decision = await presentPreGate(.lowResolution)
            if decision == .boostFirst {
                await onBoostCutout?()
                // Effects: de boost is net betaald — styleer het geboostte
                // cutout, niet het (nog steeds kleine) origineel.
                if isEffects, let fresh = StylizeQuality.freshlyBoostedCutout(portrait: portrait) {
                    return (.proceed, .freshCutout(fresh))
                }
            }
            return (decision, .original)
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
        }
    }

    private var message: String {
        switch gate.kind {
        case .lowResolution:
            return "This photo is low resolution. Boosting may improve sharpness before editing (\(CreditMeter.chipLabel(for: .upscaleHigh))). Results are not guaranteed."
        }
    }

    private var boostLabel: String {
        "Boost resolution (\(CreditMeter.chipLabel(for: .upscaleHigh)))"
    }
}
