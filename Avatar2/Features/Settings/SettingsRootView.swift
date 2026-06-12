// Settings-venster (E15.1) — 1-op-1 Figma 'App / Settings / Preferences'
// (4019:497): sub-nav links (320, "SETTINGS"-kop + 4 Navigation Buttons,
// alles op y76 vanaf de venstertop zodat de traffic lights inline vallen,
// zelfde maat als de shell-topbar), content rechts (header + Settings-
// secties). De credits/Upgrade-strip en de gear uit het frame horen bij
// het hóófdvenster-patroon dat elk App-frame draagt; de story scopet dit
// venster op "sub-nav + content-area" — bewust weggelaten (gedocumenteerd
// in de story).
//
// Pagina's 15.2–15.4 zijn hier bewust nog placeholders; elke story vult
// zijn eigen pagina in.

import AvatarUI
import SwiftUI

struct SettingsRootView: View {
    @State private var page: SettingsPage = .preferences

    var body: some View {
        HStack(spacing: 0) {
            subNav
                .frame(width: 320, alignment: .topLeading)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 1000, minHeight: 700)
        .background(DSColor.Background.app)
        .appliedAppearancePreference()
    }

    // MARK: sub-nav (Figma "sub-nav" 4019:753: navigation op x24,
    // items 272×20 met 16 gap onder de "Settings"-kop van 24 hoog)

    private var subNav: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SETTINGS")
                .dsTextStyle(.labelSmall)
                .tracking(1)
                .foregroundStyle(DSColor.Foreground.muted)
                .frame(height: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                ForEach(SettingsPage.allCases) { item in
                    SettingsNavButton(
                        title: item.title,
                        isActive: item == page
                    ) { page = item }
                }
            }
            .padding(.top, DSSpacing.gap4)
            Spacer()
        }
        .padding(.leading, DSSpacing.gap6 + DSSpacing.gap1)
        .padding(.top, 76)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .preferences:
            SettingsPreferencesPage()
        case .aiModels:
            SettingsPlaceholderPage(title: SettingsPage.aiModels.title)
        case .account:
            SettingsPlaceholderPage(title: SettingsPage.account.title)
        case .about:
            SettingsPlaceholderPage(title: SettingsPage.about.title)
        }
    }
}

/// Figma-component "Navigation Button" (272×20): actief = primary-tekst met
/// een 2pt action-balkje links; inactief = muted, hover → subtle.
private struct SettingsNavButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap2) {
                RoundedRectangle(cornerRadius: DSRadius.sm)
                    .fill(DSColor.Background.action)
                    .frame(width: DSBorderWidth.medium, height: 16)
                    .opacity(isActive ? 1 : 0)
                Text(title)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(
                        isActive
                            ? DSColor.Foreground.primary
                            : isHovering ? DSColor.Foreground.subtle : DSColor.Foreground.muted
                    )
            }
            .frame(width: 272, height: 20, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// Figma "Settings section" (608 breed, bg Card, r-2xl): H3-titel op 24
/// inzet, rijen op 24 inzet met 24 ondermarge.
struct SettingsSectionCard<Rows: View>: View {
    let title: String
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .dsTextStyle(.h3)
                .foregroundStyle(DSColor.Foreground.subtle)
            rows
                .padding(.top, DSSpacing.gap6)
        }
        .padding(DSSpacing.gap6)
        .frame(width: 608, alignment: .leading)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
    }
}

/// Figma-component "Setting Row" (560 breed): optioneel icoon (40×40,
/// bg neutral, r-md), titel (labelBase) + subtitel (bodySmall muted),
/// control rechts.
struct SettingsRow<Control: View>: View {
    var icon: String?
    let title: String
    let subtitle: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: DSSpacing.gap3) {
            if let icon {
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .fill(DSColor.Background.neutral)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DSColor.Foreground.subtle)
                    }
            }
            VStack(alignment: .leading, spacing: DSSpacing.gap0_5) {
                Text(title)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text(subtitle)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            Spacer(minLength: DSSpacing.gap4)
            control
        }
        .frame(width: 560, alignment: .leading)
    }
}

/// Placeholder tot de eigen story (15.2/15.3/15.4) de pagina invult.
struct SettingsPlaceholderPage: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .dsTextStyle(.h1)
                .foregroundStyle(DSColor.Foreground.primary)
            Spacer()
        }
        .padding(.top, 76)
        .padding(.leading, DSSpacing.gap6)
    }
}
