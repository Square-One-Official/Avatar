// Hair-paneel (E11.2, Figma App / Hair). Zelfde patroon als Clothes:
// kapsel-chips + een vrije beschrijving. Copy uit het figma-design-review-
// voorstel (chips: Trim flyaways / Curly / Straight / Short / Updo;
// placeholder "Describe a color or style"; comb-glyph i.p.v. schaar). De
// generatie loopt via het productie-`/v1/stylize` (E09.2) met de hair-intent
// (E11.2-backend), nano-banana instruction-edit (E11.1-route): alléén het
// haar wijzigt, gezicht/expressie/kleding identiek. Net als Clothes vertrouwen
// we op die model-instructie en re-isoleert ShellModel.applyEffectResult het
// volle resultaat (geen lokale crown-mask). Credit-gegated (generatief
// standaard = 4), 402 → paywall.

import AppKit
import AvatarKit
import AvatarUI
import SwiftUI

/// Stuurt de kapselwissel aan en reikt het resultaat omhoog naar de
/// ShellModel (canvas + opgeslagen cutout). Elke edit vertrekt vanaf het
/// meegegeven basisbeeld (het huidige portret op de kaart).
@MainActor
@Observable
final class HairModel {
    enum Phase: Equatable {
        case idle
        case working
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    private let entitlement: EntitlementModel
    private let onApply: (NSImage) -> Void

    init(entitlement: EntitlementModel, onApply: @escaping (NSImage) -> Void) {
        self.entitlement = entitlement
        self.onApply = onApply
    }

    var creditCost: Int { CreditMeter.credits(for: .generativeStandard) }
    var isBusy: Bool { phase == .working }

    func apply(preset: HairStyle? = nil, freeText: String? = nil, base: NSImage) async {
        guard !isBusy else { return }
        // E18.2: contextuele gate (online uit → login → upgrade).
        guard entitlement.allowCloudFeature() else { return }
        guard let png = base.pngData() else {
            entitlement.presentError("Couldn't read the portrait.")
            return
        }
        phase = .working
        entitlement.presentWorking(
            title: "Changing hair",
            messages: [
                "Touching up the hair…",
                "Trimming the flyaways…",
                "Consulting with the stylist…",
                "Every strand counts…",
                "Having second thoughts…",
                "Almost there, promise…",
            ]
        )
        do {
            let (data, _) = try await entitlement.backend.editHair(imagePNG: png, preset: preset, freeText: freeText)
            guard let image = NSImage(data: data) else {
                phase = .idle
                entitlement.dismissWorkingToast()
                entitlement.presentError("The result came back unreadable.")
                return
            }
            // Zelfde route als Clothes (E10.4): het model wijzigt alléén het
            // haar (instructie houdt gezicht/expressie/kleding identiek) en
            // ShellModel.applyEffectResult re-isoleert het volle resultaat zodat
            // de transparantie terugkomt. Geen lokale crown-mask meer — die
            // plakte de grijze model-achtergrond als halo rond het haar.
            phase = .idle
            entitlement.dismissWorkingToast()
            onApply(image)
            await entitlement.refresh()
        } catch BackendError.noCredits {
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.handleOutOfCredits()
        } catch {
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.presentError("Couldn't change the hair. Please try again.")
        }
    }

}

struct HairPanel: View {
    let baseImage: NSImage
    let entitlement: EntitlementModel
    var onApply: (NSImage) -> Void = { _ in }

    @State private var model: HairModel
    @State private var prompt = ""

    init(baseImage: NSImage, entitlement: EntitlementModel, onApply: @escaping (NSImage) -> Void = { _ in }) {
        self.baseImage = baseImage
        self.entitlement = entitlement
        self.onApply = onApply
        _model = State(initialValue: HairModel(entitlement: entitlement, onApply: onApply))
    }

    var body: some View {
        DSEditPanel(title: "Change hair", credits: CreditMeter.chipLabel(for: .generativeStandard)) {
            VStack(alignment: .leading, spacing: DSSpacing.gap4) {

                // Kapsel-presets.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.gap2) {
                        ForEach(HairStyle.allCases) { style in
                            DSChip(style.label, type: .neutral) {
                                Task { await model.apply(preset: style, base: baseImage) }
                            }
                        }
                    }
                    .scrollRowTrailingInset()
                }
                .horizontalScrollEdgeFade()

                // Vrije beschrijving + send.
                HStack(spacing: DSSpacing.gap2) {
                    DSTextField(placeholder: "Describe a color or style", text: $prompt)
                    Button {
                        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        Task { await model.apply(freeText: trimmed, base: baseImage) }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DSColor.Action.onAction)
                            .frame(width: 40, height: 40)
                            .background(DSColor.Action.primary)
                            .clipShape(Circle())
                            .opacity(prompt.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(model.isBusy)
        }
    }
}
