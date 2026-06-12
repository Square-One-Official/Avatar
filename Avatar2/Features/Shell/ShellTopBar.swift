// Shell-topbar (E04.5, Figma: App-frames node "top" 4017:1921 + gear
// "Frame 27"). Links naast de window-controls: quota-label (Labels/Small,
// "x/3 left" free · "x credits" Pro) + Upgrade-chip (brand). Rechts: gear
// in 48-cirkel (zelfde idioom als de toolbar-tools); de actie stuurt de
// standaard Settings-selector — functioneel zodra E15.1 de Settings-scene
// levert. Zichtbaarheid quota/Upgrade volgt het E05.1-besluit (pas ná de
// eerste cutout); de vorm is 1-op-1 Figma. Vervangt EntitlementStatusStrip.

import AvatarKit
import AvatarUI
import SwiftUI

struct ShellTopBar: View {
    let model: EntitlementModel

    var body: some View {
        HStack(spacing: 0) {
            if model.hasCompletedFirstCutout {
                HStack(spacing: DSSpacing.gap2) {
                    Text(quotaLabel)
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.primary)
                    DSChip("Upgrade", type: .brand) {
                        model.requestUpgrade()
                    }
                }
                // Figma "top": quota op x76 (na de window-controls), bar h52.
                .padding(.leading, 76 - DSSpacing.gap4)
            }
            Spacer()
            GearButton()
        }
        .padding(.horizontal, DSSpacing.gap4)
        .padding(.top, DSSpacing.gap3)
        .task { await model.refresh() }
    }

    private var quotaLabel: String {
        if model.isProActive {
            return "\(model.creditsRemaining) credits"
        }
        if let free = model.freeImportsRemaining {
            return "\(free)/\(FreeTier.maxPortraits) left"
        }
        return ""
    }
}

/// Gear rechtsboven (Figma Frame 27) — DSToolButton (E03.11): zelfde
/// glass-cirkel als de bottom-toolbar-tools. De actie stuurt de standaard
/// Settings-selector; functioneel zodra E15.1 de Settings-scene levert.
private struct GearButton: View {
    var body: some View {
        DSToolButton(Image(systemName: "gearshape.fill"), label: "Settings") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}
