// Muted-but-clickable chrome for cloud features when Local only is on.
// Clicks still fire so PrivacyGate can show Turn on Cloud.

import SwiftUI

enum CloudFeatureChrome {
    @MainActor
    static var isLocalOnly: Bool { !PrivacyPreferences2.shared.allowsThirdPartyCloud }

    static let mutedOpacity: Double = 0.55
}

extension View {
    /// Dim cloud-only controls without using `.disabled` (that would eat clicks).
    func cloudFeatureMuted(_ muted: Bool) -> some View {
        opacity(muted ? CloudFeatureChrome.mutedOpacity : 1)
    }

    @MainActor
    func cloudFeatureMuted() -> some View {
        cloudFeatureMuted(CloudFeatureChrome.isLocalOnly)
    }
}
