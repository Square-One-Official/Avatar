// Op=op-toast (E08.3): DSToast met aflopende timer; tik opent de paywall.
// Verschijnt wanneer een feature-callsite EntitlementModel.handleOutOfCredits()
// aanroept (HTTP 402 / BackendError.noCredits).

import AvatarKit
import AvatarUI
import SwiftUI

struct OutOfCreditsToastView: View {
    let model: EntitlementModel

    var body: some View {
        // UXS-2: aftellen, timer-track en hover-pauze zitten in DSToast zelf; de
        // duur komt uit het model i.p.v. een eigen literal hier.
        DSToast(
            title: "You're out of credits",
            description: "Top up to keep editing — tap for options.",
            autoDismiss: EntitlementModel.infoToastDuration,
            onClose: { model.dismissOutOfCreditsToast() }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            model.requestUpgrade()
        }
    }
}
