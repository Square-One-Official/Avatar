// Face-paneel (E21.1, herzien E24.15 + E24.15-rev) — de generatieve Pro-acties
// (Whiten teeth/Apply make-up/Reduce wrinkles, 4 credits) in ÉÉN horizontaal-
// scrollbare rij gedeelde thumbnail-kaarten (DSThumbnailCard, dezelfde vorm als
// Effects). One-click retouch verhuisde naar Enhance (Thierry, 2026-06-23) — een
// lokale/gratis actie hoort bij de andere appearance-toggles. Restore body hoort
// hier ook NIET (→ Enhance, E24.9/E31.3).
//
// E32.1: de drie Beauty-acties zijn nu ECHT gewired op de face-intent van
// /v1/stylize (nano-banana instruction-edit) via FaceEffectsModel — daarvoor
// (E18.2) waren ze stubs die alleen de contextuele gate openden.

import AppKit
import AvatarKit
import AvatarUI
import PhosphorSwift
import SwiftUI

/// Stuurt de generatieve face-edits (Whiten teeth/Apply make-up/Reduce
/// wrinkles) aan en reikt het resultaat omhoog naar de ShellModel (canvas +
/// opgeslagen cutout). Spiegelt EffectsModel: gate → working-toast → backend →
/// onApply → saldo-refresh; 402 → paywall. Anders dan Effects is er geen
/// effect-cache: een face-edit is een eenmalige bewerking op het huidige beeld
/// (undo'baar via de onApply-helper in EditorView), niet een aan/uit-toggle.
@MainActor
@Observable
final class FaceEffectsModel {
    enum Phase: Equatable {
        case idle
        case working(String) // label of the active preset
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    private let entitlement: EntitlementModel
    private let baseImage: NSImage
    private let portrait: Portrait2?
    private let coordinator: StylizeQualityCoordinator?
    private let onApply: (NSImage) -> Void

    init(
        entitlement: EntitlementModel,
        baseImage: NSImage,
        portrait: Portrait2? = nil,
        coordinator: StylizeQualityCoordinator? = nil,
        onApply: @escaping (NSImage) -> Void
    ) {
        self.entitlement = entitlement
        self.baseImage = baseImage
        self.portrait = portrait
        self.coordinator = coordinator
        self.onApply = onApply
    }

    var isBusy: Bool { if case .working = phase { return true } else { return false } }

    /// De titel van de kaart die momenteel verwerkt (nil = idle) — voedt de
    /// spinner/dim-logica in FaceActionsPanel, net als EffectsPanel.isWorking.
    var workingTitle: String? {
        if case let .working(label) = phase { return label }
        return nil
    }

    /// Tik op een Beauty-kaart: gate → genereren. Tijdens een lopende edit
    /// negeren we tikken.
    func apply(presetKey: String, label: String) {
        guard !isBusy else { return }
        Task { await generate(presetKey: presetKey, label: label) }
    }

    private func generate(presetKey: String, label: String) async {
        guard entitlement.allowCloudFeature() else { return }

        let source = StylizeQuality.editStylizeSource(cutout: baseImage)
        _ = await coordinator?.gateBeforeStylize(
            source: source, portrait: portrait, cutout: baseImage, isEffects: false
        )
        let cutoutBefore = NSImage(data: portrait?.cutoutData ?? Data()) ?? baseImage

        guard let png = source.pngData() else {
            entitlement.presentError("Couldn't read the portrait.")
            return
        }
        let (cutoutW, cutoutH) = StylizeQuality.cutoutDimensions(for: cutoutBefore)
        phase = .working(label)
        entitlement.presentWorking(
            title: label,
            messages: [
                "Reading the portrait…",
                "Working on the details…",
                "Keeping it natural…",
                "Almost there…",
                "Adding the finishing touches…",
            ]
        )
        do {
            let result = try await entitlement.backend.editFace(
                imagePNG: png, presetKey: presetKey,
                cutoutWidth: cutoutW, cutoutHeight: cutoutH
            )
            guard let image = NSImage(data: result.data) else {
                phase = .idle
                entitlement.dismissWorkingToast()
                entitlement.presentError("The edited image came back unreadable.")
                return
            }
            StylizeQuality.logStylizeDimensions(input: source, output: image, cutoutBefore: cutoutBefore)
            phase = .idle
            entitlement.dismissWorkingToast()
            onApply(image)
            coordinator?.offerPostBoostIfNeeded(result: image, cutoutBefore: cutoutBefore)
            await entitlement.refresh()
        } catch BackendError.noCredits {
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.handleOutOfCredits()
        } catch {
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.presentError("Couldn't apply that edit. Please try again.")
        }
    }
}

struct FaceActionsPanel: View {
    let baseImage: NSImage
    let entitlement: EntitlementModel
    var portrait: Portrait2?
    var coordinator: StylizeQualityCoordinator?
    /// E32.1: resultaat van een generatieve face-edit toepassen (undo'baar).
    var onApply: (NSImage) -> Void = { _ in }
    var isPro: Bool = false

    @State private var model: FaceEffectsModel
    @State private var cmsPresets: [RemotePreset] = []

    private static var sessionCache: [RemotePreset]? = nil

    private static let fallbackPresets: [RemotePreset] = FaceEdit.allCases.enumerated().map {
        RemotePreset(key: $0.element.rawValue, label: $0.element.label, order: $0.offset)
    }

    private var presets: [RemotePreset] {
        cmsPresets.isEmpty ? FaceActionsPanel.fallbackPresets : cmsPresets
    }

    // Bekende icon-mapping per preset-sleutel (voor nu alleen de 3 bestaande).
    private func icon(for key: String) -> Ph {
        switch key {
        case "whiten-teeth": return .tooth
        case "apply-makeup": return .palette
        case "reduce-wrinkles": return .smiley
        default: return .sparkle
        }
    }

    init(
        baseImage: NSImage,
        entitlement: EntitlementModel,
        portrait: Portrait2? = nil,
        coordinator: StylizeQualityCoordinator? = nil,
        onApply: @escaping (NSImage) -> Void = { _ in },
        isPro: Bool = false
    ) {
        self.baseImage = baseImage
        self.entitlement = entitlement
        self.portrait = portrait
        self.coordinator = coordinator
        self.onApply = onApply
        self.isPro = isPro
        _model = State(initialValue: FaceEffectsModel(
            entitlement: entitlement,
            baseImage: baseImage,
            portrait: portrait,
            coordinator: coordinator,
            onApply: onApply
        ))
        _cmsPresets = State(initialValue: FaceActionsPanel.sessionCache ?? [])
    }

    private let cardWidth: CGFloat = 112
    private let cardHeight: CGFloat = 152

    var body: some View {
        let workingTitle = model.workingTitle
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.gap2) {
                ForEach(presets) { preset in
                    let isWorking = workingTitle == preset.label
                    Button {
                        model.apply(presetKey: preset.key, label: preset.label)
                    } label: {
                        DSThumbnailCard(
                            label: preset.label,
                            isPro: !isPro,
                            isSelected: false,
                            isWorking: isWorking,
                            tileSize: cardWidth,
                            tileHeight: cardHeight
                        ) {
                            icon(for: preset.key).regular
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(workingTitle != nil)
                    .opacity(workingTitle != nil && !isWorking ? 0.5 : 1)
                }
            }
            .padding(.vertical, DSSpacing.gap2)
            .padding(.leading, DSSpacing.gap1_5)
            .scrollRowTrailingInset()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .horizontalScrollEdgeFade()
        .task {
            guard FaceActionsPanel.sessionCache == nil else { return }
            if let fetched = try? await entitlement.backend.facePresets(), !fetched.isEmpty {
                FaceActionsPanel.sessionCache = fetched
                cmsPresets = fetched
            }
        }
    }
}
