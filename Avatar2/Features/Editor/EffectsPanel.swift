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
    /// Thumbnail-afbeeldingen gedownload na de eerste fetch; gedeeld over instanties.
    private static let imageCache = NSCache<NSURL, NSImage>()
    /// Teller die oploopt telkens een thumbnail in de cache belandt, zodat de
    /// SwiftUI-view herrendert en de gecachede afbeelding meteen toont.
    private(set) var thumbnailVersion: Int = 0

    /// De beschikbare stijlen (CMS-gestuurd, E33). Start op de sessie-cache als
    /// die al gevuld is (eerder geladen in dezelfde sessie), anders op de fallback.
    private(set) var remoteEffects: [RemoteEffect] =
        EffectsModel.sessionCache.isEmpty ? RemoteEffect.fallback : EffectsModel.sessionCache

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
        prefetchThumbnails(for: fetched)
    }

    /// Downloads thumbnail URLs in the background and caches them as NSImages.
    /// Each successful download bumps `thumbnailVersion` so the view re-renders.
    private func prefetchThumbnails(for effects: [RemoteEffect]) {
        let urls = effects.compactMap(\.thumbnailUrl)
            .filter { EffectsModel.imageCache.object(forKey: $0 as NSURL) == nil }
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for url in urls {
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

    func cachedThumbnail(for effect: RemoteEffect) -> NSImage? {
        guard let url = effect.thumbnailUrl else { return nil }
        return EffectsModel.imageCache.object(forKey: url as NSURL)
    }

    /// None-kaart: terug naar het basisbeeld (instant, geen credits).
    func selectNone() {
        guard !isBusy, selected != nil else { return }
        let prevSelected = selected
        selected = nil
        phase = .idle
        onApply(base)
        registerSelectionUndo(from: prevSelected, to: nil)
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
            let prevSelected = selected
            selected = effect
            phase = .idle
            onApply(cached)
            registerSelectionUndo(from: prevSelected, to: effect)
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
        // Stylet de VOLLE originele foto (incl. achtergrond), niet de cutout: zo
        // krijgt de Original-achtergrond hetzelfde effect. De foreground komt er
        // daarna weer uitgeïsoleerd uit (applyEffectResult).
        guard let png = stylizeSource.pngData() else {
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
            let prevSelected = selected
            selected = effect
            phase = .idle
            entitlement.dismissWorkingToast()
            onApply(image)
            registerSelectionUndo(from: prevSelected, to: effect)
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

    /// Registreert selectie-undo naast de beeld-swap zodat Cmd+Z de badge én
    /// het canvas in één keer terugzet. Beide registraties vallen in hetzelfde
    /// NSUndoManager-auto-groepje (zelfde run-loop cyclus) → één Cmd+Z.
    private func registerSelectionUndo(from previous: RemoteEffect?, to next: RemoteEffect?) {
        ReversibleChange.register(
            undoManager, target: self,
            from: previous, to: next,
            actionName: "Apply effect"
        ) { model, sel in
            model.selected = sel
            model.portrait?.effectActiveRaw = sel?.key
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
    /// terwijl 'ie laadt of als het effect geen thumbnail heeft.
    @ViewBuilder
    private func thumbnail(for effect: RemoteEffect) -> some View {
        // thumbnailVersion registreert bij @Observable tracking zodat de view
        // herrendert zodra prefetchThumbnails een afbeelding in de cache zet.
        // `let _` (geen kale `_ =`) — een ViewBuilder accepteert geen Void-expressie.
        let _ = model.thumbnailVersion
        if let image = model.cachedThumbnail(for: effect) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: cardWidth, height: cardHeight)
                .clipped()
        } else if let url = effect.thumbnailUrl {
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
