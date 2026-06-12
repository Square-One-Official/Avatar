import AvatarKit
import AvatarUI
import SwiftUI

@main
struct Avatar2App: App {
    @State private var auth: AuthService
    @State private var onboarding: OnboardingModel

    init() {
        let auth = AuthService()
        _auth = State(initialValue: auth)
        _onboarding = State(initialValue: OnboardingModel(auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboarding.isActive {
                    OnboardingFlow(model: onboarding)
                } else {
                    ContentPlaceholderView()
                }
            }
            .frame(minWidth: 480, minHeight: 320)
        }
    }
}

/// Tijdelijke placeholder tot de main-shell (E05) landt.
struct ContentPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.square.badge.camera")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Aaavatar 2.0")
                .font(.title2.weight(.semibold))
            Text("Scaffold — E01.1")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Engines: \(CutoutEngineKind.allCases.map(\.rawValue).joined(separator: " · "))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
