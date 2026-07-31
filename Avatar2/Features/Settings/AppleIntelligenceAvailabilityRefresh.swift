// Ververs Tier 2-beschikbaarheid wanneer de gebruiker terugkeert uit System Settings.

import AppKit
import SwiftUI

struct AppleIntelligenceAvailabilityRefresh: ViewModifier {
    @State private var refreshTick = 0
    let onRefresh: () -> Void

    func body(content: Content) -> some View {
        content
            .id(refreshTick)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refreshTick += 1
                onRefresh()
            }
            .onAppear(perform: onRefresh)
    }
}

extension View {
    /// Her-evalueert Apple Intelligence bij app-focus (bv. na AI aanzetten in macOS Settings).
    func refreshAppleIntelligenceAvailability(_ action: @escaping () -> Void = {}) -> some View {
        modifier(AppleIntelligenceAvailabilityRefresh(onRefresh: action))
    }
}
