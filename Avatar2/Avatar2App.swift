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
                    ShellView(entitlement: entitlement)
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

