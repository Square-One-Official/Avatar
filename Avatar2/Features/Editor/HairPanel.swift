// Hair-paneel (E11.2, Figma App / Hair). Zelfde patroon als Clothes:
// kapsel-chips + een vrije beschrijving. Copy uit het figma-design-review-
// voorstel (chips: Trim flyaways / Curly / Straight / Short / Updo;
// placeholder "Describe a color or style"; comb-glyph i.p.v. schaar). De
// generatie loopt via het productie-`/v1/stylize` (E09.2) met de hair-intent
// (E11.2-backend), nano-banana instruction-edit (E11.1-route): alléén het
// haar wijzigt, gezicht/expressie/kleding identiek. Credit-gegated
// (generatief standaard = 4), 402 → paywall.

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
        guard let png = Self.pngData(from: base) else {
            phase = .failed("Couldn't read the portrait.")
            return
        }
        phase = .working
        do {
            let (data, _) = try await entitlement.backend.editHair(imagePNG: png, preset: preset, freeText: freeText)
            guard let image = NSImage(data: data) else {
                phase = .failed("The result came back unreadable.")
                return
            }
            phase = .idle
            onApply(image)
            await entitlement.refresh()
        } catch BackendError.noCredits {
            phase = .idle
            entitlement.handleOutOfCredits()
        } catch {
            phase = .failed("Couldn't change the hair. Please try again.")
        }
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
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
        DSEditPanel(title: "Change hair") {
            VStack(alignment: .leading, spacing: DSSpacing.gap3) {
                HStack(spacing: DSSpacing.gap2) {
                    if model.isBusy {
                        ProgressView().controlSize(.small)
                        Text("Changing hair…")
                            .dsTextStyle(.bodySmall)
                            .foregroundStyle(DSColor.Foreground.muted)
                    } else if case .failed(let message) = model.phase {
                        Text(message)
                            .dsTextStyle(.bodySmall)
                            .foregroundStyle(DSColor.Foreground.muted)
                    }
                    Spacer(minLength: DSSpacing.gap4)
                    Label("\(model.creditCost)", systemImage: "bolt.fill")
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.subtle)
                        .labelStyle(.titleAndIcon)
                }

                // Kapsel-presets.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.gap2) {
                        ForEach(HairStyle.allCases) { style in
                            DSChip(style.label, type: .neutral) {
                                Task { await model.apply(preset: style, base: baseImage) }
                            }
                        }
                    }
                }

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
