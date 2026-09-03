// Edit-paneel (E22.3) — Enhance: één-tik-acties als vast tegel-raster
// (naast én onder elkaar, geen horizontale scroll). Adjust gebruikt
// `AdjustPanel` voor brightness/contrast/saturation/temperature.
// One-click retouch verhuisde hierheen uit het Face-paneel (Thierry, 2026-06-23).

import AvatarKit
import AvatarUI
import SwiftUI

/// E41.2/E41.5 (herzien, Thierry 2026-07-12): hoe een "Boost resolution"
/// draait — lokaal (gratis, on-device) of online (Topaz High Fidelity V2,
/// 3 credits). Eén betaalde optie: de gratis on-device boost dekt het lichte
/// geval al, dus een goedkopere online-middenweg (google) voegde alleen
/// keuzestress toe; die tier bestaat backend-side nog wel (o.a. voor oude
/// builds zonder `quality`-veld).
enum BoostMode: Equatable, Sendable {
    case local, online

    /// Chip-/menulabel voor de kosten.
    var costLabel: String {
        switch self {
        case .local: return "Free"
        case .online: return CreditMeter.chipLabel(for: .upscaleHigh)
        }
    }
}

/// Welke chip-dropdown momenteel open is. Eén tegelijk; nil = dicht.
/// E53.7: internal (niet private) omdat de state in `UIPresentationStore` leeft.
enum ChipMenu: Hashable, Sendable { case boost, removeBackground }

/// Copy voor Colorise op een foto die al in kleur is. Eén bron voor tegel,
/// tooltip en dialog.
enum ColoriseAlreadyColourCopy {
    static let title = "Already in colour"
    static let message = "This still costs 1 credit."
    static let confirm = "Use 1 credit"
    static let help = "Already in colour. Still costs 1 credit."
    static let defaultHelp = "Turn a black-and-white photo into colour."
}

/// Tegels in het Enhance-raster. Geen `LazyVGrid`: die clipt cell-overlays, waardoor
/// Boost/Remove-background hun dropdown (die naar boven opent) onzichtbaar was.
private enum EnhanceActionID: Hashable, Sendable {
    case retouch, studioLight, portrait, colorise, boost, fillBody, removeBackground, appleIntelligence

    var previewAction: EnhanceTilePreview.Action {
        switch self {
        case .retouch: .retouch
        case .studioLight: .studioLight
        case .portrait: .portrait
        case .colorise: .colorise
        case .boost: .boost
        case .fillBody: .fillBody
        case .removeBackground: .removeBackground
        case .appleIntelligence: .appleIntelligence
        }
    }

    /// E53.10: hover-beweging per tegel (zie `EnhanceTileMotion`).
    var motion: EnhanceTileMotion {
        switch self {
        case .retouch: .wipeHorizontal(rest: 0.5, from: .trailing)
        case .studioLight: .spotlight
        case .portrait: .depthPull
        case .colorise: .wipeHorizontal(rest: 0.5, from: .trailing)
        case .boost: .resolve
        case .fillBody: .wipeVertical(rest: Double(EnhanceTilePreview.fillBodySplit))
        case .removeBackground: .dissolve
        case .appleIntelligence: .none
        }
    }
}

struct EditColorPanel: View {
    /// E24.14: de RAUWE cutout (zonder Adjust-laag). De sliders renderen er live
    /// bovenop; de commit persisteert alléén de params (niet-destructief).
    let source: NSImage
    /// Originele foto / achtergrond voor de Portrait-tegel-preview (lokale blur).
    var previewBackdrop: NSImage? = nil
    /// Door de host (EditorView) alvast voorbereide previews: decode + downscale
    /// + gezicht zijn dan al gedaan vóór het paneel opent. nil = nog bezig (bij
    /// `hostPreparesPreviews`) of geen host-prep (Board): dan bereidt het
    /// paneel zelf voor, off-main.
    var previewPrep: EnhancePreviewPrep? = nil
    /// True: wacht op `previewPrep` i.p.v. zelf voor te bereiden (voorkomt
    /// dubbel werk wanneer het paneel al open is tijdens een edit).
    var hostPreparesPreviews: Bool = false
    /// E24.14: de persisted Adjust-stand bij het openen — heropenen toont 'm.
    var initial: PortraitAdjust = .neutral
    var onPreview: (NSImage) -> Void = { _ in }
    /// E24.14: commit levert de param-stand (before→after) i.p.v. beelden, zodat
    /// de caller ze niet-destructief op het portret kan persisteren + undo'en.
    var onCommit: (_ before: PortraitAdjust, _ after: PortraitAdjust) -> Void = { _, _ in }
    /// One-click retouch (lokaal) — verhuisd uit Face (Thierry, 2026-06-23). Toont
    /// als eerste chip wanneer `showRetouch`.
    var onRetouch: () -> Void = {}
    var onStudioLight: () -> Void = {}
    /// Portrait-modus (achtergrond-blur) aan/uit — verhuist niet, blurt de
    /// achtergrondLAAG en houdt het onderwerp scherp (macOS-webcam-Portrait).
    var onPortrait: () -> Void = {}
    var onColorise: () -> Void = {}
    /// True when the current cutout already looks like a colour photo.
    /// Colorise toont dan de titel uit `ColoriseAlreadyColourCopy` i.p.v. stil
    /// een credit te verbranden op een near-no-op.
    var alreadyInColour: Bool = false
    /// E41.2: Boost met de gekozen modus (lokaal/gratis of online/1 credit).
    var onBoost: (BoostMode) -> Void = { _ in }
    // E31.3: verhuisde mee uit de frame-toolbar-AI-dropdown. E31.8 (audit C4):
    // canonieke naam is "Fill in body" (chip + toast + undo-entry) — de oude
    // chip-naam "Restore body" botste met de overflow-actie "Restore to
    // original" (re-isolate, een andere functie).
    var onFillBody: () -> Void = {}
    /// Verwijder de achtergrond: her-isoleer het onderwerp (altijd on-device).
    /// Parameter = one-shot engine-override: nil draait de actieve engine (ORMBG
    /// als "High quality" geïnstalleerd is, anders Apple Vision); `.vision` is de
    /// per-beeld "Regular quality"-keuze uit het chip-menu die de globale
    /// voorkeur NIET wijzigt. Nooit een credit.
    var onRemoveBackground: (CutoutEngineKind?) -> Void = { _ in }
    /// Tier 2: Image Playground bewerken met huidige cutout als seed.
    var entitlement: EntitlementModel? = nil
    /// E53.7: host voor de chip-dropdown-state (zie `openMenu`).
    var presentation: UIPresentationStore? = nil
    var onAppleEdit: (Data) -> Void = { _ in }
    var showAppleEdit: Bool = false
    var isPro: Bool = false
    /// E24.28: of de lokale "Studio Light"-toggle momenteel AAN staat.
    var studioLightOn: Bool = false
    /// Of "Portrait" (achtergrond-blur) momenteel AAN staat.
    var portraitOn: Bool = false
    /// One-click retouch-toggle AAN (editor); op de board een one-shot (false).
    var retouchOn: Bool = false
    /// Toon de "One click retouch"-chip als eerste in de één-tik-rij. Default uit
    /// zodat de board batch-adjust 'm niet toont (retouch = per beeld).
    var showRetouch: Bool = false
    /// Toon de "Remove background"-chip. Default uit zodat de board batch-adjust
    /// 'm niet toont (isolatie = per beeld, niet zinvol als batch).
    var showRemoveBackground: Bool = false
    /// E24.3: in de Adjust-popover staat de AI-dropdown apart (canvas-toolbar),
    /// dus dan tonen we alléén de sliders + Reset.
    /// E29.5 (audit C6): dit gate ALLEEN de vijf AI-één-tik-chips (Studio Light/
    /// Portrait/Colorise/Boost/Fill in body) — de board-call-sites zetten 'm op
    /// `false` omdat ze die closures niet bedraden (default-leeg = dode chips);
    /// `showRetouch`/`showRemoveBackground` houden hun eigen chip zichtbaar.
    var showAutoEnhance: Bool = true
    /// Enhance toont tegels zonder sliders; Adjust gebruikt `AdjustPanel`.
    var showSliders: Bool = true

    /// E29.5: de chip-rij rendert zodra er minstens één ECHT bedrade chip is —
    /// nooit meer een rij met alleen dode default-closures.
    private var showsQuickActions: Bool {
        showAutoEnhance || showRetouch || showRemoveBackground || showAppleEdit
    }

    // E41.2: Boost-/Remove background-modus-dropdown (lokaal/online) + onthouden
    // laatste keuze. Welk menu open is wordt buiten de scroll-rij gerenderd (zie
    // `chipMenuOverlay`), zodat de masker/clip van de horizontale rij het niet
    // afkapt — anders zou de gebruiker een lege dropdown zien.
    /// E53.7: welk chip-menu open is leeft in de gedeelde store i.p.v. view-@State,
    /// zodat een tab-/vensterwissel het menu niet wegslaat.
    private var openMenu: ChipMenu? {
        get { presentation?.editorChipMenu }
        nonmutating set { presentation?.editorChipMenu = newValue }
    }
    @State private var boostMode: BoostMode =
        PrivacyPreferences2.shared.effectiveTier == .onDevice ? .local : .online
    /// Alléén de lopende download-voortgang van het High-quality-model (ORMBG).
    /// Of het model áctief is lezen we reactief uit `PrivacyPreferences2.engine`
    /// (zie `highQualityActive`) — niet uit een eigen snapshot — zodat een download
    /// die elders is voltooid (Settings, haar-nudge) de chip meteen vereenvoudigt.
    /// Eigen instance per paneel; deelt de onderliggende `OrmbgModelStore.shared`.
    @State private var hiFiModel = HighFidelityModelState()
    @State private var seeded = false
    @State private var brightness = 0.0
    @State private var contrast = 1.0
    @State private var saturation = 1.0
    @State private var temperature = 0.0
    /// Param-stand bij het begin van een sleep (voor de undo-bare commit).
    @State private var dragStart: PortraitAdjust?
    /// Perf: de bron-CGImage één keer gedecodeerd zodat de live preview niet
    /// elke slider-tik opnieuw decodeert.
    @State private var sourceCG: SendableCGImage?
    /// Lopende off-main preview-render; bij elke nieuwe tik gecanceld zodat
    /// alleen de laatste stand landt (coalescing).
    @State private var previewTask: Task<Void, Never>?
    @State private var showHybridCoachmark = false
    @State private var previewLayers: [EnhanceActionID: EnhanceTileLayers] = [:]
    /// Scène achter de Portrait-tegel; één keer per paneel gekozen (E53.10).
    @State private var portraitScene: NSImage? = EnhancePreviewScenes.random()

    private var advancedAllowed: Bool {
        PrivacyPreferences2.shared.allowsThirdPartyCloud
    }

    private var current: PortraitAdjust {
        PortraitAdjust(brightness: brightness, contrast: contrast,
                       saturation: saturation, temperature: temperature)
    }

    private var hasAdjustments: Bool { !current.isNeutral }

    /// Live preview off-main (perf): de kleuraanpassing draaide voorheen
    /// synchroon op de main-thread bij élke slider-tik (vol-res CIContext-render
    /// → hapert). Nu: één gedeelde decode, render op een achtergrond-executor,
    /// plus korte debounce + cancel zodat alleen de laatste stand landt.
    /// Neutraal toont direct de rauwe cutout.
    @MainActor
    private func schedulePreview() {
        previewTask?.cancel()
        let adj = current
        guard !adj.isNeutral, let boxed = sourceCG else {
            previewTask = nil
            onPreview(source)
            return
        }
        let size = source.size
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000) // ~12 ms coalescing
            if Task.isCancelled { return }
            guard let out = await Self.renderAdjust(boxed, adj),
                  !Task.isCancelled else { return }
            onPreview(NSImage(cgImage: out.cgImage, size: size))
        }
    }

    private nonisolated static func renderAdjust(
        _ boxed: SendableCGImage, _ adj: PortraitAdjust
    ) async -> SendableCGImage? {
        PortraitEnhancer.colorAdjust(
            boxed.cgImage, brightness: adj.brightness, contrast: adj.contrast,
            saturation: adj.saturation, temperatureShift: adj.temperature
        ).map(SendableCGImage.init)
    }

    private var visibleActionIDs: [EnhanceActionID] {
        var ids: [EnhanceActionID] = []
        if showRetouch { ids.append(.retouch) }
        if showAutoEnhance {
            ids.append(contentsOf: [.studioLight, .portrait, .colorise, .boost, .fillBody])
        }
        if showRemoveBackground { ids.append(.removeBackground) }
        if showAppleEdit { ids.append(.appleIntelligence) }
        return ids
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap5) {
            // E24.27: één-tik AI-acties als vast tegel-raster (Pro/credit waar
            // van toepassing). Color-sliders zitten in Adjust.
            if showsQuickActions {
                VStack(alignment: .leading, spacing: DSSpacing.gap3) {
                    actionGrid

                    if showHybridCoachmark {
                        hybridCoachmark
                    }
                }
                if showSliders { Divider() }
            }

            if showSliders {
                slider("Brightness", value: $brightness, range: -0.4...0.4)
                slider("Contrast", value: $contrast, range: 0.6...1.4)
                slider("Saturation", value: $saturation, range: 0...2)
                slider("Temperature", value: $temperature, range: -1...1)

                HStack(spacing: DSSpacing.gap3) {
                    DSGhostButton("Reset") { reset() }
                        .disabled(!hasAdjustments)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: hiFiModel.phase) { _, phase in
            if phase == .failed {
                entitlement?.presentError(
                    "Couldn't download the High quality model. Check your connection and try again."
                )
            }
        }
        .onAppear {
            // Reflecteer of het High-quality-model al op schijf staat (bepaalt of
            // de chip simpel is of een Regular/High-keuze toont).
            hiFiModel.refreshInstalledState()
            // Alleen voor de sliders (live preview); zonder sliders zou dit een
            // vol-res PNG-decode op de main-thread zijn bij elke paneel-open.
            if showSliders, sourceCG == nil,
               let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                sourceCG = SendableCGImage(cgImage: cg)
            }
            // Seed de sliders eenmalig op de persisted stand (heropenen toont 'm).
            guard !seeded else { return }
            brightness = initial.brightness
            contrast = initial.contrast
            saturation = initial.saturation
            temperature = initial.temperature
            seeded = true
        }
        .task(id: TilePreviewKey(source: ObjectIdentifier(source), prep: previewPrep?.token)) {
            await loadTilePreviews()
        }
    }

    /// Vast 3-koloms raster zonder `LazyVGrid`, zodat de Boost-/Remove-dropdowns
    /// (die naar boven openen — Enhance zit onderin het venster) niet worden
    /// weggeclipt door de cel. De paneel-kaart clipt overlays zelf ook niet
    /// (`dsPanelSurface`): het menu is breder dan de tegel en valt over de rand.
    private var actionGrid: some View {
        let columns = EnhanceTileMetrics.columns
        let ids = visibleActionIDs
        let rows = stride(from: 0, to: ids.count, by: columns).map {
            Array(ids[$0..<min($0 + columns, ids.count)])
        }
        return VStack(spacing: EnhanceTileMetrics.gridSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let lifted = (openMenu == .boost && row.contains(.boost))
                    || (openMenu == .removeBackground && row.contains(.removeBackground))
                HStack(alignment: .center, spacing: EnhanceTileMetrics.gridSpacing) {
                    ForEach(row, id: \.self) { id in
                        actionTileView(id)
                            .frame(maxWidth: .infinity)
                    }
                    if row.count < columns {
                        ForEach(0..<(columns - row.count), id: \.self) { index in
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: EnhanceTileMetrics.height)
                                .accessibilityHidden(true)
                                .id("enhance-pad-\(index)")
                        }
                    }
                }
                .zIndex(lifted ? 10 : 0)
            }
        }
        .dsDropdownDismissOverlay(isPresented: menuOpenBinding)
    }

    private var menuOpenBinding: Binding<Bool> {
        Binding(
            get: { openMenu != nil },
            set: { if !$0 { openMenu = nil } }
        )
    }

    private func menuBinding(_ menu: ChipMenu) -> Binding<Bool> {
        Binding(
            get: { openMenu == menu },
            set: { openMenu = $0 ? menu : (openMenu == menu ? nil : openMenu) }
        )
    }

    private func menuPlacement(for id: EnhanceActionID) -> DSDropdownPlacement {
        guard let index = visibleActionIDs.firstIndex(of: id) else { return .above }
        // Rij 1: ruimte onder de tegel (tweede rij). Rij 2+: Enhance zit
        // onderin het venster, dus open naar boven over de rij erboven.
        return index < EnhanceTileMetrics.columns ? .below : .above
    }

    @ViewBuilder
    private func actionTileView(_ id: EnhanceActionID) -> some View {
        switch id {
        case .retouch:
            actionTile("Retouch", id: .retouch, isOn: retouchOn, action: onRetouch)
        case .studioLight:
            actionTile("Studio Light", id: .studioLight, isOn: studioLightOn, action: onStudioLight)
        case .portrait:
            actionTile("Portrait", id: .portrait, isOn: portraitOn, action: onPortrait)
        case .colorise:
            actionTile(
                "Colorise",
                id: .colorise,
                pro: !isPro,
                credit: "\(CreditMeter.credits(for: .colorize))",
                privacy: CloudFeatureChrome.isLocalOnly ? .thirdParty : nil,
                isMuted: CloudFeatureChrome.isLocalOnly,
                help: alreadyInColour
                    ? ColoriseAlreadyColourCopy.help
                    : ColoriseAlreadyColourCopy.defaultHelp,
                accessibilitySubtitle: alreadyInColour ? ColoriseAlreadyColourCopy.title : nil,
                action: onColorise
            )
        case .boost:
            boostMenuChip
        case .fillBody:
            actionTile(
                "Fill in body",
                id: .fillBody,
                pro: !isPro,
                credit: "\(CreditMeter.credits(for: .fillBody))",
                privacy: CloudFeatureChrome.isLocalOnly ? .thirdParty : nil,
                isMuted: CloudFeatureChrome.isLocalOnly,
                action: onFillBody
            )
        case .removeBackground:
            removeBackgroundMenuChip
        case .appleIntelligence:
            appleIntelligenceTile
        }
    }

    /// Vaste preview-kaart. ON / menu-open = lime ring, geen lime fill over de foto.
    private func actionTile(
        _ label: String,
        id: EnhanceActionID,
        pro: Bool = false,
        credit: String? = nil,
        isOn: Bool? = nil,
        showsMenu: Bool = false,
        isMenuOpen: Bool = false,
        privacy: DSPrivacyExecutionTier? = nil,
        isMuted: Bool = false,
        help: String? = nil,
        accessibilitySubtitle: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        EnhanceActionTile(
            title: label,
            credit: credit,
            pro: pro,
            showsMenu: showsMenu,
            isOn: isOn == true,
            isMenuOpen: isMenuOpen,
            privacy: privacy,
            layers: previewLayers[id],
            motion: id.motion,
            fallback: source,
            help: help,
            accessibilitySubtitle: accessibilitySubtitle,
            action: {
                if !showsMenu { openMenu = nil }
                action()
            }
        )
        .cloudFeatureMuted(isMuted)
    }

    private var appleIntelligenceTile: some View {
        actionTile(
            "Apple Intelligence",
            id: .appleIntelligence,
            privacy: CloudFeatureChrome.isLocalOnly ? .thirdParty : nil,
            isMuted: CloudFeatureChrome.isLocalOnly,
            action: {
                guard let entitlement, entitlement.allowAIFeature(
                    .imagePlaygroundEdit,
                    retry: {
                        ImagePlaygroundPresenter.shared.present(sourceImage: source, onCompleted: onAppleEdit)
                    }
                ) else { return }
                ImagePlaygroundPresenter.shared.present(sourceImage: source, onCompleted: onAppleEdit)
            }
        )
        .accessibilityLabel("Edit with Apple Intelligence")
    }

    private var hybridCoachmark: some View {
        HStack(alignment: .top, spacing: DSSpacing.gap2) {
            Text(HybridFallbackCoachmark.message)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DSSpacing.gap2)
            Button {
                HybridFallbackCoachmark.markShown()
                showHybridCoachmark = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: DSIconSize.xs, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            .buttonStyle(.plain)
            .dsFocusEffectDisabled()
        }
        .padding(.horizontal, DSSpacing.gap1)
    }

    private func noteHybridFallbackIfNeeded() {
        guard !advancedAllowed, HybridFallbackCoachmark.shouldShow else { return }
        showHybridCoachmark = true
    }

    /// E41.2: Boost-tegel. Dropdown hangt aan de tegel (niet onder het paneel),
    /// zodat hij zichtbaar blijft in het Enhance-raster onderin het venster.
    private var boostMenuChip: some View {
        actionTile(
            "Boost",
            id: .boost,
            credit: boostMode == .online ? "\(CreditMeter.credits(for: .upscaleHigh))" : nil,
            showsMenu: true,
            isMenuOpen: openMenu == .boost,
            // E53.10: geen slot-icoon meer; cloud alleen wanneer Local only aan
            // staat én de gekozen modus cloud nodig heeft (zelfde regel als
            // Colorise/Fill in body).
            privacy: (boostMode == .online && CloudFeatureChrome.isLocalOnly) ? .thirdParty : nil,
            isMuted: boostMode == .online && CloudFeatureChrome.isLocalOnly
        ) {
            toggleMenu(.boost)
        }
        .accessibilityHint("Shows boost options")
        .dsDropdownMenu(
            isPresented: menuBinding(.boost),
            anchorHeight: EnhanceTileMetrics.height,
            placement: menuPlacement(for: .boost)
        ) {
            boostMenu
        }
    }

    /// Het Boost-dropdown-paneel (gerenderd in de overlay, niet op de chip).
    private var boostMenu: some View {
        DSContextMenuPanel(minWidth: 268) {
            DSMenuRow("On device", icon: "desktopcomputer", shortcut: "Free · On device") {
                openMenu = nil
                boostMode = .local
                noteHybridFallbackIfNeeded()
                onBoost(.local)
            }
            // E41.5 (herzien): één betaalde optie — Topaz, 3 credits.
            onlineHybridMenuRow(
                title: "Online",
                shortcut: advancedAllowed
                    ? "Best · \(BoostMode.online.costLabel)"
                    : "Sharper · Cloud"
            ) {
                openMenu = nil
                boostMode = .online
                onBoost(.online)
            }
        }
    }

    /// Remove background — altijd on-device, nooit een credit. De chip houdt
    /// ALTIJD z'n chevron-menu: zonder het model kiest de gebruiker per keer
    /// Regular (Vision, direct) of High (eenmalige download die ook de globale
    /// voorkeur zet); mét het High-quality-model (ORMBG) actief biedt het menu
    /// naast High een one-shot "Regular quality · This image only" — ORMBG wint
    /// niet op élk haar (E02.2: backlit-slierten juist bij Vision beter), dus de
    /// per-beeld escape blijft nodig zonder de globale voorkeur om te zetten.
    /// Tijdens downloaden toont de chip voortgang.
    /// High quality (ORMBG) actief = de import/cutout draait er al op. Reactief op
    /// de gedeelde voorkeur, dus consistent met welke engine de cutout écht kiest.
    private var highQualityActive: Bool {
        PrivacyPreferences2.shared.engine == .downloadedModel
    }

    @ViewBuilder
    private var removeBackgroundMenuChip: some View {
        if case .downloading(let fraction) = hiFiModel.phase {
            cutoutDownloadingChip(fraction)
        } else {
            cutoutChoiceChip
        }
    }

    /// Chevron opent het kwaliteitsmenu (variant hangt af van `highQualityActive`).
    private var cutoutChoiceChip: some View {
        actionTile(
            "Remove background",
            id: .removeBackground,
            showsMenu: true,
            isMenuOpen: openMenu == .removeBackground
        ) {
            toggleMenu(.removeBackground)
        }
        .accessibilityHint("Shows quality options")
        .dsDropdownMenu(
            isPresented: menuBinding(.removeBackground),
            anchorHeight: EnhanceTileMetrics.height,
            placement: menuPlacement(for: .removeBackground)
        ) {
            removeBackgroundMenu
        }
    }

    private func cutoutDownloadingChip(_ fraction: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
        return VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            Text("Downloading…")
                .dsTextStyle(.labelBase)
            Text("\(Int(fraction * 100))%")
                .dsTextStyle(.labelSmall)
                .monospacedDigit()
                .foregroundStyle(DSColor.Foreground.muted)
            Spacer(minLength: 0)
        }
        .foregroundStyle(DSColor.Foreground.primary)
        .padding(DSSpacing.gap3)
        .frame(maxWidth: .infinity, minHeight: EnhanceTileMetrics.height, maxHeight: EnhanceTileMetrics.height, alignment: .topLeading)
        .background(DSColor.Background.neutral, in: shape)
        .accessibilityLabel("Downloading high quality model, \(Int(fraction * 100)) percent")
    }

    @ViewBuilder
    private var removeBackgroundMenu: some View {
        if highQualityActive {
            // Model actief: High is de default (globale voorkeur), Regular blijft
            // als one-shot per beeld beschikbaar — raakt de voorkeur NIET aan.
            DSContextMenuPanel(minWidth: 230) {
                DSMenuRow("High quality", icon: "sparkles", shortcut: "Current") {
                    openMenu = nil
                    onRemoveBackground(nil)
                }
                DSMenuRow("Regular quality", icon: "bolt", shortcut: "This image only") {
                    openMenu = nil
                    onRemoveBackground(.vision)
                }
            }
        } else {
            DSContextMenuPanel(minWidth: 230) {
                DSMenuRow("Regular quality", icon: "bolt", shortcut: "Instant") {
                    openMenu = nil
                    onRemoveBackground(nil)
                }
                DSMenuRow("High quality", icon: "sparkles", shortcut: "Sharper hair · 78 MB") {
                    openMenu = nil
                    // Download het model (voortgang op de chip), zet het meteen als
                    // actieve engine — ook latere imports gebruiken het dan — en maak
                    // het beeld vrijstaand zodra het binnen is.
                    hiFiModel.download {
                        PrivacyPreferences2.shared.engine = .downloadedModel
                        onRemoveBackground(nil)
                    }
                }
            }
        }
    }

    private func toggleMenu(_ menu: ChipMenu) {
        openMenu = (openMenu == menu) ? nil : menu
    }

    /// Online-pad altijd zichtbaar; muted wanneer Advanced tier nog niet actief is.
    private func onlineHybridMenuRow(
        title: String,
        shortcut: String,
        action: @escaping () -> Void
    ) -> some View {
        DSMenuRow(title, icon: "cloud", shortcut: shortcut, accessory: {
            if !advancedAllowed {
                DSPrivacyBadge(tier: .thirdParty)
                    .accessibilityHidden(true)
            }
        }, action: action)
        .opacity(advancedAllowed ? 1 : 0.55)
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap0_5) {
            Text(label)
                .dsTextStyle(.labelSmall)
                .foregroundStyle(DSColor.Foreground.muted)
            DSSlider(
                value: value,
                in: range,
                onEditingChanged: { editing in
                    if editing {
                        dragStart = current
                    } else if let before = dragStart {
                        onCommit(before, current)
                        dragStart = nil
                    }
                }
            )
            .onChange(of: value.wrappedValue) { _, _ in schedulePreview() }
        }
    }

    private func reset() {
        let before = current
        previewTask?.cancel()
        brightness = 0; contrast = 1; saturation = 1; temperature = 0
        onPreview(source)
        onCommit(before, .neutral)
    }

    /// Sleutel voor `.task(id:)`: nieuwe bron óf nieuwe host-prep → opnieuw renderen.
    private struct TilePreviewKey: Equatable {
        let source: ObjectIdentifier
        let prep: UUID?
    }

    /// E53.10: per tegel álle lagen (base/reveal/subject/focus) off-main.
    /// Backdrop: Portrait = gebundelde scène, Remove background = originele foto.
    /// De zware voorbereiding (decode, downscale, Vision) gebeurt één keer per
    /// bron — via de host (`previewPrep`) of anders hier — en de tegels delen
    /// 'm; per tegel blijft alleen de compositie op ≤ 256 px over.
    @MainActor
    private func loadTilePreviews() async {
        let prep: EnhancePreviewPrep?
        if let previewPrep {
            prep = previewPrep
        } else if hostPreparesPreviews {
            // Host is nog bezig; de task herstart zodra `previewPrep` landt.
            return
        } else {
            prep = await EnhancePreviewPrep.make(source: source, backdrop: previewBackdrop)
        }
        guard let prep, !Task.isCancelled else { return }
        let prepared = prep.subject
        let boxedOriginal = prep.backdrop.map { SendableCGImage(cgImage: $0) }
        let boxedScene = await Self.prepareScene(portraitScene)
        let jobs: [(EnhanceActionID, EnhanceTilePreview.Action, SendableCGImage?)] =
            visibleActionIDs.map { id in
                let backdrop: SendableCGImage? = switch id {
                case .portrait: boxedScene
                case .removeBackground: boxedOriginal
                default: nil
                }
                return (id, id.previewAction, backdrop)
            }
        await withTaskGroup(of: (EnhanceActionID, EnhanceTileLayers?).self) { group in
            for (id, action, backdrop) in jobs {
                group.addTask {
                    let layers = EnhanceTilePreview.renderLayers(
                        action: action,
                        prepared: prepared,
                        backdrop: backdrop?.cgImage
                    )
                    return (id, layers.map(EnhanceTileLayers.init))
                }
            }
            for await (id, layers) in group {
                if let layers { previewLayers[id] = layers }
            }
        }
    }

    /// Scène-JPEG (klein, gebundeld) decoderen + downscalen off-main.
    private nonisolated static func prepareScene(_ scene: NSImage?) async -> SendableCGImage? {
        guard let scene else { return nil }
        let boxed = SendableScene(image: scene)
        return await Task.detached(priority: .userInitiated) {
            boxed.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                .flatMap(EnhanceTilePreview.prepareBackdrop)
                .map { SendableCGImage(cgImage: $0) }
        }.value
    }

    private struct SendableScene: @unchecked Sendable {
        let image: NSImage
    }
}
