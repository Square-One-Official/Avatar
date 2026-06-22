// Face-paneel (E21.1, herzien E24.15 + E24.15-rev) — ALLE face-acties in ÉÉN
// horizontaal-scrollbare rij gedeelde thumbnail-kaarten (DSThumbnailCard,
// dezelfde vorm als Effects). GEEN sectie-labels meer (Retouch/Beauty laten
// vallen): One-click retouch (lokaal, aan/uit) + de generatieve Pro-acties
// (Whiten teeth/Apply make-up/Reduce wrinkles, 4 credits) staan direct naast
// elkaar, alles meteen zichtbaar. Restore body hoort hier NIET (→ AI-dropdown,
// E24.9).
//
// E32.1: de drie Beauty-acties zijn nu ECHT gewired op de face-intent van
// /v1/stylize (nano-banana instruction-edit) via FaceEffectsModel — daarvoor
// (E18.2) waren ze stubs die alleen de contextuele gate openden.

import AppKit
import AvatarKit
import AvatarUI
import PhosphorSwift
import SwiftUI

/// Stuurt de generatieve face-edits (Whiten teeth/Apply make-up/Reduce
/// wrinkles) aan en reikt het resultaat omhoog naar de ShellModel (canvas +
/// opgeslagen cutout). Spiegelt EffectsModel: gate → working-toast → backend →
/// onApply → saldo-refresh; 402 → paywall. Anders dan Effects is er geen
/// effect-cache: een face-edit is een eenmalige bewerking op het huidige beeld
/// (undo'baar via de onApply-helper in EditorView), niet een aan/uit-toggle.
@MainActor
@Observable
final class FaceEffectsModel {
    enum Phase: Equatable {
        case idle
        case working(FaceEdit)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    private let entitlement: EntitlementModel
    private let baseImage: NSImage
    private let onApply: (NSImage) -> Void

    init(
        entitlement: EntitlementModel,
        baseImage: NSImage,
        onApply: @escaping (NSImage) -> Void
    ) {
        self.entitlement = entitlement
        self.baseImage = baseImage
        self.onApply = onApply
    }

    var isBusy: Bool { if case .working = phase { return true } else { return false } }

    /// De titel van de kaart die momenteel verwerkt (nil = idle) — voedt de
    /// spinner/dim-logica in FaceActionsPanel, net als EffectsPanel.isWorking.
    var workingTitle: String? {
        if case let .working(edit) = phase { return edit.label }
        return nil
    }

    /// Tik op een Beauty-kaart: gate → genereren. Tijdens een lopende edit
    /// negeren we tikken.
    func apply(_ edit: FaceEdit) {
        guard !isBusy else { return }
        Task { await generate(edit) }
    }

    private func generate(_ edit: FaceEdit) async {
        // E18.2: contextuele gate (online uit → login → upgrade).
        guard entitlement.allowCloudFeature() else { return }
        guard let png = baseImage.pngData() else {
            entitlement.presentError("Couldn't read the portrait.")
            return
        }
        phase = .working(edit)
        entitlement.presentWorking(
            title: edit.label,
            messages: [
                "Reading the portrait…",
                "Working on the details…",
                "Keeping it natural…",
                "Almost there…",
                "Adding the finishing touches…",
            ]
        )
        do {
            let (data, _) = try await entitlement.backend.editFace(imagePNG: png, preset: edit)
            guard let image = NSImage(data: data) else {
                phase = .idle
                entitlement.dismissWorkingToast()
                entitlement.presentError("The edited image came back unreadable.")
                return
            }
            phase = .idle
            entitlement.dismissWorkingToast()
            onApply(image)
            // Saldo bijwerken zodat de topbar-quota klopt na de aftrek.
            await entitlement.refresh()
        } catch BackendError.noCredits {
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.handleOutOfCredits()
        } catch {
            phase = .idle
            entitlement.dismissWorkingToast()
            entitlement.presentError("Couldn't apply that edit. Please try again.")
        }
    }
}

struct FaceActionsPanel: View {
    let baseImage: NSImage
    let entitlement: EntitlementModel
    /// E12.1: lokale Core Image-retouch (geen cloud/credits) — aan/uit.
    var onRetouch: () -> Void = {}
    /// E32.1: resultaat van een generatieve face-edit toepassen (undo'baar).
    var onApply: (NSImage) -> Void = { _ in }
    var isPro: Bool = false
    /// E18.12: titels van lokale enhances die momenteel "aan" staan.
    var activeToggles: Set<String> = []

    @State private var model: FaceEffectsModel

    init(
        baseImage: NSImage,
        entitlement: EntitlementModel,
        onRetouch: @escaping () -> Void = {},
        onApply: @escaping (NSImage) -> Void = { _ in },
        isPro: Bool = false,
        activeToggles: Set<String> = []
    ) {
        self.baseImage = baseImage
        self.entitlement = entitlement
        self.onRetouch = onRetouch
        self.onApply = onApply
        self.isPro = isPro
        self.activeToggles = activeToggles
        _model = State(initialValue: FaceEffectsModel(
            entitlement: entitlement, baseImage: baseImage, onApply: onApply
        ))
    }

    private struct Card: Identifiable {
        let id = UUID()
        let title: String
        let icon: Ph
        var credits: String? = nil
        var isCloud: Bool = false
        var isOn: Bool = false
        let handler: () -> Void
    }

    private var cards: [Card] {
        let beautyCredits = CreditMeter.chipLabel(for: .generativeStandard)
        return [
            Card(title: "One click retouch", icon: .magicWand,
                 isOn: activeToggles.contains("One click retouch"), handler: onRetouch),
            Card(title: FaceEdit.whitenTeeth.label, icon: .tooth, credits: beautyCredits, isCloud: true,
                 handler: { model.apply(.whitenTeeth) }),
            Card(title: FaceEdit.applyMakeup.label, icon: .palette, credits: beautyCredits, isCloud: true,
                 handler: { model.apply(.applyMakeup) }),
            Card(title: FaceEdit.reduceWrinkles.label, icon: .smiley, credits: beautyCredits, isCloud: true,
                 handler: { model.apply(.reduceWrinkles) }),
        ]
    }

    var body: some View {
        // E24.15-rev: één doorlopende rij, geen secties, alles direct zichtbaar.
        let workingTitle = model.workingTitle
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.gap3) {
                ForEach(cards) { card in
                    let isWorking = workingTitle == card.title
                    Button(action: card.handler) {
                        DSThumbnailCard(
                            label: card.title,
                            isPro: card.isCloud && !isPro,
                            credits: card.credits,
                            isSelected: card.isOn,
                            isWorking: isWorking
                        ) {
                            card.icon.regular
                                .scaledToFit()
                                .frame(width: 26, height: 26)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(workingTitle != nil)
                    .opacity(workingTitle != nil && !isWorking ? 0.5 : 1)
                }
            }
            // Ruimte voor de hover-scale + de top-leading Pro-badge.
            .padding(.vertical, DSSpacing.gap1)
            .padding(.horizontal, DSSpacing.gap1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
