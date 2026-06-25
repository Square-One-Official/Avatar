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
    /// Thumbnail-afbeeldingen gedownload na de eerste fetch; gedeeld over instanties.
    private static let imageCache = NSCache<NSURL, NSImage>()
    /// Teller die oploopt telkens een thumbnail in de cache belandt, zodat de
    /// SwiftUI-view herrendert en de gecachede afbeelding meteen toont.
    private(set) var thumbnailVersion: Int = 0

    /// De built-in stijlen (CMS-gestuurd, E33). Start op de sessie-cache als die
    /// al gevuld is (eerder geladen in dezelfde sessie), anders op de fallback.
    private(set) var builtinEffects: [RemoteEffect] =
        EffectsModel.sessionCache.isEmpty ? RemoteEffect.fallback : EffectsModel.sessionCache
    /// De eigen custom effecten (E34). Start op de sessie-cache; leeg = nog niet
    /// geladen / geen eigen effecten / niet-Pro.
    private(set) var customEffects: [RemoteCustomEffect] = EffectsModel.customSessionCache

    /// Lokaal geseede thumbnails (E34): meteen na het aanmaken tonen we het
    /// net-gedropte referentiebeeld zonder een round-trip naar de bucket-URL.
    private var localThumbnails: [String: NSImage] = [:]

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
        self.selectedKey = activeKey
    }

    /// Het beeld dat naar de stylize-backend gaat: de PRISTINE volle originele foto
    /// (incl. achtergrond) zodat het effect óók de achtergrond stylet → de Original-
    /// achtergrondlaag past straks bij het effect. De foreground wordt daarna her-
    /// geïsoleerd uit dit volle resultaat (applyEffectResult, preserveSourceAlpha).
    /// Val terug op `base` (de cutout) als er geen originele foto is (legacy/odd
    /// import; de Original-bg-keuze is dan toch verborgen omdat originalData ontbreekt).
    private var stylizeSource: NSImage {
        if let data = portrait?.originalData, let img = NSImage(data: data) { return img }
        return base
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

    /// Haal de CMS-stijllijst (E33) én de eigen custom effecten (E34) op. Soft-fail:
    /// bij een lege/gefaalde fetch houden we de bestaande lijst zodat het paneel
    /// bruikbaar blijft.
    func loadEffects() async {
        let fetched = (try? await entitlement.backend.effects()) ?? []
        if !fetched.isEmpty {
            EffectsModel.sessionCache = fetched
            builtinEffects = fetched
            prefetchThumbnails(for: fetched.compactMap(\.thumbnailUrl))
        }
        await loadCustomEffects()
    }

    /// Custom effecten (E34) — alleen voor Pro (de capability is Pro). Soft-fail
    /// (incl. 403 pro_required) houdt de lijst leeg/ongewijzigd.
    func loadCustomEffects() async {
        guard canCreateCustom else { return }
        guard let fetched = try? await entitlement.backend.customEffects() else { return }
        EffectsModel.customSessionCache = fetched
        customEffects = fetched
        prefetchThumbnails(for: fetched.compactMap(\.thumbnailUrl))
    }

    /// Downloads thumbnail URLs in the background and caches them as NSImages.
    /// Each successful download bumps `thumbnailVersion` so the view re-renders.
    private func prefetchThumbnails(for urls: [URL]) {
        let pending = urls.filter { EffectsModel.imageCache.object(forKey: $0 as NSURL) == nil }
        guard !pending.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for url in pending {
                    group.addTask {
                        guard let (data, _) = try? await URLSession.shared.data(from: url),
                              let image = NSImage(data: data) else { return }
                        EffectsModel.imageCache.setObject(image, forKey: url as NSURL)
                        await MainActor.run { self?.thumbnailVersion += 1 }
                    }
                }
            }
        }
    }

    /// De thumbnail voor een kaart: eerst een lokaal geseed beeld (vers-gemaakt
    /// custom effect, E34), dan de gedownloade URL-cache.
    func cachedThumbnail(for card: EffectCard) -> NSImage? {
        if let local = localThumbnails[card.key] { return local }
        guard let url = card.thumbnailUrl else { return nil }
        return EffectsModel.imageCache.object(forKey: url as NSURL)
    }

    /// None-kaart: terug naar het basisbeeld (instant, geen credits).
    func selectNone() {
        guard !isBusy, selectedKey != nil else { return }
        let prev = selectedKey
        selectedKey = nil
        phase = .idle
        onApply(base)
        registerSelectionUndo(from: prev, to: nil)
        persist()
    }

    /// Tik op een effect-kaart: actief → None; gecachet → instant uit cache;
    /// anders → genereren. Tijdens een lopende generatie negeren we tikken.
    func toggle(_ card: EffectCard) {
        guard !isBusy else { return }
        if selectedKey == card.key {
            selectNone()
            return
        }
        if let cached = cache[card.key] {
            // Cache-hit: INSTANT, geen backend-call, geen credits (E24.33).
            let prev = selectedKey
            selectedKey = card.key
            phase = .idle
            onApply(cached)
            registerSelectionUndo(from: prev, to: card.key)
            persist()
            return
        }
        Task { await generate(card) }
    }

    /// Refresh-icoon op de actieve kaart: bewust opnieuw genereren (kost credits).
    func regenerate(_ card: EffectCard) {
        guard !isBusy else { return }
        Task { await generate(card) }
    }

    private func generate(_ card: EffectCard) async {
        // E18.2: contextuele gate (online uit → login → upgrade).
        guard entitlement.allowCloudFeature() else { return }
        // Stylet de VOLLE originele foto (incl. achtergrond), niet de cutout: zo
        // krijgt de Original-achtergrond hetzelfde effect. De foreground komt er
        // daarna weer uitgeïsoleerd uit (applyEffectResult).
        guard let png = stylizeSource.pngData() else {
            entitlement.presentError("Couldn't read the portrait.")
            return
        }
        phase = .working(card.key)
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
            let response: (Data, Int)
            switch card.kind {
            case .builtin:
                response = try await entitlement.backend.stylize(imagePNG: png, styleKey: card.key)
            case .custom:
                response = try await entitlement.backend.stylize(
                    imagePNG: png, customEffectID: card.customID ?? ""
                )
            }
            guard let image = NSImage(data: response.0) else {
                phase = .idle
                entitlement.dismissWorkingToast()
                entitlement.presentError("The styled image came back unreadable.")
                return
            }
            cache[card.key] = image
            if let png = image.pngData() { pngCache[card.key] = png }
            let prev = selectedKey
            selectedKey = card.key
            phase = .idle
            entitlement.dismissWorkingToast()
            onApply(image)
            registerSelectionUndo(from: prev, to: card.key)
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
    private func registerSelectionUndo(from previous: String?, to next: String?) {
        ReversibleChange.register(
            undoManager, target: self,
            from: previous, to: next,
            actionName: "Apply effect"
        ) { model, key in
            model.selectedKey = key
            model.portrait?.effectActiveRaw = key
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
    var onApply: (NSImage) -> Void = { _ in }

    @State private var model: EffectsModel
    @State private var showCreateSheet = false
    @Environment(\.undoManager) private var undoManager

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
                    createCard
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
        .sheet(isPresented: $showCreateSheet) {
            CreateEffectSheet(entitlement: entitlement) { result in
                model.addCustomEffect(
                    result.effect, referenceImage: result.referenceImage, apply: result.apply
                )
            }
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

    /// E34: "Create effect"-kaart — opent de modal (Pro). Niet-Pro → upgrade.
    private var createCard: some View {
        Button {
            if model.canCreateCustom {
                showCreateSheet = true
            } else {
                entitlement.requestUpgrade()
            }
        } label: {
            DSThumbnailCard(
                label: "Create",
                isPro: !model.canCreateCustom,
                tileSize: cardWidth,
                tileHeight: cardHeight
            ) {
                VStack(spacing: DSSpacing.gap1) {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .semibold))
                    Text("New effect")
                        .dsTextStyle(.labelSmall)
                }
                .foregroundStyle(DSColor.Foreground.muted)
            }
        }
        .buttonStyle(.plain)
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
    /// terwijl 'ie laadt of als het effect geen thumbnail heeft.
    @ViewBuilder
    private func thumbnail(for card: EffectCard) -> some View {
        // thumbnailVersion registreert bij @Observable tracking zodat de view
        // herrendert zodra prefetchThumbnails een afbeelding in de cache zet.
        let _ = model.thumbnailVersion
        if let image = model.cachedThumbnail(for: card) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: cardWidth, height: cardHeight)
                .clipped()
        } else if let url = card.thumbnailUrl {
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
