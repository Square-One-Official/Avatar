// Edit-paneel (E22.3) — live handmatige color-correctie. Vier sliders
// (Brightness/Contrast/Saturation/Temperature) passen meteen toe op de canvas
// (goedkope preview via onPreview); op het loslaten van een slider commit een
// undo-bare stap (onCommit before→after). Reset zet alles neutraal.
// De één-tik-acties (One click retouch/Studio Light/Colorise/Boost/Fill in body)
// staan als compacte chips bovenin het Enhance-paneel. One-click retouch verhuisde
// hierheen uit het Face-paneel (Thierry, 2026-06-23).

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

/// Levert de scherm-bounds van elke menu-chip omhoog naar het paneel, zodat het
/// dropdown-paneel BUITEN de gemaskeerde scroll-rij (en dus ongecliped) onder de
/// juiste chip kan zweven.
private struct ChipAnchorKey: PreferenceKey {
    static let defaultValue: [ChipMenu: Anchor<CGRect>] = [:]
    static func reduce(value: inout [ChipMenu: Anchor<CGRect>],
                       nextValue: () -> [ChipMenu: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

struct EditColorPanel: View {
    /// E24.14: de RAUWE cutout (zonder Adjust-laag). De sliders renderen er live
    /// bovenop; de commit persisteert alléén de params (niet-destructief).
    let source: NSImage
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
    /// E41.2: Boost met de gekozen modus (lokaal/gratis of online/1 credit).
    var onBoost: (BoostMode) -> Void = { _ in }
    // E31.3: verhuisde mee uit de frame-toolbar-AI-dropdown. E31.8 (audit C4):
    // canonieke naam is "Fill in body" (chip + toast + undo-entry) — de oude
    // chip-naam "Restore body" botste met de overflow-actie "Restore to
    // original" (re-isolate, een andere functie).
    var onFillBody: () -> Void = {}
    /// Verwijder de achtergrond: her-isoleer het onderwerp (altijd on-device).
    /// Draait met de actieve engine — ORMBG als "High quality" geïnstalleerd is,
    /// anders Apple Vision ("Regular quality"). Nooit een credit.
    var onRemoveBackground: () -> Void = {}
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

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            // E24.27: één-tik AI-acties bovenin als compacte DS-chips (Pro/credit
            // waar van toepassing) → divider → de manuele sliders eronder.
            if showsQuickActions {
                VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DSSpacing.gap2) {
                            if showRetouch {
                                quickAction("One click retouch", icon: "wand.and.stars", isOn: retouchOn, action: onRetouch)
                            }
                            if showAutoEnhance {
                                quickAction("Studio Light", icon: "sun.max", isOn: studioLightOn, action: onStudioLight)
                                quickAction("Portrait", icon: "camera.aperture", isOn: portraitOn, action: onPortrait)
                                quickAction("Colorise", icon: "paintbrush.pointed", pro: !isPro, action: onColorise)
                                boostMenuChip
                                // E31.8 (audit C4): canonieke naam + de echte
                                // 2-credit-prijs via CreditMeter (getest label).
                                quickAction("Fill in body", icon: "person.crop.rectangle", pro: !isPro,
                                            credit: CreditMeter.chipLabel(for: .fillBody), action: onFillBody)
                            }
                            if showRemoveBackground {
                                removeBackgroundMenuChip
                            }
                            if showAppleEdit {
                                ImagePlaygroundEditChip(
                                    entitlement: entitlement,
                                    sourceImage: source,
                                    onEdited: onAppleEdit
                                )
                            }
                        }
                        .padding(.vertical, DSSpacing.gap1)
                        .scrollRowTrailingInset()
                    }
                    .horizontalScrollEdgeFade()

                    if showHybridCoachmark {
                        hybridCoachmark
                    }
                }
                Divider()
            }

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
        .frame(maxWidth: .infinity, alignment: .leading)
        // De Boost-/Remove background-dropdowns leven BUITEN de gemaskeerde
        // scroll-rij (zie comment bij `openMenu`); hier zwevend bovenop het
        // paneel zodat ze niet door de rij-clip worden afgekapt.
        .overlayPreferenceValue(ChipAnchorKey.self) { anchors in
            chipMenuOverlay(anchors)
        }
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
            if sourceCG == nil,
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
    }

    /// E24.27/24.28: compacte één-tik-actie-chip met optionele Pro-badge/credit
    /// en — voor toggle-acties — een duidelijke active-state (lime fill + check).
    private func quickAction(_ label: String, icon: String, pro: Bool = false,
                             credit: String? = nil, isOn: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap1) {
                Image(systemName: isOn ? "checkmark" : icon).font(.system(size: 12, weight: .medium))
                Text(label).dsTextStyle(.labelSmall)
                // E31.8: Pro-badge en credit-prijs zijn onafhankelijk — een
                // betaalde Pro-actie toont beide (Pro-gate én wat 'ie kost).
                if pro {
                    DSProChip()
                }
                if let credit {
                    DSBadge(credit, type: .neutral, compact: true)
                }
            }
            // E24.28: lime fill + onAction-tekst als de toggle AAN staat.
            .foregroundStyle(isOn ? DSColor.Action.onAction : DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 32)
            .background(isOn ? DSColor.Action.primary : DSColor.Background.neutral, in: Capsule())
        }
        .buttonStyle(.plain)
        .dsHoverScale()
        .fixedSize()
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DSSpacing.gap1)
    }

    private func noteHybridFallbackIfNeeded() {
        guard !advancedAllowed, HybridFallbackCoachmark.shouldShow else { return }
        showHybridCoachmark = true
    }

    /// E41.2: Boost-chip — alleen de knop; het dropdown-paneel rendert in
    /// `chipMenuOverlay` (buiten de scroll-clip).
    private var boostMenuChip: some View {
        Button {
            toggleMenu(.boost)
        } label: {
            HStack(spacing: DSSpacing.gap1) {
                Image(systemName: "arrow.up.backward.and.arrow.down.forward").font(.system(size: 12, weight: .medium))
                Text("Boost").dsTextStyle(.labelSmall)
                Text(boostMode.costLabel)
                    .dsTextStyle(.labelSmall).foregroundStyle(DSColor.Foreground.muted)
                DSPrivacyBadge(tier: boostMode == .local ? .onDevice : .thirdParty)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            .foregroundStyle(DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 32)
            .background(DSColor.Background.neutral, in: Capsule())
        }
        .buttonStyle(.plain)
        .dsHoverScale()
        .fixedSize()
        .anchorPreference(key: ChipAnchorKey.self, value: .bounds) { [ChipMenu.boost: $0] }
    }

    /// Het Boost-dropdown-paneel (gerenderd in de overlay, niet op de chip).
    private var boostMenu: some View {
        DSContextMenuPanel(minWidth: 230) {
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
                    : "Sharper · Advanced privacy"
            ) {
                openMenu = nil
                boostMode = .online
                onBoost(.online)
            }
        }
    }

    /// Remove background — altijd on-device, nooit een credit. Met het High-
    /// quality-model (ORMBG) geïnstalleerd is dit één simpele knop; zonder het
    /// model kiest de gebruiker per keer Regular (Vision, direct) of High
    /// (eenmalige download). Tijdens downloaden toont de chip voortgang.
    /// High quality (ORMBG) actief = de import/cutout draait er al op. Reactief op
    /// de gedeelde voorkeur, dus consistent met welke engine de cutout écht kiest.
    private var highQualityActive: Bool {
        PrivacyPreferences2.shared.engine == .downloadedModel
    }

    @ViewBuilder
    private var removeBackgroundMenuChip: some View {
        if case .downloading(let fraction) = hiFiModel.phase {
            cutoutDownloadingChip(fraction)
        } else if highQualityActive {
            cutoutSimpleChip
        } else {
            cutoutChoiceChip
        }
    }

    /// Model actief → één gratis knop die meteen vrijstaand maakt (High quality).
    private var cutoutSimpleChip: some View {
        Button { onRemoveBackground() } label: {
            cutoutChipLabel(trailingIcon: nil)
        }
        .buttonStyle(.plain)
        .dsHoverScale()
        .fixedSize()
    }

    /// Model nog niet gedownload → chevron opent de Regular/High-keuze.
    private var cutoutChoiceChip: some View {
        Button { toggleMenu(.removeBackground) } label: {
            cutoutChipLabel(trailingIcon: "chevron.down")
        }
        .buttonStyle(.plain)
        .dsHoverScale()
        .fixedSize()
        .anchorPreference(key: ChipAnchorKey.self, value: .bounds) { [ChipMenu.removeBackground: $0] }
    }

    private func cutoutDownloadingChip(_ fraction: Double) -> some View {
        HStack(spacing: DSSpacing.gap1) {
            Image(systemName: "arrow.down.circle").font(.system(size: 12, weight: .medium))
            Text("Downloading… \(Int(fraction * 100))%")
                .dsTextStyle(.labelSmall)
                .monospacedDigit()
                .foregroundStyle(DSColor.Foreground.muted)
        }
        .foregroundStyle(DSColor.Foreground.primary)
        .padding(.horizontal, DSSpacing.gap2)
        .frame(height: 32)
        .background(DSColor.Background.neutral, in: Capsule())
        .fixedSize()
    }

    private func cutoutChipLabel(trailingIcon: String?) -> some View {
        HStack(spacing: DSSpacing.gap1) {
            Image(systemName: "scissors").font(.system(size: 12, weight: .medium))
            Text("Remove background").dsTextStyle(.labelSmall)
            if let trailingIcon {
                Image(systemName: trailingIcon).font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.muted)
            }
        }
        .foregroundStyle(DSColor.Foreground.primary)
        .padding(.horizontal, DSSpacing.gap2)
        .frame(height: 32)
        .background(DSColor.Background.neutral, in: Capsule())
    }

    private var removeBackgroundMenu: some View {
        DSContextMenuPanel(minWidth: 230) {
            DSMenuRow("Regular quality", icon: "bolt", shortcut: "Instant") {
                openMenu = nil
                onRemoveBackground()
            }
            DSMenuRow("High quality", icon: "sparkles", shortcut: "Sharper hair · 78 MB") {
                openMenu = nil
                // Download het model (voortgang op de chip), zet het meteen als
                // actieve engine — ook latere imports gebruiken het dan — en maak
                // het beeld vrijstaand zodra het binnen is.
                hiFiModel.download {
                    PrivacyPreferences2.shared.engine = .downloadedModel
                    onRemoveBackground()
                }
            }
        }
    }

    private func toggleMenu(_ menu: ChipMenu) {
        openMenu = (openMenu == menu) ? nil : menu
    }

    /// Rendert het open dropdown-paneel zwevend onder de bijbehorende chip, plus
    /// een transparante vanglaag die bij een tik erbuiten sluit. Leeft buiten de
    /// gemaskeerde scroll-rij, dus wordt niet afgekapt.
    @ViewBuilder
    private func chipMenuOverlay(_ anchors: [ChipMenu: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if openMenu != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { openMenu = nil }
                }
                if openMenu == .boost, let anchor = anchors[.boost] {
                    floatingMenu(boostMenu, at: proxy[anchor], in: proxy.size)
                }
                if openMenu == .removeBackground, let anchor = anchors[.removeBackground] {
                    floatingMenu(removeBackgroundMenu, at: proxy[anchor], in: proxy.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Dicht: laat alle tikken door naar de sliders eronder. Open: vang ze
        // (vanglaag sluit, menu-rijen reageren).
        .allowsHitTesting(openMenu != nil)
        .animation(DSMotion.fast, value: openMenu)
    }

    private func floatingMenu<Menu: View>(_ menu: Menu, at chip: CGRect, in size: CGSize) -> some View {
        let menuWidth: CGFloat = 230
        let x = max(0, min(chip.minX, size.width - menuWidth))
        return menu
            .fixedSize()
            .offset(x: x, y: chip.maxY + DSSpacing.gap2)
            .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
    }

    /// Online-pad altijd zichtbaar; muted wanneer Advanced tier nog niet actief is.
    private func onlineHybridMenuRow(
        title: String,
        shortcut: String,
        action: @escaping () -> Void
    ) -> some View {
        DSMenuRow(title, icon: "cloud", shortcut: shortcut, action: action)
            .opacity(advancedAllowed ? 1 : 0.55)
            .overlay(alignment: .trailing) {
                if !advancedAllowed {
                    DSPrivacyBadge(tier: .thirdParty)
                        .padding(.trailing, DSSpacing.gap2)
                }
            }
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            Text(label)
                .dsTextStyle(.bodySmall)
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
}
