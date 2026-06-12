// Preferences-pagina (E15.1) — Figma 4019:762: H1-header "Preferences" op
// y76, daaronder (gap-8) twee Settings-secties met 4pt tussenruimte:
// Appearance (Theme-rij met System/Light/Dark-dropdown) en Notifications
// (icoonrij met DSToggle).
//
// Copy-afwijking, gedocumenteerd: de Notifications-rij in het frame draagt
// nog transcribe-app-copy ("Recording reminder … record your meeting" —
// zelfde template-bug als in figma-design-review.md). Vorm 1-op-1
// overgenomen; copy in de geest van Aaavatar: update-meldingen. De
// voorkeur is persistent (settings2.updateNotifications) en wordt door
// 15.4 (About/Updates, Sparkle) geconsumeerd.

import AvatarUI
import SwiftUI

struct SettingsPreferencesPage: View {
    @AppStorage(SettingsDefaults.appearanceKey)
    private var appearanceRaw: String = AppearancePreference.system.rawValue

    @AppStorage(SettingsDefaults.updateNotificationsKey)
    private var updateNotifications: Bool = true

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
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
                SettingsSectionCard(title: "Notifications") {
                    SettingsRow(
                        icon: "bell",
                        title: "Update notifications",
                        subtitle: "Let Aaavatar tell you when a new version is ready"
                    ) {
                        DSToggle(isOn: $updateNotifications)
                    }
                }
            }
            .padding(.top, DSSpacing.gap8)

            Spacer()
        }
        .padding(.top, 76)
        .padding(.leading, DSSpacing.gap6)
    }

    // Figma-dropdown: pill (bg neutral, r-xl, 40 hoog) met label + chevron.
    private var themeMenu: some View {
        Menu {
            ForEach(AppearancePreference.allCases) { option in
                Button(option.label) { appearanceRaw = option.rawValue }
            }
        } label: {
            HStack(spacing: DSSpacing.gap2) {
                Text(appearance.label)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.subtle)
            }
            .padding(.horizontal, DSSpacing.gap4)
            .frame(height: 40)
            .background(DSColor.Background.neutral)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
