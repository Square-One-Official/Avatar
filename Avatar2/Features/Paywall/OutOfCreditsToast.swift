// Op=op-toast (E08.3): DSToast met aflopende timer; tik opent de paywall.
// Verschijnt wanneer een feature-callsite EntitlementModel.handleOutOfCredits()
// aanroept (HTTP 402 / BackendError.noCredits).

import AvatarKit
import AvatarUI
import SwiftUI

struct OutOfCreditsToastView: View {
    let model: EntitlementModel

    private static let duration: TimeInterval = 6
    // Audit-cleanup: één lineair geanimeerde waarde (1→0) i.p.v. een
    // TimelineView die de hele toast 30×/sec herbouwt voor de balk.
    @State private var progress: Double = 1

    var body: some View {
        DSToast(
            title: "You're out of credits",
            description: "Top up to keep editing — tap for options.",
            progress: progress,
            onClose: { model.dismissOutOfCreditsToast() }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            model.requestUpgrade()
        }
        .onAppear {
            withAnimation(.linear(duration: Self.duration)) { progress = 0 }
        }
        .task {
            try? await Task.sleep(for: .seconds(Self.duration))
            model.dismissOutOfCreditsToast()
        }
    }
}
