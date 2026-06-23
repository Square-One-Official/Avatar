// Clothes-paneel (E10.2 + E10.4-wiring, Figma App / Clothes 4016:13760):
// "Change upper clothes" + vaste outfit-chips + een vrije prompt ("Describe
// a color or style") met lime send-knop.
//
// Generatie-route (besluit Thierry 2026-06-13): nano-banana instruction-edit
// via het productie-`/v1/stylize` (clothes-intent, E10.4). Hard
// acceptatiecriterium server-side afgedwongen: alléén de kleding wijzigt,
// gezicht/haar/pose/achtergrond identiek. FLUX-Fill + mask (E10.1) blijft de
// precisie-fallback, geen default. Credit-gegated (generatief standaard = 4),
// 402 → paywall.

import AppKit
import AvatarKit
import AvatarUI
import SwiftUI

/// Stuurt de kledingwissel aan en reikt het resultaat omhoog naar de
/// ShellModel (canvas + opgeslagen cutout). Zelfde patroon als HairModel.
@MainActor
@Observable
final class ClothesModel {
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

    func apply(preset: ClothesStyle? = nil, freeText: String? = nil, base: NSImage) async {
        guard !isBusy else { return }
        // E18.2: contextuele gate (online uit → login → upgrade).
        guard entitlement.allowCloudFeature() else { return }
        guard let png = base.pngData() else {
            entitlement.presentError("Couldn't read the portrait.")
            return
        }
        phase = .working
        entitlement.presentWorking(
            title: "Changing clothing",
            messages: [
                "Picking the right fit…",
                "Pressing the wrinkles out…",
                "Checking the stitching…",
                "Did someone say outfit change?",
                "Looking sharp…",
                "Almost dressed…",
            ]
        )
        do {
            let (data, _) = try await entitlement.backend.editClothes(imagePNG: png, preset: preset, freeText: freeText)
            guard let image = NSImage(data: data) else {
                phase = .idle
                entitlement.dismissWorkingToast()
                entitlement.presentError("The result came back unreadable.")
                return
            }
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
            entitlement.presentError("Couldn't change the clothing. Please try again.")
        }
    }

}

struct ClothesPanel: View {
    let baseImage: NSImage
    let entitlement: EntitlementModel
    var onApply: (NSImage) -> Void = { _ in }

    @State private var model: ClothesModel
    @State private var prompt = ""

    init(baseImage: NSImage, entitlement: EntitlementModel, onApply: @escaping (NSImage) -> Void = { _ in }) {
        self.baseImage = baseImage
        self.entitlement = entitlement
        self.onApply = onApply
        _model = State(initialValue: ClothesModel(entitlement: entitlement, onApply: onApply))
    }

    var body: some View {
        DSEditPanel(title: "Change upper clothes", credits: CreditMeter.chipLabel(for: .generativeStandard)) {
            VStack(alignment: .leading, spacing: DSSpacing.gap4) {

                // Outfit-presets.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.gap2) {
                        ForEach(ClothesStyle.allCases) { preset in
                            DSChip(preset.label, type: .neutral) {
                                Task { await model.apply(preset: preset, base: baseImage) }
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
