// Settings 2.0 (E15) — paginamodel + voorkeuren.
//
// Figma: sectie "Settings" (4017:10181), frames 'App / Settings /
// Preferences' (4019:497) en 'App / Settings / AI & Models' (4019:823).
// De sub-nav kent vier items; het frame toont nog "Permissions" uit de
// template-app — het bord (E15.1–15.4) definieert onze vier pagina's:
// Preferences, AI & Models, Account, About. Gedocumenteerde afwijking.

import SwiftUI

/// De vier Settings-pagina's. Volgorde = sub-nav-volgorde.
enum SettingsPage: String, CaseIterable, Identifiable {
    case preferences
    case aiModels
    case account
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferences: return "Preferences"
        case .aiModels: return "AI & Models"
        case .account: return "Account"
        case .about: return "About"
        }
    }
}

/// Appearance-voorkeur (Preferences > Appearance > Theme). System is de
/// Figma-default. De DS-tokens zijn vooralsnog dark-only, dus het directe
/// visuele effect is beperkt tot systeemcontrols; de voorkeur is wél
/// persistent en wordt op de root toegepast zodat een licht thema later
/// alleen tokenwerk is.
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
    static let updateNotificationsKey = "settings2.updateNotifications"
}

/// Past de persistente Theme-voorkeur toe op een scene-root. System = nil
/// (volg het systeem — identiek aan het gedrag vóór E15.1). Bewust internal,
/// niet private (E01.14): als window-root-modifier zit de type-naam in
/// SwiftUI's frame-autosave-sleutel; een private type levert een per-build
/// instabiele "(unknown context at $adres)"-signatuur op → wees-sleutels en
/// een venster dat bij twee launch-condities tegelijk kan inklappen.
struct AppearancePreferenceModifier: ViewModifier {
    // E23: default = Dark (de huidige merk-look). Light/System zijn opt-in via
    // Settings > Appearance. Vóór E23 stond dit op .system terwijl de app
    // dark-only was; nu de tokens theme-bewust zijn houdt .dark de look gelijk.
    @AppStorage(SettingsDefaults.appearanceKey)
    private var appearanceRaw: String = AppearancePreference.dark.rawValue

    func body(content: Content) -> some View {
        content.preferredColorScheme(
            (AppearancePreference(rawValue: appearanceRaw) ?? .dark).colorScheme
        )
    }
}

extension View {
    func appliedAppearancePreference() -> some View {
        modifier(AppearancePreferenceModifier())
    }
}
