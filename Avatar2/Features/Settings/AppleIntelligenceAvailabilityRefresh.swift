// Ververs Tier 2-beschikbaarheid wanneer de gebruiker terugkeert uit System Settings.
//
// Bewust GEEN `.id(tick)` op de content: dat her-identificeerde bij elke
// app-activatie de hele ShellView-subtree en wiste alle @State (o.a. de
// editor-camera: 40% zoom → terug op fit na een venster-wissel). De status is
// observable (`AppleIntelligenceAvailabilityStore`), dus een refresh hertekent
// precies de views die 'm lezen.

import AppKit
import SwiftUI

struct AppleIntelligenceAvailabilityRefresh: ViewModifier {
    let onRefresh: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refresh()
            }
            .onAppear(perform: refresh)
    }

    private func refresh() {
        AppleIntelligenceAvailability.refresh()
        onRefresh()
    }
}

extension View {
    /// Her-evalueert Apple Intelligence bij app-focus (bv. na AI aanzetten in macOS Settings).
    func refreshAppleIntelligenceAvailability(_ action: @escaping () -> Void = {}) -> some View {
        modifier(AppleIntelligenceAvailabilityRefresh(onRefresh: action))
    }
}
