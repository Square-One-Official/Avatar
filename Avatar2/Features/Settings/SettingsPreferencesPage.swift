// Preferences-pagina (E15.1) — Figma 4019:762: H1-header "Preferences" op
// y76, daaronder (gap-8) de Appearance-sectie (Theme-rij met System/Light/
// Dark-dropdown).
//
// De Figma-frame toont hier ook een "Notifications"-toggle, maar die bleek
// inert (niets las settings2.updateNotifications) én een duplicaat van de
// werkende "Automatic updates"-toggle in About/Updates (live op Sparkle).
// Besluit Thierry (2026-06-23, cleanup-audit): rij verwijderd → update-
// voorkeuren leven uitsluitend in About, één bron van waarheid.

import AvatarKit
import AvatarUI
import SwiftData
import SwiftUI

struct SettingsPreferencesPage: View {
    // E23: default = Dark (zie AppearancePreferenceModifier).
    @AppStorage(SettingsDefaults.appearanceKey)
    private var appearanceRaw: String = AppearancePreference.dark.rawValue

    // E13.2: migratie-import uit een Aaavatar 1-back-up.
    @Environment(\.modelContext) private var modelContext
    var entitlement: EntitlementModel? = nil
    @State private var importResult: String?

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

                // E13.2: migratiepad vanuit Aaavatar 1. Bewust hier en niet in
                // onboarding: de back-up-export moet eerst in v1 gebeuren, dus
                // dit is een bewuste handeling, geen eerste-startpad.
                SettingsSectionCard(title: "Migration") {
                    SettingsRow(
                        title: "Import from Aaavatar 1",
                        subtitle: importResult
                            ?? "Bring over your v1 library from a backup file (in Aaavatar 1: Settings → Export library)"
                    ) {
                        DSNeutralButton("Import backup…") { runImport() }
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

    private func runImport() {
        V1LibraryImporter.presentImportPanel(modelContext: modelContext) { result in
            switch result {
            case .success(let summary):
                importResult = summary.userMessage
            case .failure(let error):
                // Fouten óók via de subtitle: de settings-takeover heeft geen
                // eigen toast-slot en de app-brede fout-toast is voor cloud-acties.
                importResult = error.localizedDescription
            }
        }
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
