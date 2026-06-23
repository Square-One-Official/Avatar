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
    /// De beschikbare stijlen (CMS-gestuurd, E33). Start op de fallback zodat het
    /// paneel nooit leeg opent; `loadEffects()` vervangt 'm met de CMS-lijst.
    private(set) var remoteEffects: [RemoteEffect] = RemoteEffect.fallback

    private let entitlement: EntitlementModel
    private let onApply: (NSImage) -> Void
    private let portrait: Portrait2?
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
        onApply: @escaping (NSImage) -> Void
    ) {
        self.entitlement = entitlement
        self.onApply = onApply
        self.portrait = portrait

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
        remoteEffects = fetched
        let activeKey = selected?.key ?? portrait?.effectActiveRaw
        if let activeKey {
            selected = fetched.first { $0.key == activeKey } ?? selected
        }
    }

    /// None-kaart: terug naar het basisbeeld (instant, geen credits).
    func selectNone() {
        guard !isBusy, selected != nil else { return }
        selected = nil
        phase = .idle
        onApply(base)
        persist()
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
            // Cache-hit: INSTANT, geen backend-call, geen credits (E24.33).
            selected = effect
            phase = .idle
            onApply(cached)
            persist()
            return
        }
        Task { await generate(effect) }
    }

    /// Refresh-icoon op de actieve kaart: bewust opnieuw genereren (kost credits).
    func regenerate(_ effect: RemoteEffect) {
        guard !isBusy else { return }
        Task { await generate(effect) }
    }

    private func generate(_ effect: RemoteEffect) async {
        // E18.2: contextuele gate (online uit → login → upgrade).
        guard entitlement.allowCloudFeature() else { return }
        guard let png = base.pngData() else {
            entitlement.presentError("Couldn't read the portrait.")
            return
        }
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
            let (data, _) = try await entitlement.backend.stylize(imagePNG: png, styleKey: effect.key)
            guard let image = NSImage(data: data) else {
                phase = .idle
                entitlement.dismissWorkingToast()
                entitlement.presentError("The styled image came back unreadable.")
                return
            }
            cache[effect.key] = image
            if let png = image.pngData() { pngCache[effect.key] = png }
            selected = effect
            phase = .idle
            entitlement.dismissWorkingToast()
            onApply(image)
            persist()
            // Saldo bijwerken zodat de topbar-quota klopt na de aftrek.
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
    var onApply: (NSImage) -> Void = { _ in }

    @State private var model: EffectsModel

    init(
        baseImage: NSImage,
        entitlement: EntitlementModel,
        portrait: Portrait2? = nil,
        onApply: @escaping (NSImage) -> Void = { _ in }
    ) {
        self.baseImage = baseImage
        self.entitlement = entitlement
        self.portrait = portrait
        self.onApply = onApply
        _model = State(initialValue: EffectsModel(
            entitlement: entitlement, baseImage: baseImage, portrait: portrait, onApply: onApply
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
    /// terwijl 'ie laadt of als het effect geen thumbnail heeft.
    @ViewBuilder
    private func thumbnail(for effect: RemoteEffect) -> some View {
        if let url = effect.thumbnailUrl {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
            } placeholder: {
                placeholderIcon
            }
        } else {
            placeholderIcon
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 28, weight: .regular))
    }
}
