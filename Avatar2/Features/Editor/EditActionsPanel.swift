// Edit-paneel (E21.1) — kleur/technische acties. De beauty-acties zijn
// verhuisd naar het Face-paneel (FaceActionsPanel); framing/restore-body
// verhuizen later naar de canvas-cluster (E22.2) en Edit wordt dan live
// color-sliders (E22.3). Rijen via de gedeelde EditorActionList.

import AvatarKit
import AvatarUI
import SwiftUI

struct EditActionsPanel: View {
    /// Auto-crop & center draait op het geselecteerde portret (E06.5).
    let onAutomaticFraming: () -> Void
    /// E12.1: lokale Core Image-belichting (geen cloud/credits) — aan/uit.
    var onImproveLighting: () -> Void = {}
    /// E10.3: cloud-upscale ("Boost resolution", 1 credit) + busy-vlag.
    var onBoostResolution: () -> Void = {}
    var isBoosting: Bool = false
    /// E18.2: nog niet-gebouwde Pro-acties → contextuele gate.
    var onProFeature: () -> Void = {}
    var isPro: Bool = false
    /// E18.12: titels van lokale enhances die momenteel "aan" staan.
    var activeToggles: Set<String> = []

    private var sections: [EditorActionSection] {
        [
            EditorActionSection(title: "Position and alignment", actions: [
                EditorAction(title: "Auto-crop & center", handler: onAutomaticFraming),
                EditorAction(title: "Fix camera angle", handler: nil),
            ]),
            EditorActionSection(title: "Optimise", actions: [
                EditorAction(title: "Colorise", meter: .colorize, isCloud: true, handler: onProFeature),
                EditorAction(title: "Boost resolution", meter: .upscale, isCloud: true, handler: onBoostResolution),
            ]),
            EditorActionSection(title: "Adjust", actions: [
                EditorAction(
                    title: "Improve lighting", handler: onImproveLighting,
                    isOn: activeToggles.contains("Improve lighting")
                ),
                EditorAction(title: "Restore body", meter: .fillBody, isCloud: true, handler: onProFeature),
            ]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            if isBoosting {
                HStack(spacing: DSSpacing.gap2) {
                    ProgressView().controlSize(.small)
                    Text("Boosting resolution…")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                }
            }
            EditorActionList(sections: sections, isPro: isPro)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(isBoosting)
    }
}
