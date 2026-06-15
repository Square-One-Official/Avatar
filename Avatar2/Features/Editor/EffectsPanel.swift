// Effects-paneel (E09.2, Figma App / Effects): een "None"-kaart (terug naar
// origineel) + vier stijl-kaarten (clay, wood, 3d, scribble). E24.33: de gekozen
// stijl is de active state; nogmaals tikken = None. Resultaten worden per effect
// op het portret GECACHET → None ↔ effect ↔ ander effect is INSTANT en kost geen
// nieuwe credits; alleen het refresh-icoon in de actieve thumbnail hergenereert
// bewust (kost dan wel credits). De previews zijn placeholders (echte
// stijl-previews volgen later, zie ASSETS.md); generatie via productie-
// `/v1/stylize` (nano-banana default), credit-gegated, 402 → paywall-toast.

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
        case working(StylizeStyle)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Het toegepaste effect (active state), nil = None (basisbeeld).
    private(set) var selected: StylizeStyle?

    private let entitlement: EntitlementModel
    private let onApply: (NSImage) -> Void
    private let portrait: Portrait2?
    /// Het "None"/origineel-beeld waarop effecten worden gegenereerd.
    private(set) var base: NSImage
    /// Sessie-cache (gehydrateerd uit het portret) — rawValue → beeld.
    private var cache: [String: NSImage]

    init(
        entitlement: EntitlementModel,
        baseImage: NSImage,
        portrait: Portrait2?,
        onApply: @escaping (NSImage) -> Void
    ) {
        self.entitlement = entitlement
        self.onApply = onApply
        self.portrait = portrait

        // Hydrateer uit het portret (E24.33). Met een actief effect is `baseImage`
        // (de huidige cutout) het effect-beeld; de echte basis staat dan in
        // `effectBaseData`. Zonder actief effect ÍS de huidige cutout de basis.
        let active = portrait?.effectActiveRaw.flatMap { StylizeStyle(rawValue: $0) }
        self.selected = active
        if active != nil, let data = portrait?.effectBaseData, let img = NSImage(data: data) {
            self.base = img
        } else {
            self.base = baseImage
        }
        var hydrated: [String: NSImage] = [:]
        for (raw, data) in portrait?.effectCache ?? [:] {
            if let img = NSImage(data: data) { hydrated[raw] = img }
        }
        // Het actieve effect-beeld is de huidige cutout, ook als de cache nog leeg
        // is (bv. gegenereerd vóór deze cache bestond).
        if let active, hydrated[active.rawValue] == nil {
            hydrated[active.rawValue] = baseImage
        }
        self.cache = hydrated
    }

    var creditCost: Int { CreditMeter.credits(for: .generativeStandard) }

    var isBusy: Bool { if case .working = phase { return true } else { return false } }

    func isCached(_ style: StylizeStyle) -> Bool { cache[style.rawValue] != nil }

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
    func toggle(_ style: StylizeStyle) {
        guard !isBusy else { return }
        if selected == style {
            selectNone()
            return
        }
        if let cached = cache[style.rawValue] {
            // Cache-hit: INSTANT, geen backend-call, geen credits (E24.33).
            selected = style
            phase = .idle
            onApply(cached)
            persist()
            return
        }
        Task { await generate(style) }
    }

    /// Refresh-icoon op de actieve kaart: bewust opnieuw genereren (kost credits).
    func regenerate(_ style: StylizeStyle) {
        guard !isBusy else { return }
        Task { await generate(style) }
    }

    private func generate(_ style: StylizeStyle) async {
        // E18.2: contextuele gate (online uit → login → upgrade).
        guard entitlement.allowCloudFeature() else { return }
        guard let png = base.pngData() else {
            entitlement.presentError("Couldn't read the portrait.")
            return
        }
        phase = .working(style)
        do {
            let (data, _) = try await entitlement.backend.stylize(imagePNG: png, style: style)
            guard let image = NSImage(data: data) else {
                phase = .idle
                entitlement.presentError("The styled image came back unreadable.")
                return
            }
            cache[style.rawValue] = image
            selected = style
            phase = .idle
            onApply(image)
            persist()
            // Saldo bijwerken zodat de topbar-quota klopt na de aftrek.
            await entitlement.refresh()
        } catch BackendError.noCredits {
            phase = .idle
            entitlement.handleOutOfCredits()
        } catch {
            // E18.3: fout als toast i.p.v. inline tekst onder de menutitel.
            phase = .idle
            entitlement.presentError("Couldn't apply that style. Please try again.")
        }
    }

    /// Persisteer de Effects-staat op het portret (E24.33).
    private func persist() {
        guard let portrait else { return }
        if portrait.effectBaseData == nil {
            portrait.effectBaseData = base.pngData()
        }
        portrait.effectActiveRaw = selected?.rawValue
        portrait.effectCache = cache.compactMapValues { $0.pngData() }
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

    var body: some View {
        DSEditPanel(title: "Effects") {
            VStack(alignment: .leading, spacing: DSSpacing.gap3) {
                HStack(spacing: DSSpacing.gap2) {
                    Text("Apply a style")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                    Spacer(minLength: DSSpacing.gap4)
                    Label("\(model.creditCost)", systemImage: "bolt.fill")
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.subtle)
                        .labelStyle(.titleAndIcon)
                }

                if case .failed(let message) = model.phase {
                    Text(message)
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.gap3) {
                        noneCard
                        ForEach(StylizeStyle.allCases) { style in
                            styleCard(style)
                        }
                    }
                    // E24.15: ruimte zodat de hover-scale niet tegen de scroll-
                    // grens clipt (zoals de background-swatch-fix 24.10).
                    .padding(.vertical, DSSpacing.gap1)
                    .padding(.horizontal, DSSpacing.gap1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// E24.33: "None"-kaart helemaal links — terug naar het origineel (basis).
    private var noneCard: some View {
        Button {
            model.selectNone()
        } label: {
            DSThumbnailCard(label: "None", isSelected: model.selected == nil, tileSize: 84) {
                Image(nsImage: model.base)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipped()
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .opacity(model.isBusy ? 0.5 : 1)
    }

    private func styleCard(_ style: StylizeStyle) -> some View {
        let isSelected = model.selected == style
        let isWorking = model.phase == .working(style)
        // E24.15: gedeelde DSThumbnailCard (placeholder-icoon tot echte
        // stijl-thumbnails landen — ASSETS.md). E24.33: het refresh-icoon
        // verschijnt alleen op de actieve kaart (bewuste her-generatie).
        return Button {
            model.toggle(style)
        } label: {
            DSThumbnailCard(
                label: style.label,
                isSelected: isSelected,
                isWorking: isWorking,
                tileSize: 84,
                onRefresh: isSelected ? { model.regenerate(style) } : nil
            ) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .regular))
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .opacity(model.isBusy && !isWorking ? 0.5 : 1)
    }
}
