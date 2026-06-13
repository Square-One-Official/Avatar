import AvatarKit
import AvatarUI
import SwiftData
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
            // Punt 18a: minimum waarbij de layout nooit kapot kan (de
            // first-use-ring schaalt mee, 18b); default-opening hieronder.
            .frame(minWidth: 800, minHeight: 600)
            #if DEBUG
            .task {
                // Smoke-run-haak (--onboarding-step <stap>): forceer de flow
                // open op een stap voor de visuele verificatie.
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "--onboarding-step"),
                   args.indices.contains(i + 1) {
                    switch args[i + 1] {
                    case "privacy": onboarding.debugForce(step: .privacy)
                    case "email": onboarding.debugForce(step: .email)
                    case "otp": onboarding.debugForce(step: .otp)
                    case "splash": onboarding.debugForce(step: .splash)
                    default: break
                    }
                }
            }
            #endif
            // Frame-autosave: AppKit onthoudt de gebruikersmaat tussen
            // sessies; bij de eerste start geldt defaultSize.
            .background(WindowFrameAutosave(name: "Avatar2MainWindow"))
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
            // E15.1: persistente Theme-voorkeur (Preferences > Appearance).
            .appliedAppearancePreference()
        }
        // Eigen SwiftData-store voor de set (E05.4) — los van de v1-store.
        .modelContainer(for: Portrait2.self)
        // Bevinding 1 (E04.5): Figma kent geen aparte titelbalk — één zwart
        // vlak, traffic lights inline, geen venstertitel. hiddenTitleBar
        // geeft full-size content; de topbar reserveert zelf ruimte naast
        // de window-controls.
        .windowStyle(.hiddenTitleBar)
        // E15.1 + punt 14: Settings leeft BINNEN het hoofdvenster (view-
        // state in ShellView, gear toggelt) — geen aparte Settings-scene;
        // de frames vullen het hele app-venster.
        // Punt 18a: opent ruim boven de 1000×700-ontwerpmaat van de frames.
        .defaultSize(width: 1100, height: 760)
    }
}

/// Koppelt AppKit's frame-autosave aan het SwiftUI-venster: de door de
/// gebruiker gekozen maat/positie overleeft sessies (punt 18a); zonder
/// opgeslagen frame geldt defaultSize.
private struct WindowFrameAutosave: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.setFrameAutosaveName(name)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

