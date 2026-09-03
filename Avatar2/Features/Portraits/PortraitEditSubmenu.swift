// E57.2–57.6 — de "Edit ▸"-tak van het portret-menu: Boost resolution ▸,
// Fill in body en Apply effect ▸ als set-acties op 1…N portretten. Eén view
// voor élk portret-menu (tegelmenu op Home/Portraits, board-node-menu), zodat
// een nieuwe Edit-actie overal tegelijk verschijnt.

import AvatarKit
import AvatarUI
import SwiftUI

struct PortraitEditSubmenu: View {
    let targets: [Portrait2]
    let model: ShellModel
    let entitlement: EntitlementModel
    let undoManager: UndoManager?
    let onDismiss: () -> Void

    var body: some View {
        editSubmenu
    }

    // MARK: - Edit ▸

    /// Eén lopende Edit-batch tegelijk: dezelfde bron als de editor-chips
    /// (`workingContext.blocksOtherAIFeatures`) plus de set-actie-toast.
    private var editIsBusy: Bool {
        model.isSetActionBusy || entitlement.workingContext?.blocksOtherAIFeatures == true
    }

    /// Edit ▸ Boost resolution ▸ (On device / Online) · Fill in body · Apply
    /// effect ▸ — voor 1…N portretten. Geen "…on N" in de rij-copy (Thierry
    /// 2026-09-03); het aantal zit in de credits-labels en de bon.
    @ViewBuilder private var editSubmenu: some View {
        let n = targets.count
        // E57.5: reden bij de disabled-staat (native tooltip; de rij zelf
        // heeft geen DS-tooltip-slot).
        DSMenuSubmenu("Edit", icon: "wand.and.stars", disabled: editIsBusy, minWidth: 230) {
            DSMenuSubmenu("Boost resolution", icon: "arrow.up.left.and.arrow.down.right", minWidth: 230) {
                boostRows(targets: targets)
            }
            // E57.3: zelfde contract als de editor-tegel (E56) — alleen echt
            // afgesneden randen; zonder afgesneden rand een gratis no-op.
            DSMenuRow("Fill in body", icon: "figure.arms.open", shortcut: fillBodyLabel(count: n)) {
                onDismiss()
                PortraitSetActions.fillBody(
                    targets, entitlement: entitlement,
                    undoManager: undoManager, reporter: model.setActionReporter
                )
            }
            // E57.4: stijlen uit dezelfde lijst als het Effects-paneel.
            DSMenuSubmenu("Apply effect", icon: "sparkles", minWidth: 250) {
                effectRows(targets: targets)
            }
        }
        .help(editIsBusy ? "Wait for the current edit to finish" : "Boost resolution, fill in body or apply a style")
    }

    /// None · eigen effecten (Pro) · built-in stijlen. Label rechts: "Cached"
    /// als geen enkel portret hoeft te genereren, anders het credits-totaal
    /// voor de portretten die wél genereren (zonder Cloud-tier: "Cloud").
    @ViewBuilder private func effectRows(targets: [Portrait2]) -> some View {
        let list = EffectsModel.cachedEffectList(entitlement: entitlement)
        if targets.contains(where: { $0.effectActiveRaw != nil }) {
            DSMenuRow("None", icon: "circle.slash") {
                runEffect(.none, on: targets, list: list.builtin)
            }
            Divider().padding(.vertical, 2)
        }
        if !list.custom.isEmpty {
            ForEach(list.custom) { effect in
                DSMenuRow(
                    effect.label, icon: "sparkles",
                    shortcut: effectLabel(targets, choice: .custom(effect)),
                    accessory: { DSProChip() }
                ) {
                    runEffect(.custom(effect), on: targets, list: list.builtin)
                }
            }
            Divider().padding(.vertical, 2)
        }
        ForEach(list.builtin) { effect in
            DSMenuRow(
                effect.label, icon: effect.isDieCut ? "seal" : "paintbrush",
                shortcut: effectLabel(targets, choice: .builtin(effect))
            ) {
                runEffect(.builtin(effect), on: targets, list: list.builtin)
            }
        }
    }

    private func effectLabel(_ targets: [Portrait2], choice: PortraitSetActions.EffectChoice) -> String {
        let generating = PortraitSetActions.effectGenerationCount(targets, choice: choice)
        guard generating > 0 else { return "Cached" }
        guard PrivacyPreferences2.shared.allowsThirdPartyCloud else { return "Cloud" }
        let total = CreditMeter.credits(for: .generativeStandard) * generating
        return total == 1 ? "1 credit" : "\(total) credits"
    }

    private func runEffect(_ choice: PortraitSetActions.EffectChoice, on targets: [Portrait2], list: [RemoteEffect]) {
        onDismiss()
        PortraitSetActions.applyEffect(
            targets, choice: choice,
            isDieCut: { key in list.first { $0.key == key }?.isDieCut ?? false },
            model: model, entitlement: entitlement,
            undoManager: undoManager, reporter: model.setActionReporter
        )
    }

    /// Credits-totaal (2 per portret; alleen afgeschreven als er echt gevuld
    /// wordt); zonder Cloud-tier de neutrale "Cloud"-hint, zoals bij Boost.
    private func fillBodyLabel(count: Int) -> String {
        guard PrivacyPreferences2.shared.allowsThirdPartyCloud else { return "Cloud" }
        let total = CreditMeter.credits(for: .fillBody) * count
        return total == 1 ? "1 credit" : "\(total) credits"
    }

    /// Boost-modus kiezen. Online toont het totaal aan credits (3 per
    /// portret); zonder Cloud-tier de neutrale "Cloud"-hint — de gate vraagt
    /// dan zelf om de tier te verhogen (zoals in de editor).
    @ViewBuilder private func boostRows(targets: [Portrait2]) -> some View {
        let onlineLabel: String = {
            guard PrivacyPreferences2.shared.allowsThirdPartyCloud else { return "Sharper · Cloud" }
            let total = CreditMeter.credits(for: .upscaleHigh) * targets.count
            return "Best · \(total == 1 ? "1 credit" : "\(total) credits")"
        }()
        DSMenuRow("On device", icon: "desktopcomputer", shortcut: "Free") {
            onDismiss()
            PortraitSetActions.boostResolution(
                targets, mode: .local, entitlement: entitlement,
                undoManager: undoManager, reporter: model.setActionReporter
            )
        }
        DSMenuRow("Online", icon: "cloud", shortcut: onlineLabel) {
            onDismiss()
            PortraitSetActions.boostResolution(
                targets, mode: .online, entitlement: entitlement,
                undoManager: undoManager, reporter: model.setActionReporter
            )
        }
    }

}
