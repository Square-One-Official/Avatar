// About-pagina (E15.4) — geen eigen Figma-frame; geëxtrapoleerd in de
// 15.1-stijl (Setting Row-patroon) conform de werkregel. Functionele
// referentie: v1 UpdatesSection (versie-rij, auto-check-toggle,
// check-knop) + appcast.
//
// Sparkle is in het Avatar2-target nog niet gelinkt (project.yml =
// INFRA-grens; story E01.11 staat op het bord). Tot die landt is de
// check-knop disabled met de versie-rij en links volledig functioneel;
// de auto-check-voorkeur persisteert alvast onder settings2.* zodat de
// Sparkle-port hem direct kan consumeren.

import AvatarUI
import SwiftUI

struct SettingsAboutPage: View {
    @AppStorage("settings2.autoUpdateCheck")
    private var autoUpdateCheck: Bool = true

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("About")
                .dsTextStyle(.h1)
                .foregroundStyle(DSColor.Foreground.primary)

            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                SettingsSectionCard(title: "Updates") {
                    VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                        SettingsRow(
                            title: "Version",
                            subtitle: "Aaavatar 2"
                        ) {
                            Text(versionLabel)
                                .dsTextStyle(.labelBase)
                                .foregroundStyle(DSColor.Foreground.muted)
                        }
                        SettingsRow(
                            title: "Automatic updates",
                            subtitle: "Check for new versions in the background"
                        ) {
                            DSToggle(isOn: $autoUpdateCheck)
                        }
                        SettingsRow(
                            title: "Check for updates",
                            subtitle: "Updates arrive via the Aaavatar update channel"
                        ) {
                            // Sparkle-koppeling volgt in E01.11 (INFRA);
                            // tot die tijd bewust disabled, geen dode actie.
                            DSNeutralButton("Check now") {}
                                .disabled(true)
                        }
                    }
                }
                SettingsSectionCard(title: "Links") {
                    VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                        linkRow(
                            title: "Website",
                            subtitle: "aaavatar.nl",
                            url: "https://aaavatar.nl"
                        )
                        linkRow(
                            title: "Privacy policy",
                            subtitle: "How Aaavatar handles your photos",
                            url: "https://aaavatar.nl/privacy"
                        )
                    }
                }
            }
            .padding(.top, DSSpacing.gap8)

            Spacer()
        }
        .padding(.top, 76)
        .padding(.leading, DSSpacing.gap6)
        .padding(.trailing, DSSpacing.gap6)
    }

    private func linkRow(title: String, subtitle: String, url: String) -> some View {
        SettingsRow(title: title, subtitle: subtitle) {
            DSIconButton(Image(systemName: "arrow.up.right")) {
                if let target = URL(string: url) {
                    NSWorkspace.shared.open(target)
                }
            }
            .accessibilityLabel("Open \(title)")
        }
    }
}
