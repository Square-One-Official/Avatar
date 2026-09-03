// Onboarding 2.0 — splash (Figma: Onboarding / Splash, 2611:39453). Licht
// moment conform het frame (E04.5): fluid-gradient-achtergrondafbeelding is
// een geregistreerde asset-placeholder (plan/ASSETS.md #1) op volledige
// venstergrootte; kop H1 in primary-static-black gecentreerd; Continue
// (lime, Default) onder gecentreerd op 64pt van de rand (gemeten uit het
// frame: knop-onderkant ±66 van 800). De licht→donker-overgang naar de
// e-mailstap loopt via de bestaande flow-fade.

import AvatarKit
import AvatarUI
import SwiftUI

struct OnboardingSplashView: View {
    let model: OnboardingModel
    var entitlement: EntitlementModel? = nil

    @State private var splashUrl: URL? = OnboardingSplashView.cachedSplashUrl

    private static var cachedSplashUrl: URL? = nil

    var body: some View {
        ZStack {
            if let url = splashUrl {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        SplashBackgroundPlaceholder()
                    }
                }
                .ignoresSafeArea()
            } else {
                SplashBackgroundPlaceholder()
            }
            Text("Welcome to Aaavatar. One look for every team portrait")
                .dsTextStyle(.h1)
                .foregroundStyle(DSColor.Foreground.primaryStaticBlack)
                .multilineTextAlignment(.center)
                .frame(width: 360)
        }
        .overlay(alignment: .bottom) {
            DSPrimaryButton("Continue") {
                model.advanceFromSplash()
            }
            .padding(.bottom, DSSpacing.gap8 + DSSpacing.gap8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadSplashUrl() }
    }

    private func loadSplashUrl() async {
        guard let backend = entitlement?.backend else { return }
        guard let url = (try? await backend.appConfig())?.splashBackgroundUrl else { return }
        OnboardingSplashView.cachedSplashUrl = url
        splashUrl = url
    }
}

/// ASSET-PLACEHOLDER (plan/ASSETS.md #1): de fluid blauwe gradient uit
/// Onboarding / Splash, hier benaderd met een gelaagde gradient op de
/// frameverhouding (1240×800, full-bleed). Thierry levert het definitieve
/// beeld in de assetbatch; markering rechtsonder hoort bij de werkregel
/// en verdwijnt met de echte asset.
private struct SplashBackgroundPlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.56, green: 0.80, blue: 0.96),
                    Color(red: 0.30, green: 0.66, blue: 0.92),
                    Color(red: 0.62, green: 0.84, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            EllipticalGradient(
                colors: [Color.white.opacity(0.85), .clear],
                center: UnitPoint(x: 0.7, y: 0.25),
                startRadiusFraction: 0,
                endRadiusFraction: 0.6
            )
            EllipticalGradient(
                colors: [Color(red: 0.16, green: 0.52, blue: 0.86).opacity(0.5), .clear],
                center: UnitPoint(x: 0.2, y: 0.8),
                startRadiusFraction: 0,
                endRadiusFraction: 0.7
            )
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottomTrailing) {
            Text("Asset placeholder · splash background")
                .dsTextStyle(.labelSmall)
                .foregroundStyle(DSColor.Foreground.primaryStaticBlack.opacity(DSOpacity.subtle))
                .padding(DSSpacing.gap2)
        }
    }
}
