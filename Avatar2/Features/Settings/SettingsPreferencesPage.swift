// Preferences-pagina (E15.1) — Figma 4019:762: H1-header "Preferences" op
// y76, daaronder (gap-8) de Appearance-sectie (Theme-rij met System/Light/
// Dark-dropdown).
//
// De Figma-frame toont hier ook een "Notifications"-toggle, maar die bleek
// inert (niets las settings2.updateNotifications) én een duplicaat van de
// werkende "Automatic updates"-toggle in About/Updates (live op Sparkle).
// Besluit Thierry (2026-06-23, cleanup-audit): rij verwijderd → update-
// voorkeuren leven uitsluitend in About, één bron van waarheid.

import AvatarUI
import SwiftUI

struct SettingsPreferencesPage: View {
    // E23: default = Dark (zie AppearancePreferenceModifier).
    @AppStorage(SettingsDefaults.appearanceKey)
    private var appearanceRaw: String = AppearancePreference.dark.rawValue

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .dark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Preferences")
                .dsTextStyle(.h1)
                .foregroundStyle(DSColor.Foreground.primary)

            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                SettingsSectionCard(title: "Appearance") {
                    SettingsRow(
                        title: "Theme",
                        subtitle: "Match the system, or pin Aaavatar to light or dark mode"
                    ) {
                        themeMenu
                    }
                }
            }
            .padding(.top, DSSpacing.gap8)
        }
        .padding(.top, ShellMetrics.settingsPageTopInset)
        .padding(.leading, DSSpacing.gap6)
        .padding(.trailing, DSSpacing.gap6)
    }

    // Figma-dropdown: pill (bg neutral, r-xl, 40 hoog) met label + chevron.
    private var themeMenu: some View {
        ThemeMenuPill(selection: $appearanceRaw, label: appearance.label)
    }
}

private struct ThemeMenuPill: View {
    @Binding var selection: String
    let label: String

    @State private var isHovering = false

    var body: some View {
        Menu {
            ForEach(AppearancePreference.allCases) { option in
                Button(option.label) { selection = option.rawValue }
            }
        } label: {
            HStack(spacing: DSSpacing.gap2) {
                Text(label)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: DSIconSize.sm, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.subtle)
            }
            .padding(.horizontal, DSSpacing.gap4)
            .frame(height: 40)
            .background(isHovering ? DSColor.Background.neutralStronger : DSColor.Background.neutral)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl))
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.xl))
            .onHover { isHovering = $0 }
            .dsMotion(DSMotion.micro, value: isHovering)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
