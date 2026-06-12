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
