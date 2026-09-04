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
    @Bindable var presentation: UIPresentationStore
    @State private var importResult: String?
    // E13.7: directe import van de v1-store op deze Mac.
    @State private var localImportResult: String?
    @State private var isImportingLocal = false

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
                // Open menu boven de Migration-kaart eronder tekenen; de
                // zIndex van de knop zelf reikt niet buiten deze kaart.
                .zIndex(presentation.settingsThemeMenuOpen ? 1 : 0)

                // E13.2 + E13.7: migratiepad vanuit Aaavatar 1. Bewust hier en
                // niet in onboarding: het is een bewuste handeling, en op
                // macOS 15+ vraagt de directe import eenmalig systeemtoegang —
                // dat hoort bij een klik, niet bij de eerste start.
                SettingsSectionCard(title: "Migration") {
                    VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                        SettingsRow(
                            title: "Import from Aaavatar 1 on this Mac",
                            subtitle: localImportResult
                                ?? "Finds the library the previous version left on this Mac and brings over your portraits, originals included"
                        ) {
                            DSNeutralButton(isImportingLocal ? "Importing…" : "Import from this Mac") {
                                runLocalImport()
                            }
                            .disabled(isImportingLocal)
                        }
                        SettingsRow(
                            title: "Import from a backup file",
                            subtitle: importResult
                                ?? "Bring over your v1 library from a backup made in Aaavatar 1 (Settings → Export library)"
                        ) {
                            DSNeutralButton("Import backup…") { runImport() }
                        }
                    }
                }
            }
            .padding(.top, DSSpacing.gap8)
            .dsDropdownDismissOverlay(isPresented: $presentation.settingsThemeMenuOpen)
        }
        .padding(.top, ShellMetrics.settingsPageTopInset)
        .padding(.leading, DSSpacing.gap6)
        .padding(.trailing, DSSpacing.gap6)
    }

    // Figma-dropdown: pill (bg neutral, r-xl, 40 hoog) met label + chevron.
    private var themeMenu: some View {
        ThemeMenuPill(
            selection: $appearanceRaw,
            label: appearance.label,
            isPresented: $presentation.settingsThemeMenuOpen
        )
    }

    private func runLocalImport() {
        guard !isImportingLocal else { return }
        isImportingLocal = true
        localImportResult = "Looking for your Aaavatar 1 library…"
        Task { @MainActor in
            let result = await V1LibraryImporter.importFromLocalStore(modelContext: modelContext)
            isImportingLocal = false
            switch result {
            case .success(let summary):
                localImportResult = summary.userMessage
            case .failure(let error):
                localImportResult = error.localizedDescription
            }
        }
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
    @Binding var isPresented: Bool

    @State private var isHovering = false

    var body: some View {
        DSDropdownButton(isPresented: $isPresented, anchorHeight: 40, minWidth: 160) {
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
        } menu: {
            ForEach(AppearancePreference.allCases) { option in
                DSMenuRow(
                    option.label,
                    icon: option.icon,
                    shortcut: option.rawValue == selection ? "✓" : nil
                ) {
                    selection = option.rawValue
                    isPresented = false
                }
            }
        }
        .fixedSize()
    }
}
