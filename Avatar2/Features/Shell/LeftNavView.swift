// PoC (left-nav): Granola-stijl linker navigatie. Eigen losstaande kaart
// (zelfde taal als SidebarView/DSEditPanel: bg Card, concentrische radius,
// ShellView geeft de marge). Top-level secties (Studio/Portraits), onderin de
// upgrade-banner + quota en een klikbare gebruikersrij waarvan het menu
// Settings en "Manage backgrounds" opent. Net-nieuw scherm (geen Figma-bron) —
// gebouwd op de bestaande DS-tokens in de geest van het hoofddesign.

import AvatarUI
import SwiftUI

struct LeftNavView: View {
    let model: ShellModel
    let entitlement: EntitlementModel

    /// Breedte in lijn met de set-sidebar (248), iets smaller — Granola-maat.
    static let width: CGFloat = 232
    static let edgeInset: CGFloat = ShellMetrics.windowEdgeInset

    @State private var showUserMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, DSSpacing.gap3)
                .padding(.top, DSSpacing.gap3)
                .padding(.bottom, DSSpacing.gap4)

            VStack(spacing: DSSpacing.gap1) {
                LeftNavRow(
                    icon: Image(systemName: "wand.and.stars"),
                    title: "Studio",
                    isSelected: model.section == .studio && !model.isShowingSettings
                ) {
                    model.showSection(.studio)
                }
                LeftNavRow(
                    icon: Image(systemName: "square.grid.2x2"),
                    title: "Portraits",
                    isSelected: model.section == .portraits && !model.isShowingSettings
                ) {
                    model.showSection(.portraits)
                }
            }
            .padding(.horizontal, DSSpacing.gap2)

            Spacer(minLength: DSSpacing.gap4)

            upgradeBanner
                .padding(.horizontal, DSSpacing.gap2)
                .padding(.bottom, DSSpacing.gap2)

            Divider()
                .overlay(DSColor.Foreground.divider)
                .padding(.horizontal, DSSpacing.gap3)

            userRow
                .padding(DSSpacing.gap2)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            DSColor.Background.card,
            in: .rect(
                cornerRadius: DSRadius.concentric(inset: Self.edgeInset),
                style: .continuous
            )
        )
        .task { await entitlement.refresh() }
    }

    // MARK: - Header (app-mark + inklap-chevron)

    private var header: some View {
        HStack(spacing: DSSpacing.gap2) {
            RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                .fill(DSColor.Background.action)
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "person.crop.square.filled.and.at.rectangle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DSColor.Action.onAction)
                )
            Text("Aaavatar")
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)
            Spacer(minLength: 0)
            Button { model.toggleLeftNav() } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(DSColor.Foreground.muted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide sidebar")
        }
    }

    // MARK: - Upgrade-banner + quota (Granola-stijl)

    private var upgradeBanner: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            HStack(spacing: DSSpacing.gap2) {
                Text(entitlement.isProActive ? "Pro plan" : "Starter plan")
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.primary)
                Spacer(minLength: 0)
                if !entitlement.isProActive {
                    DSChip("Upgrade", type: .brand) { entitlement.requestUpgrade() }
                }
            }
            if !entitlement.quotaSummary.isEmpty {
                Text("\(entitlement.quotaSummary) images")
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }
        }
        .padding(DSSpacing.gap3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.Background.inset, in: RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))
    }

    // MARK: - Gebruikersrij + menu

    private var userRow: some View {
        Button { showUserMenu.toggle() } label: {
            HStack(spacing: DSSpacing.gap2) {
                Circle()
                    .fill(DSColor.Background.neutralStronger)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(userInitial)
                            .dsTextStyle(.labelSmall)
                            .foregroundStyle(DSColor.Foreground.primary)
                    )
                Text(userDisplayName)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .dsHoverHighlight(cornerRadius: DSRadius.lg)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showUserMenu, arrowEdge: .top) {
            userMenu
        }
    }

    private var userMenu: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            menuRow("Settings", icon: "gearshape") {
                showUserMenu = false
                model.isShowingSettings = true
            }
            menuRow("Manage backgrounds", icon: "photo.on.rectangle") {
                showUserMenu = false
                model.isShowingManageBackgrounds = true
            }
            if entitlement.isSignedIn {
                Divider().padding(.vertical, 2)
                menuRow("Sign out", icon: "rectangle.portrait.and.arrow.right", destructive: true) {
                    showUserMenu = false
                    entitlement.signOutAccount()
                }
            }
        }
        .padding(DSSpacing.gap1)
        .frame(width: 220)
    }

    private func menuRow(_ title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap2) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium)).frame(width: 18)
                Text(title).dsTextStyle(.labelBase)
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? DSColor.Signal.error : DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .dsHoverHighlight(cornerRadius: DSRadius.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Afgeleide gebruikerslabels

    private var userDisplayName: String {
        guard let email = entitlement.accountEmail, !email.isEmpty else { return "Sign in" }
        return String(email.prefix(while: { $0 != "@" }))
    }

    private var userInitial: String {
        let name = userDisplayName
        return name == "Sign in" ? "?" : String(name.prefix(1)).uppercased()
    }
}

/// Eén navigatierij in de left-nav (icoon + label + selectie-highlight). Lokaal
/// in FEAT/Shell — volgt de DSSidebarRow-taal maar is icoon-gericht i.p.v.
/// avatar-gericht.
private struct LeftNavRow: View {
    let icon: Image
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap2) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(title)
                    .dsTextStyle(.labelBase)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? DSColor.Foreground.primary : DSColor.Foreground.subtle)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .dsMotion(DSMotion.micro, value: hovering)
    }

    private var rowBackground: Color {
        if isSelected { return DSColor.Background.neutralStronger }
        if hovering { return DSColor.Background.neutral }
        return .clear
    }
}
