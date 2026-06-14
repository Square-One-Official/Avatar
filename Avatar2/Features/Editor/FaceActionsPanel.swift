// Face-paneel (E21.1) — beauty-acties, gesplitst van het Edit-paneel. Lokale
// One-click retouch (aan/uit) + de generatieve Pro-acties (Whiten teeth,
// Apply make-up, Reduce wrinkles, elk 4 credits). Rijen via de gedeelde
// EditorActionList. Restore body hoort hier NIET (→ canvas-cluster, E22.2).

import AvatarKit
import AvatarUI
import SwiftUI

struct FaceActionsPanel: View {
    /// E12.1: lokale Core Image-retouch (geen cloud/credits) — aan/uit.
    var onRetouch: () -> Void = {}
    /// E18.2: nog niet-gebouwde Pro-acties → contextuele gate.
    var onProFeature: () -> Void = {}
    var isPro: Bool = false
    /// E18.12: titels van lokale enhances die momenteel "aan" staan.
    var activeToggles: Set<String> = []

    private var sections: [EditorActionSection] {
        [
            EditorActionSection(title: "Retouch", actions: [
                EditorAction(
                    title: "One click retouch", handler: onRetouch,
                    isOn: activeToggles.contains("One click retouch")
                ),
            ]),
            EditorActionSection(title: "Beauty", actions: [
                EditorAction(title: "Whiten teeth", meter: .generativeStandard, isCloud: true, handler: onProFeature),
                EditorAction(title: "Apply make-up", meter: .generativeStandard, isCloud: true, handler: onProFeature),
                EditorAction(title: "Reduce wrinkles", meter: .generativeStandard, isCloud: true, handler: onProFeature),
            ]),
        ]
    }

    var body: some View {
        EditorActionList(sections: sections, isPro: isPro)
    }
}
