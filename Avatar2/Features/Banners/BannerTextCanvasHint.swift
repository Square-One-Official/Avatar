// E37.13 — Minimale tekst-tool hint; bewerking gebeurt op het canvas (Freeform).

import AvatarUI
import SwiftUI

/// Vervangt het zware onderpaneel — styling zit in `BannerTextFloatingToolbar`.
struct BannerTextCanvasHint: View {
    var subtitle: String?

    var body: some View {
        DSEditPanel(title: "Text", subtitle: subtitle, maxContentHeight: 48) {
            Text("Tap the canvas to add a text box. Drag to move; use the floating toolbar to style.")
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
