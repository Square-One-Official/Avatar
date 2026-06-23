// Face-paneel (E21.1, herzien E24.15 + E24.15-rev) — de generatieve Pro-acties
// (Whiten teeth/Apply make-up/Reduce wrinkles, 4 credits) in ÉÉN horizontaal-
// scrollbare rij gedeelde thumbnail-kaarten (DSThumbnailCard, dezelfde vorm als
// Effects). One-click retouch verhuisde naar Enhance (Thierry, 2026-06-23) — een
// lokale/gratis actie hoort bij de andere appearance-toggles. Restore body hoort
// hier ook NIET (→ Enhance, E24.9/E31.3).
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
    /// E32.1: resultaat van een generatieve face-edit toepassen (undo'baar).
    var onApply: (NSImage) -> Void = { _ in }
    var isPro: Bool = false

    @State private var model: FaceEffectsModel

    init(
        baseImage: NSImage,
        entitlement: EntitlementModel,
        onApply: @escaping (NSImage) -> Void = { _ in },
        isPro: Bool = false
    ) {
        self.baseImage = baseImage
        self.entitlement = entitlement
        self.onApply = onApply
        self.isPro = isPro
        _model = State(initialValue: FaceEffectsModel(
            entitlement: entitlement, baseImage: baseImage, onApply: onApply
        ))
    }

    private struct Card: Identifiable {
        let id = UUID()
        let title: String
        let icon: Ph
        var isCloud: Bool = false
        var isOn: Bool = false
        let handler: () -> Void
    }

    private var cards: [Card] {
        [
            Card(title: FaceEdit.whitenTeeth.label, icon: .tooth, isCloud: true,
                 handler: { model.apply(.whitenTeeth) }),
            Card(title: FaceEdit.applyMakeup.label, icon: .palette, isCloud: true,
                 handler: { model.apply(.applyMakeup) }),
            Card(title: FaceEdit.reduceWrinkles.label, icon: .smiley, isCloud: true,
                 handler: { model.apply(.reduceWrinkles) }),
        ]
    }

    private let cardWidth: CGFloat = 112
    private let cardHeight: CGFloat = 152

    var body: some View {
        let workingTitle = model.workingTitle
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.gap2) {
                ForEach(cards) { card in
                    let isWorking = workingTitle == card.title
                    Button(action: card.handler) {
                        DSThumbnailCard(
                            label: card.title,
                            isPro: card.isCloud && !isPro,
                            isSelected: card.isOn,
                            isWorking: isWorking,
                            tileSize: cardWidth,
                            tileHeight: cardHeight
                        ) {
                            card.icon.regular
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(workingTitle != nil)
                    .opacity(workingTitle != nil && !isWorking ? 0.5 : 1)
                }
            }
            .padding(.vertical, DSSpacing.gap2)
            .padding(.leading, DSSpacing.gap1_5)
            .scrollRowTrailingInset()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .horizontalScrollEdgeFade()
    }
}
