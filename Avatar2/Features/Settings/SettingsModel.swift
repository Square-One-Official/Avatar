// Settings 2.0 (E15) — paginamodel + voorkeuren.
//
// Figma: sectie "Settings" (4017:10181), frames 'App / Settings /
// Preferences' (4019:497) en 'App / Settings / AI & Models' (4019:823).
// De sub-nav kent vier items; het frame toont nog "Permissions" uit de
// template-app — het bord (E15.1–15.4) definieert onze vier pagina's:
// Preferences, AI & Models, Account, About. Gedocumenteerde afwijking.

import SwiftUI

/// De Settings-pagina's. Volgorde = sub-nav-volgorde. Billing & Invoices
/// (2026-09-02) is de vijfde: geen Figma-frame, gebouwd naar het referentie-
/// ontwerp dat Thierry aandroeg — zie SettingsBillingPage.
enum SettingsPage: String, CaseIterable, Identifiable {
    case preferences
    case aiModels
    case account
    case billing
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferences: return "Preferences"
        case .aiModels: return "AI & Models"
        case .account: return "Account"
        case .billing: return "Billing & Invoices"
        case .about: return "About"
        }
    }
}

/// Appearance-voorkeur (Preferences > Appearance > Theme).
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum SettingsDefaults {
    static let appearanceKey = "settings2.appearance"
}

/// Past de persistente Theme-voorkeur toe op een view (root of sheet). Bewust
/// internal, niet private (E01.14): als window-root-modifier zit de type-naam
/// in SwiftUI's frame-autosave-sleutel; een private type levert een per-build
/// instabiele "(unknown context at $adres)"-signatuur op → wees-sleutels en
/// een venster dat bij twee launch-condities tegelijk kan inklappen.
struct AppearancePreferenceModifier: ViewModifier {
    // E23: default = Dark (de huidige merk-look). Light/System zijn opt-in via
    // Settings > Appearance. Vóór E23 stond dit op .system terwijl de app
    // dark-only was; nu de tokens theme-bewust zijn houdt .dark de look gelijk.
    @AppStorage(SettingsDefaults.appearanceKey)
    private var appearanceRaw: String = AppearancePreference.dark.rawValue
    @State private var systemAppearance = SystemAppearanceObserver()

    private var preference: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .dark
    }

    private var resolvedScheme: ColorScheme {
        preference.resolvedColorScheme(systemIsDark: systemAppearance.isDark)
    }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(resolvedScheme)
            .background(
                WindowBackgroundPainter(colorScheme: resolvedScheme)
                    .frame(width: 0, height: 0)
            )
    }
}

extension View {
    func appliedAppearancePreference() -> some View {
        modifier(AppearancePreferenceModifier())
    }
}
