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
//
// E32.3: "Whiten teeth" is een twee-armige kaart geworden (besluit Thierry
// 2026-08-03): een dropdown kiest tussen On device (gratis, TeethWhitener —
// gelokaliseerd, pixel-exact buiten de mond) en Cloud (best quality, 4 credits,
// Pro). De andere presets blijven single-tap cloud. Tegelijk is het stale-base-
// defect gefixt: het model bevroor `baseImage` bij panel-init, waardoor een
// tweede face-edit de pre-edit cutout opnieuw instuurde — de view geeft de
// actuele base nu per tik mee (zelfde patroon als ClothesModel/HairModel).

import AppKit
import AvatarKit
import AvatarUI
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
    private let coordinator: StylizeQualityCoordinator?
    private let onApply: (NSImage) async -> Void

    init(
        entitlement: EntitlementModel,
        coordinator: StylizeQualityCoordinator? = nil,
        onApply: @escaping (NSImage) async -> Void
    ) {
        self.entitlement = entitlement
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
    /// negeren we tikken. E32.3: `base`/`portrait` komen per tik van de view
    /// (vers per render) i.p.v. bevroren bij init — een tweede edit bouwt zo
    /// op het resultaat van de eerste.
    func apply(presetKey: String, label: String, base: NSImage, portrait: Portrait2?) {
        guard !isBusy else { return }
        Task { await generate(presetKey: presetKey, label: label, base: base, portrait: portrait) }
    }

    /// E32.3: de gratis on-device arm van "Whiten teeth" — TeethWhitener
    /// (Vision-landmarks + Core Image, alléén het mondgebied verandert).
    /// Geen entitlement-gate en geen credits: on-device, net als Remove
    /// background en One-click retouch.
    func applyLocalTeethWhiten(base: NSImage, label: String) {
        guard !isBusy else { return }
        guard let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            entitlement.presentError("Couldn't read the portrait.")
            return
        }
        phase = .working(label)
        entitlement.presentWorking(
            title: "Whitening teeth",
            messages: ["Working on your Mac…", "Brightening the smile…", "Keeping it private…"]
        )
        let box = SendableCGImage(cgImage: cg)
        Task {
            let outcome: Result<SendableCGImage, TeethWhitener.Failure> =
                await Task.detached(priority: .userInitiated) {
                    do {
                        let out = try await TeethWhitener().whiten(box.cgImage)
                        return .success(SendableCGImage(cgImage: out))
                    } catch let failure as TeethWhitener.Failure {
                        return .failure(failure)
                    } catch {
                        return .failure(.renderFailed)
                    }
                }.value
            phase = .idle
            entitlement.dismissWorkingToast()
            switch outcome {
            case .success(let boxed):
                let out = boxed.cgImage
                await onApply(NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height)))
            case .failure(.noFaceFound):
                entitlement.presentError(
                    "Couldn't find a face in this photo. For tricky crops, try the Cloud option."
                )
            case .failure(.mouthNotVisible):
                entitlement.presentError(
                    "No visible teeth to whiten here — the mouth looks closed."
                )
            case .failure(.renderFailed):
                entitlement.presentError("Couldn't whiten the teeth. Please try again.")
            }
        }
    }

    private func generate(presetKey: String, label: String, base: NSImage, portrait: Portrait2?) async {
        guard entitlement.allowAIFeature(.faceEdit) else { return }

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
            let softSource = StylizeQuality.requestsSoftSourcePrompt(for: source)
            let result = try await entitlement.backend.editFace(
                imagePNG: png, presetKey: presetKey,
                cutoutWidth: cutoutW, cutoutHeight: cutoutH,
                softSource: softSource
            )
            guard let image = NSImage(data: result.data) else {
                phase = .idle
                entitlement.dismissWorkingToast()
                entitlement.presentError("The edited image came back unreadable.")
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
            entitlement.presentError("Couldn't apply that edit. Please try again.")
        }
    }
}

/// Levert de bounds van de Whiten teeth-kaart omhoog zodat het dropdown-paneel
/// buiten de gemaskeerde scroll-rij kan renderen (ChipAnchorKey-patroon uit
/// EditColorPanel). Het menu zweeft ÓVER de kaart (top-aligned): het paneel is
/// maar één rij hoog en zit in DSEditPanels verticale ScrollView — onder of
/// boven de kaart zou het geclipt worden.
private struct WhitenAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct FaceActionsPanel: View {
    let baseImage: NSImage
    let entitlement: EntitlementModel
    var portrait: Portrait2?
    var coordinator: StylizeQualityCoordinator?
    /// E32.1: resultaat van een generatieve face-edit toepassen (undo'baar).
    var onApply: (NSImage) async -> Void = { _ in }
    var isPro: Bool = false

    @State private var model: FaceEffectsModel
    @State private var cmsPresets: [RemotePreset] = []
    /// E32.3: On device/Cloud-keuze voor Whiten teeth.
    @State private var whitenMenuOpen = false

    private static var sessionCache: [RemotePreset]? = nil

    private static let fallbackPresets: [RemotePreset] = FaceEdit.allCases.enumerated().map {
        RemotePreset(key: $0.element.rawValue, label: $0.element.label, order: $0.offset)
    }

    private var presets: [RemotePreset] {
        cmsPresets.isEmpty ? FaceActionsPanel.fallbackPresets : cmsPresets
    }

    private var whitenLabel: String {
        presets.first { $0.key == FaceEdit.whitenTeeth.rawValue }?.label
            ?? FaceEdit.whitenTeeth.label
    }

    // Bekende icon-mapping per preset-sleutel (voor nu alleen de 3 bestaande).
    // E49.4: via DSIcon (SF Symbols); de bedoelde Phosphor-namen wonen dáár.
    private func icon(for key: String) -> DSIcon.Symbol {
        switch key {
        case "whiten-teeth": return .whitenTeeth
        case "apply-makeup": return .applyMakeup
        case "reduce-wrinkles": return .reduceWrinkles
        default: return .sparkle
        }
    }

    init(
        baseImage: NSImage,
        entitlement: EntitlementModel,
        portrait: Portrait2? = nil,
        coordinator: StylizeQualityCoordinator? = nil,
        onApply: @escaping (NSImage) async -> Void = { _ in },
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
                    let isWhiten = preset.key == FaceEdit.whitenTeeth.rawValue
                    Button {
                        if isWhiten {
                            whitenMenuOpen.toggle()
                        } else {
                            model.apply(
                                presetKey: preset.key, label: preset.label,
                                base: baseImage, portrait: portrait
                            )
                        }
                    } label: {
                        DSThumbnailCard(
                            label: preset.label,
                            // E32.3: de whiten-kaart heeft een gratis arm —
                            // geen blanket Pro-badge; Pro/credits staan op de
                            // Cloud-rij in het menu.
                            isPro: isWhiten ? false : !isPro,
                            isSelected: false,
                            isWorking: isWorking,
                            tileSize: cardWidth,
                            tileHeight: cardHeight
                        ) {
                            // E52.1: optionele CMS-thumbnail (verkleinde
                            // render-variant, gedeelde disk-cache); zonder
                            // thumbnail blijft het bekende preset-icoon staan.
                            if let url = preset.thumbnailUrl {
                                RemoteThumbnail(url: url) {
                                    DSIcon(icon(for: preset.key), size: 32)
                                        .frame(width: 36, height: 36)
                                }
                                .frame(width: cardWidth, height: cardHeight)
                                .clipped()
                            } else {
                                DSIcon(icon(for: preset.key), size: 32)
                                    .frame(width: 36, height: 36)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if isWhiten {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: DSIconSize.xxs, weight: .semibold))
                                    .foregroundStyle(DSColor.Foreground.muted)
                                    .padding(DSSpacing.gap2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(workingTitle != nil)
                    .opacity(workingTitle != nil && !isWorking ? 0.5 : 1)
                    .anchorPreference(key: WhitenAnchorKey.self, value: .bounds) {
                        isWhiten ? $0 : nil
                    }
                }
            }
            .padding(.vertical, DSSpacing.gap2)
            .padding(.leading, DSSpacing.gap1_5)
            .scrollRowTrailingInset()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .horizontalScrollEdgeFade()
        // Het Whiten-dropdown-paneel leeft BUITEN de gemaskeerde scroll-rij
        // (EditColorPanel-patroon) zodat de rij-mask het niet afkapt.
        .overlayPreferenceValue(WhitenAnchorKey.self) { anchor in
            whitenMenuOverlay(anchor)
        }
        .task {
            guard FaceActionsPanel.sessionCache == nil else { return }
            if let fetched = try? await entitlement.backend.facePresets(), !fetched.isEmpty {
                FaceActionsPanel.sessionCache = fetched
                cmsPresets = fetched
                // E52.1: warm de gedeelde thumbnail-cache voor presets mét preview.
                ThumbnailCache.shared.prefetch(fetched.compactMap(\.thumbnailUrl))
            }
        }
    }

    /// De twee armen van Whiten teeth. On device = gratis TeethWhitener;
    /// Cloud = de bestaande face-intent (4 credits, Pro-gate via
    /// allowAIFeature in het model).
    private var whitenMenu: some View {
        let cloudCost = CreditMeter.chipLabel(for: .generativeStandard)
        return DSContextMenuPanel(minWidth: 240) {
            DSMenuRow("On device", icon: "desktopcomputer", shortcut: "Free · On device") {
                whitenMenuOpen = false
                model.applyLocalTeethWhiten(base: baseImage, label: whitenLabel)
            }
            DSMenuRow(
                "Cloud", icon: "cloud",
                shortcut: isPro ? "Best · \(cloudCost)" : "Best · \(cloudCost) · Pro"
            ) {
                whitenMenuOpen = false
                model.apply(
                    presetKey: FaceEdit.whitenTeeth.rawValue, label: whitenLabel,
                    base: baseImage, portrait: portrait
                )
            }
        }
    }

    /// Rendert het open menu zwevend óver de Whiten-kaart plus een
    /// transparante vanglaag die bij een tik erbuiten sluit (zelfde opzet als
    /// EditColorPanel.chipMenuOverlay).
    @ViewBuilder
    private func whitenMenuOverlay(_ anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if whitenMenuOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { whitenMenuOpen = false }
                    if let anchor {
                        let card = proxy[anchor]
                        let menuWidth: CGFloat = 240
                        whitenMenu
                            .fixedSize()
                            .offset(
                                x: max(0, min(card.minX, proxy.size.width - menuWidth)),
                                y: max(0, card.minY)
                            )
                            .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Dicht: laat tikken door naar de kaarten; open: vang ze (vanglaag
        // sluit, menu-rijen reageren).
        .allowsHitTesting(whitenMenuOpen)
        .dsMotion(DSMotion.fast, value: whitenMenuOpen)
    }
}
