import AvatarKit
import AvatarUI
import SwiftUI

@main
struct Avatar2App: App {
    @State private var auth: AuthService
    @State private var onboarding: OnboardingModel
    @State private var entitlement: EntitlementModel

    init() {
        let auth = AuthService()
        _auth = State(initialValue: auth)
        _onboarding = State(initialValue: OnboardingModel(auth: auth))
        _entitlement = State(initialValue: EntitlementModel(auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboarding.isActive {
                    OnboardingFlow(model: onboarding)
                } else {
                    ContentPlaceholderView()
                        // Tijdelijke paywall-opstap tot E05/E06 echte
                        // gating-callsites leveren.
                        .overlay(alignment: .topTrailing) {
                            EntitlementStatusStrip(model: entitlement)
                                .padding(DSSpacing.gap4)
                        }
                }
            }
            .frame(minWidth: 480, minHeight: 320)
            .sheet(isPresented: Binding(
                get: { entitlement.isPaywallPresented },
                set: { entitlement.isPaywallPresented = $0 }
            )) {
                PaywallSheet(model: entitlement)
            }
            .overlay(alignment: .bottom) {
                if entitlement.isShowingOutOfCreditsToast {
                    OutOfCreditsToastView(model: entitlement)
                        .padding(.bottom, DSSpacing.gap6)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: entitlement.isShowingOutOfCreditsToast)
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
