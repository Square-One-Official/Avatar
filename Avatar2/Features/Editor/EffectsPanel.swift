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
//
// E34: gebruikers maken hun EIGEN effect. Een "Create effect"-(+)kaart (Pro)
// opent een modal (referentiebeeld + beschrijving); het effect wordt gegenereerd,
// op het portret getoond én bewaard als eigen effect met het referentiebeeld als
// thumbnail. Custom effecten syncen per account (`backend.customEffects()`) en
// delen exact dezelfde cache/persistentie als de built-ins (string-keyed, met de
// `custom:<id>`-namespace).

import AppKit
import AvatarKit
import AvatarUI
import SwiftUI

/// Eén kaart in het paneel: een built-in CMS-stijl of een eigen custom effect.
/// Verenigt beide op de string-cachekey (`key`) zodat selectie, cache en
/// persistentie (effectCache/effectActiveRaw) ongewijzigd blijven.
struct EffectCard: Identifiable, Equatable {
    enum Kind: Equatable { case builtin, custom }
    let key: String          // built-in: effect.key · custom: "custom:<id>"
    let label: String
    let kind: Kind
    let thumbnailUrl: URL?
    let customID: String?    // alleen voor custom: de rij-id (naar /v1/stylize)

    var id: String { key }

    init(_ effect: RemoteEffect) {
        key = effect.key
        label = effect.label
        kind = .builtin
        thumbnailUrl = effect.thumbnailUrl
        customID = nil
    }

    init(_ effect: RemoteCustomEffect) {
        key = effect.cacheKey
        label = effect.label
        kind = .custom
        thumbnailUrl = effect.thumbnailUrl
        customID = effect.id
    }
}

/// Stuurt de stijl-generatie aan en reikt het resultaat omhoog naar de
/// ShellModel (die canvas + opgeslagen cutout vervangt). De Effects-staat
/// (basisbeeld, actief effect, cache) persisteert op het portret (E24.33) zodat
/// schakelen instant + gratis is en het paneel heropenen de cache behoudt.
@MainActor
@Observable
final class EffectsModel {
    enum Phase: Equatable {
        case idle
        case working(String)   // de cachekey van het effect dat genereert
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// De cachekey van het toegepaste effect (active state), nil = None (basis).
    private(set) var selectedKey: String?
    /// Ingesteld door EffectsPanel via de SwiftUI-omgeving zodat selectie-wijzigingen
    /// in hetzelfde undo-groepje als de bijbehorende beeld-swap landen.
    var undoManager: UndoManager?
    /// Sessie-cache: gedeeld over alle instanties zodat herhaaldelijk openen van
    /// het paneel niet terugvalt op de hardgecodeerde fallback. Leeg = eerste open.
    private static var sessionCache: [RemoteEffect] = []
    /// Custom effecten (E34) — ook sessie-gecachet zodat heropenen niet flitst.
    private static var customSessionCache: [RemoteCustomEffect] = []

    /// De built-in stijlen (CMS-gestuurd, E33). Hydratie-volgorde (E55.6):
    /// sessie-cache → disk-snapshot (EffectsListCache) → hardgecodeerde
    /// fallback — gezet in `init` zodat een koude start het paneel mét
    /// thumbnails opent zonder op de netwerk-fetch te wachten.
    private(set) var builtinEffects: [RemoteEffect] = []
    /// De eigen custom effecten (E34). Zelfde hydratie; leeg = nog niet
    /// geladen / geen eigen effecten / niet-Pro.
    private(set) var customEffects: [RemoteCustomEffect] = []

    /// Lokaal geseede thumbnails (E34): meteen na het aanmaken tonen we het
    /// net-gedropte referentiebeeld zonder een round-trip naar de bucket-URL.
    private var localThumbnails: [String: NSImage] = [:]

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
        self.coordinator = coordinator

        // E55.6: lijst-hydratie zonder netwerk — sessie-cache → disk-snapshot
        // → fallback. De disk-lees is enkele KB (sync is prima); de sessie-
        // cache wordt meteen gevuld zodat volgende panelen de disk overslaan.
        if EffectsModel.sessionCache.isEmpty,
           let disk = EffectsListCache.shared.loadEffects(), !disk.isEmpty {
            EffectsModel.sessionCache = disk
        }
        builtinEffects = EffectsModel.sessionCache.isEmpty
            ? RemoteEffect.fallback
            : EffectsModel.sessionCache
        // Custom alleen hydrateren als het account ze mag zien (Pro) — anders
        // zou een uitgelogde/afgeschaalde sessie andermans kaarten tonen.
        if entitlement.isProActive || entitlement.isDevUnlimited {
            if EffectsModel.customSessionCache.isEmpty,
               let disk = EffectsListCache.shared.loadCustomEffects(), !disk.isEmpty {
                EffectsModel.customSessionCache = disk
            }
            customEffects = EffectsModel.customSessionCache
        }

        // Hydrateer uit het portret (E24.33). Cache + basis zijn key-gestuurd
        // (string), LOS van de CMS-lijst: zo blijft de hydratie correct ook als
        // het actieve effect (nog) niet in de geladen lijst zit (offline /
        // CMS-only effect vóór de fetch landt, of een eigen custom effect). Met
        // een actief effect is `baseImage` (de huidige cutout) het effect-beeld;
        // de echte basis staat dan in `effectBaseData`. Zonder actief effect ÍS
        // de cutout de basis.
        let activeKey = portrait?.effectActiveRaw
        if activeKey != nil, let data = portrait?.effectBaseData, let img = NSImage(data: data) {
            self.base = img
            // E55.3: met een actief effect ÍS de meegegeven cutout het
            // effect-beeld — een nieuwe generatie moet op de BASIS werken,
            // anders stapelt stijl B op A's output (repro: A toepassen →
            // tool wisselen → paneel heropent met verse identiteit → B
            // genereren styleerde voorheen A's cutout).
            self.cutoutImage = img
        } else {
            self.base = baseImage
            self.cutoutImage = cutoutImage
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
        // De selectie ÍS de key — geen resolutie tegen een lijst nodig, dus ook
        // correct voor een custom effect dat pas ná de fetch bekend is.
        self.selectedKey = activeKey
    }

    /// Het beeld dat naar de stylize-backend gaat — zie `StylizeQuality.effectsStylizeSource`.
    /// Internal (niet private) zodat de E55.3-regressietest kan bewijzen dat de
    /// bron bij een actief effect de effect-basis is, niet de gestylede cutout.
    func stylizeSource(choice: StylizeQuality.EffectsSourceChoice) -> NSImage {
        StylizeQuality.effectsStylizeSource(portrait: portrait, cutout: cutoutImage, choice: choice)
    }

    var creditCost: Int { CreditMeter.credits(for: .generativeStandard) }

    var isBusy: Bool { if case .working = phase { return true } else { return false } }

    /// De kaarten in paneel-volgorde: eigen effecten eerst (nieuwste eerst, zoals
    /// de backend ze teruggeeft), daarna de built-in stijlen.
    var cards: [EffectCard] {
        customEffects.map(EffectCard.init) + builtinEffects.map(EffectCard.init)
    }

    func isSelected(_ card: EffectCard) -> Bool { selectedKey == card.key }
    func isWorking(_ card: EffectCard) -> Bool { phase == .working(card.key) }
    func isCached(_ card: EffectCard) -> Bool { cache[card.key] != nil }

    /// Mag de huidige gebruiker custom effecten maken? (Pro-only capability, E34.)
    var canCreateCustom: Bool { entitlement.isProActive || entitlement.isDevUnlimited }

    /// Haal de CMS-stijllijst (E33) én de eigen custom effecten (E34) op —
    /// sinds E55.6 parallel (de custom-fetch wachtte serieel achter de
    /// built-ins) en stale-while-revalidate: het paneel toont al de disk-
    /// hydratie; dit ververst lijst + disk-snapshot op de achtergrond.
    /// Soft-fail: bij een lege/gefaalde fetch houden we de bestaande lijst
    /// zodat het paneel bruikbaar blijft.
    func loadEffects() async {
        async let customRefresh: Void = loadCustomEffects()
        let fetched = (try? await entitlement.backend.effects()) ?? []
        if !fetched.isEmpty {
            EffectsModel.sessionCache = fetched
            builtinEffects = fetched
            EffectsListCache.shared.saveEffects(fetched)
            // E52.1: warm de gedeelde thumbnail-cache (memory + disk, downsampled
            // decode). De kaarten renderen via `RemoteThumbnail`, dus geen eigen
            // NSCache/thumbnailVersion-boekhouding meer.
            ThumbnailCache.shared.prefetch(fetched.compactMap(\.thumbnailUrl))
        }
        await customRefresh
    }

    /// Custom effecten (E34) — alleen voor Pro (de capability is Pro). Soft-fail
    /// (incl. 403 pro_required) houdt de lijst leeg/ongewijzigd — belangrijk
    /// zolang sql/015 nog niet op prod staat: custom-falen blokkeert nooit de
    /// built-ins (E55.6).
    func loadCustomEffects() async {
        guard canCreateCustom else { return }
        guard let fetched = try? await entitlement.backend.customEffects() else { return }
        EffectsModel.customSessionCache = fetched
        customEffects = fetched
        EffectsListCache.shared.saveCustomEffects(fetched)
        ThumbnailCache.shared.prefetch(fetched.compactMap(\.thumbnailUrl))
    }

    // MARK: - Launch-prewarm (E55.6 = E52.2 voor effects)

    private static var didPrewarm = false

    /// Warmt lijst + thumbnails bij app-start (fire-and-forget, éénmalig per
    /// proces), zodat zelfs de állereerste paneel-open van een sessie de
    /// kaarten uit memory/disk schildert. Anoniem-vriendelijk endpoint, dus
    /// veilig vóór sign-in; custom effecten volgen bij paneel-open (Pro-check
    /// hangt aan entitlement-state die bij launch nog kan laden).
    static func prewarm(entitlement: EntitlementModel) {
        guard !didPrewarm else { return }
        didPrewarm = true
        Task(priority: .utility) { @MainActor in
            let fetched = (try? await entitlement.backend.effects()) ?? []
            guard !fetched.isEmpty else { return }
            EffectsModel.sessionCache = fetched
            EffectsListCache.shared.saveEffects(fetched)
            ThumbnailCache.shared.prefetch(fetched.compactMap(\.thumbnailUrl))
        }
    }

    /// Lokaal geseed referentiebeeld voor een vers-gemaakt custom effect (E34):
    /// toont de kaart meteen, zonder round-trip naar de bucket-URL. nil → de
    /// kaart rendert via `RemoteThumbnail` op `card.thumbnailUrl`.
    func localThumbnail(for card: EffectCard) -> NSImage? { localThumbnails[card.key] }

    /// None-kaart: terug naar het basisbeeld (instant, geen credits).
    func selectNone() {
        guard !isBusy, selectedKey != nil else { return }
        let prev = selectedKey
        selectedKey = nil
        phase = .idle
        Task {
            await onApply(base)
            registerSelectionUndo(from: prev, to: nil)
            persist()
        }
    }

    /// Tik op een effect-kaart: actief → None; gecachet → instant uit cache;
    /// anders → genereren. Tijdens een lopende generatie negeren we tikken.
    /// E55.9: tikken op een kaart waarvan de generatie ge-cancel'd (gedetacht)
    /// doorloopt = de wacht-toast weer aankoppelen, NIET opnieuw genereren —
    /// anders zou de cancel-knop een dubbele generatie (en dubbele credits)
    /// uitlokken.
    func toggle(_ card: EffectCard) {
        guard !isBusy else { return }
        if detachedKey == card.key {
            reattach(card)
            return
        }
        if selectedKey == card.key {
            selectNone()
            return
        }
        if let cached = cache[card.key] {
            // Cache-hit: instant uit cache, maar her-isolatie kan even duren.
            let prev = selectedKey
            selectedKey = card.key
            Task {
                phase = .working(card.key)
                entitlement.presentWorking(
                    title: "Applying style",
                    messages: ["Cutting out the subject…", "Almost there…"]
                )
                await onApply(cached)
                phase = .idle
                entitlement.dismissWorkingToast()
                registerSelectionUndo(from: prev, to: card.key)
                persist()
            }
            return
        }
        Task { await generate(card) }
    }

    /// Refresh-icoon op de actieve kaart: bewust opnieuw genereren (kost credits).
    func regenerate(_ card: EffectCard) {
        guard !isBusy else { return }
        if detachedKey == card.key {
            reattach(card)
            return
        }
        Task { await generate(card, feature: .effectRegenerate) }
    }

    // MARK: - Cancel = detachen (E55.9)

    /// De kaart-key waarvan de generatie op de achtergrond doorloopt nadat de
    /// gebruiker op Cancel drukte. De server rekent pas af ná succes en de call
    /// loopt gewoon door — "echt" annuleren zou dus credits kosten zonder
    /// resultaat. Detachen is het eerlijke alternatief: de editor is meteen
    /// weer vrij en het resultaat landt stil in de kaart-cache (badge; tikken
    /// = gratis instant toepassen).
    private var detachedKey: String?
    /// Startmoment van de lopende generatie, zodat een re-attach de verstreken
    /// tijd doortelt i.p.v. op 0:00 te herbeginnen.
    private var generationStart = Date()

    /// Verwachte duur voor de toast-voortgang: gpt-image op high zit p50
    /// rond de 50s plus her-isolatie — 75s belooft bewust ruim (E55.9;
    /// bakeoff 55.7 herijkt dit getal met echte metingen).
    static let expectedGenerationSeconds = 75

    private func detachCurrentGeneration() {
        guard case .working(let key) = phase else { return }
        detachedKey = key
        phase = .idle
        entitlement.dismissWorkingToast()
    }

    private func reattach(_ card: EffectCard) {
        detachedKey = nil
        phase = .working(card.key)
        presentGenerationToast(startedAt: generationStart)
    }

    private func presentGenerationToast(startedAt: Date) {
        entitlement.presentWorking(
            title: "Applying style",
            messages: [
                "Mixing the palette…",
                "Laying on the texture…",
                "Top quality takes a moment…",
                "Tweaking the shadows…",
                "This one's going to look good…",
                "Adding the finishing touches…",
                "Almost there…",
            ],
            startedAt: startedAt,
            expectedSeconds: Self.expectedGenerationSeconds,
            onCancel: { [weak self] in self?.detachCurrentGeneration() }
        )
    }

    private func generate(_ card: EffectCard, feature: AIFeature = .effectGenerate) async {
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
        phase = .working(card.key)
        generationStart = Date()
        presentGenerationToast(startedAt: generationStart)
        // E55.9: is de generatie ondertussen gedetacht (Cancel), dan géén
        // apply/selectie/undo/toast meer — alleen stil cachen zodat de kaart
        // de badge krijgt en tikken straks gratis en instant is.
        func consumeDetach() -> Bool {
            guard detachedKey == card.key else { return false }
            detachedKey = nil
            return true
        }
        do {
            let softSource = StylizeQuality.requestsSoftSourcePrompt(for: source)
            // Cutout én origineel: geen reframe — achtergrond zit los van het cutout.
            let preserveFraming = true
            let resultData: Data
            switch card.kind {
            case .builtin:
                let response = try await entitlement.backend.stylize(
                    imagePNG: png, styleKey: card.key,
                    cutoutWidth: cutoutW, cutoutHeight: cutoutH,
                    softSource: softSource,
                    preserveFraming: preserveFraming
                )
                resultData = response.data
            case .custom:
                // E34: de server bouwt de prompt uit de opgeslagen beschrijving en
                // stuurt het referentiebeeld als stijlreferentie mee naar het model.
                let response = try await entitlement.backend.stylize(
                    imagePNG: png, customEffectID: card.customID ?? ""
                )
                resultData = response.data
            }
            guard let image = NSImage(data: resultData) else {
                if consumeDetach() { return }
                phase = .idle
                entitlement.dismissWorkingToast()
                entitlement.presentError("The styled image came back unreadable.")
                return
            }
            StylizeQuality.logStylizeDimensions(input: source, output: image, cutoutBefore: cutoutBefore)
            cache[card.key] = image
            if let png = image.pngData() { pngCache[card.key] = png }
            if consumeDetach() {
                // Gedetacht afgerond: resultaat is betaald én bewaard — persist
                // zet 'm in portrait.effectCache (overleeft ook paneel-wissel),
                // de kaart-badge maakt 'm vindbaar, saldo stil verversen.
                persist()
                await entitlement.refresh()
                return
            }
            let prev = selectedKey
            selectedKey = card.key
            await onApply(image)
            phase = .idle
            entitlement.dismissWorkingToast()
            registerSelectionUndo(from: prev, to: card.key)
            persist()
            await entitlement.refresh()
        } catch BackendError.noCredits {
            if consumeDetach() { return }
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.handleOutOfCredits()
        } catch BackendError.proRequired {
            // E34: de custom-effect-tak is Pro-only; een verlopen abonnement
            // tijdens de sessie landt hier i.p.v. op een generieke foutmelding.
            if consumeDetach() { return }
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.requestUpgrade()
        } catch BackendError.generationRefused {
            // E55: safety-weigering — eigen copy ("probeer een andere foto",
            // geen credits verbruikt) i.p.v. de retry-uitlokkende generieke.
            if consumeDetach() { return }
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.presentError(BackendError.generationRefused.errorDescription ?? "")
        } catch {
            // Gedetacht + gefaald: stil — de gebruiker is verder gegaan en er
            // is niets afgeschreven (server rekent pas af ná succes).
            if consumeDetach() { return }
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.presentError("Couldn't apply that style. Please try again.")
        }
    }

    // MARK: - Custom effects (E34)

    /// Voegt een net-aangemaakt custom effect toe (vooraan) en seedt zijn
    /// thumbnail met het zojuist gedropte referentiebeeld zodat de kaart meteen
    /// verschijnt zonder bucket-round-trip. Optioneel meteen toepassen.
    func addCustomEffect(_ effect: RemoteCustomEffect, referenceImage: NSImage, apply: Bool) {
        customEffects.insert(effect, at: 0)
        EffectsModel.customSessionCache = customEffects
        localThumbnails[effect.cacheKey] = referenceImage
        if apply {
            Task { await generate(EffectCard(effect)) }
        }
    }

    /// Verwijdert een eigen custom effect (server + lokaal). Was 'ie actief, dan
    /// terug naar None.
    func deleteCustomEffect(_ card: EffectCard) {
        guard card.kind == .custom, let id = card.customID else { return }
        if selectedKey == card.key { selectNone() }
        customEffects.removeAll { $0.id == id }
        EffectsModel.customSessionCache = customEffects
        cache[card.key] = nil
        pngCache[card.key] = nil
        localThumbnails[card.key] = nil
        if portrait?.effectCache[card.key] != nil {
            persist()
        }
        Task { try? await entitlement.backend.deleteCustomEffect(id: id) }
    }

    /// Registreert selectie-undo naast de beeld-swap zodat Cmd+Z de badge én
    /// het canvas in één keer terugzet. Beide registraties vallen in hetzelfde
    /// NSUndoManager-auto-groepje (zelfde run-loop cyclus) → één Cmd+Z.
    /// Target is het portret (SwiftData), niet `self`: EffectsModel leeft alleen
    /// zolang het paneel open is — na sluiten crashte een tweede undo op een
    /// dangling weak ref.
    private func registerSelectionUndo(from previous: String?, to next: String?) {
        guard let portrait else { return }
        ReversibleChange.register(
            undoManager, target: portrait,
            from: previous, to: next,
            actionName: "Apply effect"
        ) { [weak self] p, key in
            p.effectActiveRaw = key
            self?.selectedKey = key
        }
    }

    /// Persisteer de Effects-staat op het portret (E24.33).
    private func persist() {
        guard let portrait else { return }
        if portrait.effectBaseData == nil {
            portrait.effectBaseData = base.pngData()
        }
        portrait.effectActiveRaw = selectedKey
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
    /// E53.7: de "Create effect"-modal leeft op de stabiele host (ShellView), dus
    /// het paneel schrijft zijn open-state hier i.p.v. in eigen @State.
    var presentation: UIPresentationStore?
    var onApply: (NSImage) async -> Void = { _ in }

    @State private var model: EffectsModel
    @Environment(\.undoManager) private var undoManager

    init(
        baseImage: NSImage,
        entitlement: EntitlementModel,
        portrait: Portrait2? = nil,
        coordinator: StylizeQualityCoordinator? = nil,
        presentation: UIPresentationStore? = nil,
        onApply: @escaping (NSImage) async -> Void = { _ in }
    ) {
        self.baseImage = baseImage
        self.entitlement = entitlement
        self.portrait = portrait
        self.coordinator = coordinator
        self.presentation = presentation
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
        DSEditPanel(
            title: "Effects",
            credits: CreditMeter.chipLabel(for: .generativeStandard),
            headerAccessory: { createHeaderButton }
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.gap2) {
                    noneCard
                    ForEach(model.cards) { card in
                        styleCard(card)
                    }
                }
                .padding(.vertical, DSSpacing.gap2)
                .padding(.leading, DSSpacing.gap1_5)
                .scrollRowTrailingInset()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .horizontalScrollEdgeFade()
        }
        // E33/E34: CMS-lijst + eigen effecten ophalen bij openen. Soft-fail.
        .task { await model.loadEffects() }
        .onAppear { model.undoManager = undoManager }
        // E34+E53.7: de modal zelf hangt op ShellView; hier consumeren we alleen
        // haar resultaat (en legen de brievenbus zodat 'ie niet twee keer landt).
        .onChange(of: presentation?.createdCustomEffect?.effect.id) { _, newValue in
            guard newValue != nil, let result = presentation?.createdCustomEffect else { return }
            presentation?.createdCustomEffect = nil
            model.addCustomEffect(
                result.effect, referenceImage: result.referenceImage, apply: result.apply
            )
        }
    }

    /// E24.33: "None"-kaart helemaal links — terug naar het origineel (basis).
    private var noneCard: some View {
        Button {
            model.selectNone()
        } label: {
            DSThumbnailCard(
                label: "None",
                isSelected: model.selectedKey == nil,
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

    /// E55.4 (was E34-kaart): "Create" opent de modal (Pro) — verhuisd van
    /// tweede rail-kaart naar de paneelheader (besluit Thierry 2026-08-02;
    /// gedocumenteerde Figma-afwijking — Figma toont geen custom-effects-UI).
    /// De rail is nu puur content: None → eigen effecten → built-ins.
    /// Gating + mailbox (`presentation?.createEffectSheetOpen`) identiek aan
    /// de oude kaart.
    private var createHeaderButton: some View {
        HStack(spacing: DSSpacing.gap1) {
            if !model.canCreateCustom {
                DSProChip()
            }
            DSGhostButton("Create", icon: Image(systemName: "plus"), size: .small) {
                if model.canCreateCustom {
                    presentation?.createEffectSheetOpen = true
                } else {
                    entitlement.requestUpgrade()
                }
            }
        }
        .disabled(model.isBusy)
        .opacity(model.isBusy ? 0.5 : 1)
        .help("Create your own effect from a reference image")
    }

    @ViewBuilder
    private func styleCard(_ card: EffectCard) -> some View {
        let isSelected = model.isSelected(card)
        Button {
            model.toggle(card)
        } label: {
            DSThumbnailCard(
                label: card.label,
                isSelected: isSelected,
                isWorking: model.isWorking(card),
                tileSize: cardWidth,
                tileHeight: cardHeight,
                onRefresh: isSelected ? { model.regenerate(card) } : nil
            ) {
                thumbnail(for: card)
            }
            // E55.9: "klaar"-stip op gegenereerde-maar-niet-actieve kaarten —
            // maakt de gratis instant-cache zichtbaar, en is de landingsplek
            // van een ge-cancel'de (gedetachte) generatie.
            .overlay(alignment: .topTrailing) {
                if model.isCached(card), !isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: DSIconSize.sm))
                        .foregroundStyle(DSColor.Background.card, DSColor.Foreground.subtle)
                        .padding(DSSpacing.gap1_5)
                        .help("Generated — applying it again is instant and free")
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .opacity(model.isBusy && !model.isWorking(card) ? 0.5 : 1)
        // E34: eigen effecten zijn verwijderbaar via het contextmenu.
        .modifier(DeletableCustom(card: card, isBusy: model.isBusy) {
            model.deleteCustomEffect(card)
        })
    }

    /// CMS-/referentie-thumbnail die de tile vult; valt terug op het sparkles-icoon
    /// terwijl 'ie laadt of als het effect geen thumbnail heeft. E52.1: via de
    /// gedeelde `ThumbnailCache` (memory + disk + downsampled decode) i.p.v.
    /// AsyncImage — her-opens zijn instant, ook na een app-herstart. Een vers
    /// aangemaakt custom effect (E34) toont zijn lokaal geseede referentiebeeld
    /// zolang de bucket-URL nog niet warm is.
    @ViewBuilder
    private func thumbnail(for card: EffectCard) -> some View {
        if let local = model.localThumbnail(for: card) {
            Image(nsImage: local)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: cardWidth, height: cardHeight)
                .clipped()
        } else if let url = card.thumbnailUrl {
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
            .font(.system(size: DSIconSize.xl, weight: .regular))
    }
}

/// E34: contextmenu-delete, alleen op eigen (custom) effecten.
private struct DeletableCustom: ViewModifier {
    let card: EffectCard
    let isBusy: Bool
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        if card.kind == .custom {
            content.contextMenu {
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete effect", systemImage: "trash")
                }
                .disabled(isBusy)
            }
        } else {
            content
        }
    }
}
