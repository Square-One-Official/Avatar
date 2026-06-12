// Main shell-wortel (E05). 5.1 levert alleen de first-use-empty-state;
// import (5.2), isolating-animatie (5.3), sidebar (5.4) en de header (5.5)
// haken hier later in.

import AvatarUI
import SwiftUI

struct ShellView: View {
    let entitlement: EntitlementModel

    var body: some View {
        FirstUseEmptyState {
            // E05.2: bestandskiezer → PipelineRouter. Tot die story is de
            // knop een bewuste no-op.
        }
        // Tijdelijke paywall-opstap (E08.3) tot E06 echte gating levert.
        .overlay(alignment: .topTrailing) {
            EntitlementStatusStrip(model: entitlement)
                .padding(DSSpacing.gap4)
        }
    }
}
