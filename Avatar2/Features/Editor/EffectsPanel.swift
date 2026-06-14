// Effects-paneel (E09.2, Figma App / Effects): vier stijl-kaarten (clay,
// wood, 3d, scribble). Géén Original-kaart — de gekozen stijl is de active
// state, nogmaals tikken deselecteert (terug naar het basisbeeld). De
// previews zijn placeholders (echte stijl-previews volgen later, zie
// ASSETS.md); de generatie loopt via het productie-`/v1/stylize` (E09.2,
// nano-banana default), credit-gegated (generatief standaard = 4 credits),
// 402 → paywall-toast.

import AppKit
import AvatarKit
import AvatarUI
import SwiftUI

/// Stuurt de stijl-generatie aan en reikt het resultaat omhoog naar de
/// ShellModel (die canvas + opgeslagen cutout vervangt). Het basisbeeld is
/// het portret zoals het bij het openen van het paneel op de kaart staat;
/// deselecteren herstelt dat lokaal (geen extra call/credits).
@MainActor
@Observable
final class EffectsModel {
    enum Phase: Equatable {
        case idle
        case working(StylizeStyle)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// De toegepaste stijl (active state), nil = basisbeeld.
    private(set) var selected: StylizeStyle?

    private let entitlement: EntitlementModel
    private let baseImage: NSImage
    private let onApply: (NSImage) -> Void

    init(entitlement: EntitlementModel, baseImage: NSImage, onApply: @escaping (NSImage) -> Void) {
        self.entitlement = entitlement
        self.baseImage = baseImage
        self.onApply = onApply
    }

    var creditCost: Int { CreditMeter.credits(for: .generativeStandard) }

    var isBusy: Bool { if case .working = phase { return true } else { return false } }

    /// Tik op een kaart: actieve stijl → deselecteer (herstel basis); andere
    /// stijl → genereer. Tijdens een lopende generatie negeren we tikken.
    func toggle(_ style: StylizeStyle) {
        guard !isBusy else { return }
        if selected == style {
            selected = nil
            phase = .idle
            onApply(baseImage)
            return
        }
        Task { await apply(style) }
    }

    private func apply(_ style: StylizeStyle) async {
        // E18.2: contextuele gate (online uit → login → upgrade).
        guard entitlement.allowCloudFeature() else { return }
        guard let png = Self.pngData(from: baseImage) else {
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
            selected = style
            phase = .idle
            onApply(image)
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

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

struct EffectsPanel: View {
    let baseImage: NSImage
    let entitlement: EntitlementModel
    var onApply: (NSImage) -> Void = { _ in }

    @State private var model: EffectsModel

    init(baseImage: NSImage, entitlement: EntitlementModel, onApply: @escaping (NSImage) -> Void = { _ in }) {
        self.baseImage = baseImage
        self.entitlement = entitlement
        self.onApply = onApply
        _model = State(initialValue: EffectsModel(entitlement: entitlement, baseImage: baseImage, onApply: onApply))
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
                        ForEach(StylizeStyle.allCases) { style in
                            styleCard(style)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func styleCard(_ style: StylizeStyle) -> some View {
        let isSelected = model.selected == style
        let isWorking = model.phase == .working(style)
        return Button {
            model.toggle(style)
        } label: {
            VStack(spacing: DSSpacing.gap2) {
                ZStack {
                    // Placeholder-preview (ASSETS.md): echte stijl-thumbnails
                    // levert Thierry later in batch.
                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .fill(DSColor.Background.neutral)
                        .frame(width: 84, height: 84)
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(DSColor.Foreground.muted)
                        }
                    if isWorking {
                        RoundedRectangle(cornerRadius: DSRadius.lg)
                            .fill(.black.opacity(0.35))
                            .frame(width: 84, height: 84)
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .strokeBorder(DSColor.Action.primary, lineWidth: 2)
                        .frame(width: 84, height: 84)
                        .opacity(isSelected ? 1 : 0)
                }
                Text(style.label)
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(isSelected ? DSColor.Foreground.primary : DSColor.Foreground.subtle)
            }
        }
        .buttonStyle(.plain)
        // E24.15: hover-state op de stijl-thumbnails (was afwezig).
        .dsHoverScale()
        .disabled(model.isBusy)
        .opacity(model.isBusy && !isWorking ? 0.5 : 1)
    }
}
