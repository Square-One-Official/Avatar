// Op=op-toast (E08.3): DSToast met aflopende timer; tik opent de paywall.
// Verschijnt wanneer een feature-callsite EntitlementModel.handleOutOfCredits()
// aanroept (HTTP 402 / BackendError.noCredits).

import AvatarKit
import AvatarUI
import SwiftUI

struct OutOfCreditsToastView: View {
    let model: EntitlementModel

    private static let duration: TimeInterval = 6
    @State private var appearedAt = Date.now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = context.date.timeIntervalSince(appearedAt)
            DSToast(
                title: "You're out of credits",
                description: "Top up to keep editing — tap for options.",
                progress: max(0, 1 - elapsed / Self.duration),
                onClose: { model.dismissOutOfCreditsToast() }
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.requestUpgrade()
        }
        .task {
            try? await Task.sleep(for: .seconds(Self.duration))
            model.dismissOutOfCreditsToast()
        }
    }
}

/// Tijdelijke opstap tot de main-shell (E05) en het editor-framework (E06)
/// echte gating-callsites leveren: toont de entitlementstate (DSQuotaBadge)
/// en opent de paywall via dezelfde requestUpgrade()-route als DSGated.
struct EntitlementStatusStrip: View {
    let model: EntitlementModel

    var body: some View {
        HStack(spacing: DSSpacing.gap2) {
            // Quota pas ná de eerste cutout (E05.1): geen druk vóór waarde.
            if model.hasCompletedFirstCutout {
                if model.isProActive {
                    DSQuotaBadge("\(model.creditsRemaining) credits")
                } else if let free = model.freeImportsRemaining {
                    DSQuotaBadge("\(free) of \(FreeTier.maxPortraits) free imports left")
                }
            }
            DSNeutralButton("Upgrade to Pro", size: .small) {
                model.requestUpgrade()
            }
        }
        .task { await model.refresh() }
    }
}
