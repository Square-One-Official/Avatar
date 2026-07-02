// Effects-paneel (E09.2, Figma App / Effects): een "None"-kaart (terug naar
// origineel) + de stijl-kaarten. E24.33: de gekozen stijl is de active state;
// nogmaals tikken = None. Resultaten worden per effect op het portret GECACHET
// → None ↔ effect ↔ ander effect is INSTANT en kost geen nieuwe credits; alleen
// het refresh-icoon in de actieve thumbnail hergenereert bewust (kost dan wel
// credits). Generatie via productie-`/v1/stylize` (nano-banana default),
// credit-gegated, 402 → paywall-toast.
//
// E33: de stijl-lijst is CMS-gestuurd. De kaarten + thumbnails + keys komen uit
// Payload (`backend.effects()`); een nieuw effect verschijnt zonder app-release.
// Tot de fetch landt (of bij offline) draait het paneel op `RemoteEffect.fallback`
// (de vier launch-keys, zonder thumbnail).

import AppKit
import AvatarKit
import AvatarUI
import SwiftUI

/// Stuurt de stijl-generatie aan en reikt het resultaat omhoog naar de
/// ShellModel (die canvas + opgeslagen cutout vervangt). De Effects-staat
/// (basisbeeld, actief effect, cache) persisteert op het portret (E24.33) zodat
/// schakelen instant + gratis is en het paneel heropenen de cache behoudt.
@MainActor
@Observable
final class EffectsModel {
    enum Phase: Equatable {
        case idle
        case working(RemoteEffect)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Het toegepaste effect (active state), nil = None (basisbeeld).
    private(set) var selected: RemoteEffect?
    /// Ingesteld door EffectsPanel via de SwiftUI-omgeving zodat selectie-wijzigingen
    /// in hetzelfde undo-groepje als de bijbehorende beeld-swap landen.
    var undoManager: UndoManager?
    /// Sessie-cache: gedeeld over alle instanties zodat herhaaldelijk openen van
    /// het paneel niet terugvalt op de hardgecodeerde fallback. Leeg = eerste open.
    private static var sessionCache: [RemoteEffect] = []

    /// De beschikbare stijlen (CMS-gestuurd, E33). Start op de sessie-cache als
    /// die al gevuld is (eerder geladen in dezelfde sessie), anders op de fallback.
    private(set) var remoteEffects: [RemoteEffect] =
        EffectsModel.sessionCache.isEmpty ? RemoteEffect.fallback : EffectsModel.sessionCache

    private let entitlement: EntitlementModel
    private let onApply: (NSImage) async -> Void
    private let portrait: Portrait2?
    private let coordinator: StylizeQualityCoordinator?
    private let cutoutImage: NSImage
    /// Het "None"/origineel-beeld waarop effecten worden gegenereerd.
    private(set) var base: NSImage
    /// Sessie-cache (gehydrateerd uit het portret) — key → beeld.
    private var cache: [String: NSImage]
    /// PNG-encodes parallel aan `cache`, één keer ge-encodeerd per effect, zodat
    /// `persist()` alleen kopieert i.p.v. élke toggle de hele cache te her-encoden.
    private var pngCache: [String: Data]

    init(
        entitlement: EntitlementModel,
        baseImage: NSImage,
        portrait: Portrait2?,
        cutoutImage: NSImage,
        coordinator: StylizeQualityCoordinator?,
        onApply: @escaping (NSImage) async -> Void
    ) {
        self.entitlement = entitlement
        self.onApply = onApply
        self.portrait = portrait
        self.cutoutImage = cutoutImage
        self.coordinator = coordinator

        // Hydrateer uit het portret (E24.33). Cache + basis zijn key-gestuurd
        // (string), LOS van de CMS-lijst: zo blijft de hydratie correct ook als
        // het actieve effect (nog) niet in de geladen lijst zit (offline /
        // CMS-only effect vóór de fetch landt). Met een actief effect is
        // `baseImage` (de huidige cutout) het effect-beeld; de echte basis staat
        // dan in `effectBaseData`. Zonder actief effect ÍS de cutout de basis.
        let activeKey = portrait?.effectActiveRaw
        if activeKey != nil, let data = portrait?.effectBaseData, let img = NSImage(data: data) {
            self.base = img
        } else {
            self.base = baseImage
        }
        var hydrated: [String: NSImage] = [:]
        var hydratedPNG: [String: Data] = [:]
        for (key, data) in portrait?.effectCache ?? [:] {
            if let img = NSImage(data: data) {
                hydrated[key] = img
                hydratedPNG[key] = data
            }
        }
        // Het actieve effect-beeld is de huidige cutout, ook als de cache nog leeg
        // is (bv. gegenereerd vóór deze cache bestond).
        if let activeKey, hydrated[activeKey] == nil {
            hydrated[activeKey] = baseImage
            if let png = baseImage.pngData() { hydratedPNG[activeKey] = png }
        }
        self.cache = hydrated
        self.pngCache = hydratedPNG

        // Resolveer de selectie tegen de (fallback-)lijst; `loadEffects()`
        // herresolveert zodra de CMS-lijst binnen is.
        self.selected = activeKey.flatMap { k in remoteEffects.first { $0.key == k } }
    }

    /// Het beeld dat naar de stylize-backend gaat — zie `StylizeQuality.effectsStylizeSource`.
    private func stylizeSource(choice: StylizeQuality.EffectsSourceChoice) -> NSImage {
        StylizeQuality.effectsStylizeSource(portrait: portrait, cutout: cutoutImage, choice: choice)
    }

    var creditCost: Int { CreditMeter.credits(for: .generativeStandard) }

    var isBusy: Bool { if case .working = phase { return true } else { return false } }

    func isCached(_ effect: RemoteEffect) -> Bool { cache[effect.key] != nil }

    /// Haal de CMS-stijllijst op (E33). Soft-fail: bij een lege/gefaalde fetch
    /// houden we de fallback zodat het paneel bruikbaar blijft. Na succes
    /// herresolveren we de actieve selectie tegen de verse lijst zodat de
    /// selectie-ring naar dezelfde waarde wijst als de kaart (Equatable).
    func loadEffects() async {
        let fetched = (try? await entitlement.backend.effects()) ?? []
        guard !fetched.isEmpty else { return }
        EffectsModel.sessionCache = fetched
        remoteEffects = fetched
        let activeKey = selected?.key ?? portrait?.effectActiveRaw
        if let activeKey {
            selected = fetched.first { $0.key == activeKey } ?? selected
        }
        // E52.1: warm de gedeelde thumbnail-cache (memory + disk, downsampled
        // decode). De kaarten renderen via `RemoteThumbnail`, dus geen eigen
        // NSCache/thumbnailVersion-boekhouding meer.
        ThumbnailCache.shared.prefetch(fetched.compactMap(\.thumbnailUrl))
    }

    /// None-kaart: terug naar het basisbeeld (instant, geen credits).
    func selectNone() {
        guard !isBusy, selected != nil else { return }
        let prevSelected = selected
        selected = nil
        phase = .idle
        Task {
            await onApply(base)
            registerSelectionUndo(from: prevSelected, to: nil)
            persist()
        }
    }

    /// Tik op een effect-kaart: actief → None; gecachet → instant uit cache;
    /// anders → genereren. Tijdens een lopende generatie negeren we tikken.
    func toggle(_ effect: RemoteEffect) {
        guard !isBusy else { return }
        if selected == effect {
            selectNone()
            return
        }
        if let cached = cache[effect.key] {
            // Cache-hit: instant uit cache, maar her-isolatie kan even duren.
            let prevSelected = selected
            selected = effect
            Task {
                phase = .working(effect)
                entitlement.presentWorking(
                    title: "Applying style",
                    messages: ["Cutting out the subject…", "Almost there…"]
                )
                await onApply(cached)
                phase = .idle
                entitlement.dismissWorkingToast()
                registerSelectionUndo(from: prevSelected, to: effect)
                persist()
            }
            return
        }
        Task { await generate(effect) }
    }

    /// Refresh-icoon op de actieve kaart: bewust opnieuw genereren (kost credits).
    func regenerate(_ effect: RemoteEffect) {
        guard !isBusy else { return }
        Task { await generate(effect, feature: .effectRegenerate) }
    }

    private func generate(_ effect: RemoteEffect, feature: AIFeature = .effectGenerate) async {
        guard entitlement.allowAIFeature(feature) else { return }

        let defaultChoice = StylizeQuality.defaultEffectsSourceChoice(portrait: portrait)
        let (_, effectsChoice) = await coordinator?.gateBeforeStylize(
            source: stylizeSource(choice: defaultChoice),
            portrait: portrait,
            cutout: cutoutImage,
            isEffects: true
        ) ?? (.proceed, defaultChoice)
        let source = stylizeSource(choice: effectsChoice)
        let cutoutBefore = NSImage(data: portrait?.cutoutData ?? Data()) ?? cutoutImage

        guard let png = source.pngData() else {
            entitlement.presentError("Couldn't read the portrait.")
            return
        }
        let (cutoutW, cutoutH) = StylizeQuality.cutoutDimensions(for: cutoutBefore)
        phase = .working(effect)
        entitlement.presentWorking(
            title: "Applying style",
            messages: [
                "Mixing the palette…",
                "Laying on the texture…",
                "Tweaking the shadows…",
                "This one's going to look good…",
                "Adding the finishing touches…",
                "Almost there…",
            ]
        )
        do {
            let softSource = StylizeQuality.requestsSoftSourcePrompt(for: source)
            // Cutout én origineel: geen reframe — achtergrond zit los van het cutout.
            let preserveFraming = true
            let result = try await entitlement.backend.stylize(
                imagePNG: png, styleKey: effect.key,
                cutoutWidth: cutoutW, cutoutHeight: cutoutH,
                softSource: softSource,
                preserveFraming: preserveFraming
            )
            guard let image = NSImage(data: result.data) else {
                phase = .idle
                entitlement.dismissWorkingToast()
                entitlement.presentError("The styled image came back unreadable.")
                return
            }
            StylizeQuality.logStylizeDimensions(input: source, output: image, cutoutBefore: cutoutBefore)
            cache[effect.key] = image
            if let png = image.pngData() { pngCache[effect.key] = png }
            let prevSelected = selected
            selected = effect
            await onApply(image)
            phase = .idle
            entitlement.dismissWorkingToast()
            registerSelectionUndo(from: prevSelected, to: effect)
            persist()
            await entitlement.refresh()
        } catch BackendError.noCredits {
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.handleOutOfCredits()
        } catch {
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.presentError("Couldn't apply that style. Please try again.")
        }
    }

    /// Registreert selectie-undo naast de beeld-swap zodat Cmd+Z de badge én
    /// het canvas in één keer terugzet. Beide registraties vallen in hetzelfde
    /// NSUndoManager-auto-groepje (zelfde run-loop cyclus) → één Cmd+Z.
    /// Target is het portret (SwiftData), niet `self`: EffectsModel leeft alleen
    /// zolang het paneel open is — na sluiten crashte een tweede undo op een
    /// dangling weak ref.
    private func registerSelectionUndo(from previous: RemoteEffect?, to next: RemoteEffect?) {
        guard let portrait else { return }
        ReversibleChange.register(
            undoManager, target: portrait,
            from: previous, to: next,
            actionName: "Apply effect"
        ) { [weak self] p, sel in
            p.effectActiveRaw = sel?.key
            self?.selected = sel
        }
    }

    /// Persisteer de Effects-staat op het portret (E24.33).
    private func persist() {
        guard let portrait else { return }
        if portrait.effectBaseData == nil {
            portrait.effectBaseData = base.pngData()
        }
        portrait.effectActiveRaw = selected?.key
        // pngCache is al ge-encodeerd (één keer per effect) — alleen kopiëren,
        // geen her-encode van de hele cache per toggle (perf).
        portrait.effectCache = pngCache
    }

}

struct EffectsPanel: View {
    let baseImage: NSImage
    let entitlement: EntitlementModel
    var portrait: Portrait2?
    var coordinator: StylizeQualityCoordinator?
    var onApply: (NSImage) async -> Void = { _ in }

    @State private var model: EffectsModel
    @Environment(\.undoManager) private var undoManager

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
        _model = State(initialValue: EffectsModel(
            entitlement: entitlement,
            baseImage: baseImage,
            portrait: portrait,
            cutoutImage: baseImage,
            coordinator: coordinator,
            onApply: onApply
        ))
    }

    private let cardWidth: CGFloat = 112
    private let cardHeight: CGFloat = 152

    var body: some View {
        DSEditPanel(title: "Effects", credits: CreditMeter.chipLabel(for: .generativeStandard)) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.gap2) {
                    noneCard
                    ForEach(model.remoteEffects) { effect in
                        styleCard(effect)
                    }
                }
                .padding(.vertical, DSSpacing.gap2)
                .padding(.leading, DSSpacing.gap1_5)
                .scrollRowTrailingInset()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .horizontalScrollEdgeFade()
        }
        // E33: CMS-lijst ophalen bij openen. Soft-fail houdt de fallback.
        .task { await model.loadEffects() }
        .onAppear { model.undoManager = undoManager }
    }

    /// E24.33: "None"-kaart helemaal links — terug naar het origineel (basis).
    private var noneCard: some View {
        Button {
            model.selectNone()
        } label: {
            DSThumbnailCard(
                label: "None",
                isSelected: model.selected == nil,
                tileSize: cardWidth,
                tileHeight: cardHeight
            ) {
                Image(nsImage: model.base)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .opacity(model.isBusy ? 0.5 : 1)
    }

    private func styleCard(_ effect: RemoteEffect) -> some View {
        let isSelected = model.selected == effect
        let isWorking = model.phase == .working(effect)
        return Button {
            model.toggle(effect)
        } label: {
            DSThumbnailCard(
                label: effect.label,
                isSelected: isSelected,
                isWorking: isWorking,
                tileSize: cardWidth,
                tileHeight: cardHeight,
                onRefresh: isSelected ? { model.regenerate(effect) } : nil
            ) {
                thumbnail(for: effect)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .opacity(model.isBusy && !isWorking ? 0.5 : 1)
    }

    /// CMS-thumbnail (E33) die de tile vult; valt terug op het sparkles-icoon
    /// terwijl 'ie laadt of als het effect geen thumbnail heeft. E52.1: via de
    /// gedeelde `ThumbnailCache` (memory + disk + downsampled decode) i.p.v.
    /// AsyncImage — her-opens zijn instant, ook na een app-herstart.
    @ViewBuilder
    private func thumbnail(for effect: RemoteEffect) -> some View {
        if let url = effect.thumbnailUrl {
            RemoteThumbnail(url: url) {
                placeholderIcon
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipped()
        } else {
            placeholderIcon
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 28, weight: .regular))
    }
}
