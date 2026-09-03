// Hair-paneel (E11.2, Figma App / Hair). Zelfde patroon als Clothes:
// kapsel-chips + een vrije beschrijving. Copy uit het figma-design-review-
// voorstel (chips: Trim flyaways / Curly / Straight / Short / Updo;
// placeholder "Describe a color or style"; comb-glyph i.p.v. schaar). De
// generatie loopt via het productie-`/v1/stylize` (E09.2) met de hair-intent
// (E11.2-backend), nano-banana instruction-edit (E11.1-route): alléén het
// haar wijzigt, gezicht/expressie/kleding identiek. Net als Clothes vertrouwen
// we op die model-instructie en re-isoleert ShellModel.applyEffectResult het
// volle resultaat (geen lokale crown-mask). Credit-gegated (generatief
// standaard = 4), 402 → paywall.

import AppKit
import AvatarKit
import AvatarUI
import SwiftUI

/// Stuurt de kapselwissel aan en reikt het resultaat omhoog naar de
/// ShellModel (canvas + opgeslagen cutout). Elke edit vertrekt vanaf het
/// meegegeven basisbeeld (het huidige portret op de kaart).
@MainActor
@Observable
final class HairModel {
    enum Phase: Equatable {
        case idle
        case working
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    private let entitlement: EntitlementModel
    private let onApply: (NSImage) async -> Void
    private let coordinator: StylizeQualityCoordinator?

    init(
        entitlement: EntitlementModel,
        coordinator: StylizeQualityCoordinator? = nil,
        onApply: @escaping (NSImage) async -> Void
    ) {
        self.entitlement = entitlement
        self.coordinator = coordinator
        self.onApply = onApply
    }

    var creditCost: Int { CreditMeter.credits(for: .generativeStandard) }
    var isBusy: Bool { phase == .working }

    func apply(
        presetKey: String? = nil,
        freeText: String? = nil,
        base: NSImage,
        portrait: Portrait2? = nil
    ) async {
        guard !isBusy else { return }
        guard entitlement.allowAIFeature(.hairEdit, retry: { [weak self] in
            guard let self else { return }
            Task {
                await self.apply(
                    presetKey: presetKey, freeText: freeText, base: base, portrait: portrait
                )
            }
        }) else { return }

        let source = StylizeQuality.editStylizeSource(cutout: base)
        _ = await coordinator?.gateBeforeStylize(
            source: source, portrait: portrait, cutout: base, isEffects: false
        )
        let cutoutBefore = NSImage(data: portrait?.cutoutData ?? Data()) ?? base

        guard let png = source.pngData() else {
            entitlement.presentError("Couldn't read the portrait.")
            return
        }
        let (cutoutW, cutoutH) = StylizeQuality.cutoutDimensions(for: cutoutBefore)
        phase = .working
        entitlement.presentWorking(
            title: "Changing hair",
            messages: [
                "Touching up the hair…",
                "Trimming the flyaways…",
                "Consulting with the stylist…",
                "Every strand counts…",
                "Having second thoughts…",
                "Almost there, promise…",
            ]
        )
        do {
            let softSource = StylizeQuality.requestsSoftSourcePrompt(for: source)
            let result = try await entitlement.backend.editHair(
                imagePNG: png, presetKey: presetKey, freeText: freeText,
                cutoutWidth: cutoutW, cutoutHeight: cutoutH,
                softSource: softSource
            )
            guard let image = NSImage(data: result.data) else {
                phase = .idle
                entitlement.dismissWorkingToast()
                entitlement.presentError("The result came back unreadable.")
                return
            }
            StylizeQuality.logStylizeDimensions(input: source, output: image, cutoutBefore: cutoutBefore)
            await onApply(image)
            phase = .idle
            entitlement.dismissWorkingToast()
            await entitlement.refresh()
        } catch BackendError.noCredits {
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.handleOutOfCredits()
        } catch BackendError.generationRefused {
            // E55: safety-weigering → advies "andere foto", geen credits kwijt.
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.presentError(BackendError.generationRefused.errorDescription ?? "")
        } catch {
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.presentError("Couldn't change the hair. Please try again.")
        }
    }

}

struct HairPanel: View {
    let baseImage: NSImage
    let entitlement: EntitlementModel
    var portrait: Portrait2?
    var coordinator: StylizeQualityCoordinator?
    var onApply: (NSImage) async -> Void = { _ in }

    @State private var model: HairModel
    @State private var prompt = ""
    @State private var cmsPresets: [RemotePreset] = []

    private static var sessionCache: [RemotePreset]? = nil

    private static let fallbackPresets: [RemotePreset] = HairStyle.allCases.enumerated().map {
        RemotePreset(key: $0.element.rawValue, label: $0.element.label, order: $0.offset)
    }

    private var presets: [RemotePreset] {
        cmsPresets.isEmpty ? HairPanel.fallbackPresets : cmsPresets
    }

    init(
        baseImage: NSImage,
        entitlement: EntitlementModel,
        portrait: Portrait2? = nil,
        coordinator: StylizeQualityCoordinator? = nil,
        onApply: @escaping (NSImage) async -> Void = { _ in }
    ) {
        self.baseImage = baseImage
        self.entitlement = entitlement
        self.portrait = portrait
        self.coordinator = coordinator
        self.onApply = onApply
        _model = State(initialValue: HairModel(entitlement: entitlement, coordinator: coordinator, onApply: onApply))
        _cmsPresets = State(initialValue: HairPanel.sessionCache ?? [])
    }

    var body: some View {
        DSEditPanel(title: "Change hair", credits: CreditMeter.chipLabel(for: .generativeStandard)) {
            VStack(alignment: .leading, spacing: DSSpacing.gap4) {

                // Kapsel-presets (CMS-gestuurd; fallback: HairStyle.allCases).
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.gap2) {
                        ForEach(presets) { preset in
                            DSChip(preset.label, type: .neutral) {
                                Task { await model.apply(presetKey: preset.key, base: baseImage, portrait: portrait) }
                            }
                        }
                    }
                    .scrollRowTrailingInset()
                }
                .horizontalScrollEdgeFade()

                // Vrije beschrijving + send.
                HStack(spacing: DSSpacing.gap2) {
                    DSTextField(placeholder: "Describe a color or style", text: $prompt)
                    Button {
                        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        Task { await model.apply(freeText: trimmed, base: baseImage, portrait: portrait) }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: DSIconSize.base, weight: .semibold))
                            .foregroundStyle(DSColor.Action.onAction)
                            .frame(width: 40, height: 40)
                            .background(DSColor.Action.primary)
                            .clipShape(Circle())
                            .opacity(prompt.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                    .dsFocusEffectDisabled()
                    .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cloudFeatureMuted()
            .disabled(model.isBusy)
        }
        .task {
            guard HairPanel.sessionCache == nil else { return }
            if let fetched = try? await entitlement.backend.hairPresets(), !fetched.isEmpty {
                HairPanel.sessionCache = fetched
                cmsPresets = fetched
            }
        }
    }
}
