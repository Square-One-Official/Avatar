// Clothes-paneel (E10.2 + E10.4-wiring, Figma App / Clothes 4016:13760):
// "Change upper clothes" + vaste outfit-chips + een vrije prompt ("Describe
// a color or style") met lime send-knop.
//
// Generatie-route (besluit Thierry 2026-06-13): nano-banana instruction-edit
// via het productie-`/v1/stylize` (clothes-intent, E10.4). Hard
// acceptatiecriterium server-side afgedwongen: alléén de kleding wijzigt,
// gezicht/haar/pose/achtergrond identiek. FLUX-Fill + mask (E10.1) blijft de
// precisie-fallback, geen default. Credit-gegated (generatief standaard = 4),
// 402 → paywall.

import AppKit
import AvatarKit
import AvatarUI
import SwiftUI

/// Stuurt de kledingwissel aan en reikt het resultaat omhoog naar de
/// ShellModel (canvas + opgeslagen cutout). Zelfde patroon als HairModel.
@MainActor
@Observable
final class ClothesModel {
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
        guard entitlement.allowAIFeature(.clothesEdit) else { return }

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
            title: "Changing clothing",
            messages: [
                "Picking the right fit…",
                "Pressing the wrinkles out…",
                "Checking the stitching…",
                "Did someone say outfit change?",
                "Looking sharp…",
                "Almost dressed…",
            ]
        )
        do {
            let softSource = StylizeQuality.requestsSoftSourcePrompt(for: source)
            let result = try await entitlement.backend.editClothes(
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
        } catch {
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.presentError("Couldn't change the clothing. Please try again.")
        }
    }

}

struct ClothesPanel: View {
    let baseImage: NSImage
    let entitlement: EntitlementModel
    var portrait: Portrait2?
    var coordinator: StylizeQualityCoordinator?
    var onApply: (NSImage) async -> Void = { _ in }

    @State private var model: ClothesModel
    @State private var prompt = ""
    @State private var cmsPresets: [RemotePreset] = []

    private static var sessionCache: [RemotePreset]? = nil

    private static let fallbackPresets: [RemotePreset] = ClothesStyle.allCases.enumerated().map {
        RemotePreset(key: $0.element.rawValue, label: $0.element.label, order: $0.offset)
    }

    private var presets: [RemotePreset] {
        cmsPresets.isEmpty ? ClothesPanel.fallbackPresets : cmsPresets
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
        _model = State(initialValue: ClothesModel(entitlement: entitlement, coordinator: coordinator, onApply: onApply))
        _cmsPresets = State(initialValue: ClothesPanel.sessionCache ?? [])
    }

    var body: some View {
        DSEditPanel(title: "Change upper clothes", credits: CreditMeter.chipLabel(for: .generativeStandard)) {
            VStack(alignment: .leading, spacing: DSSpacing.gap4) {

                // Outfit-presets (CMS-gestuurd; fallback: ClothesStyle.allCases).
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DSColor.Action.onAction)
                            .frame(width: 40, height: 40)
                            .background(DSColor.Action.primary)
                            .clipShape(Circle())
                            .opacity(prompt.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(model.isBusy)
        }
        .task {
            guard ClothesPanel.sessionCache == nil else { return }
            if let fetched = try? await entitlement.backend.clothesPresets(), !fetched.isEmpty {
                ClothesPanel.sessionCache = fetched
                cmsPresets = fetched
            }
        }
    }
}
