// Account-pagina (E15.3) — geen eigen Figma-frame; geëxtrapoleerd in de
// 15.1-stijl (Setting Row-patroon), conform de werkregel. Gegevens via het
// EntitlementModel (e-mail uit AuthService, plan/credits/reset uit
// /v1/account). Geen sessie → uitnodiging om in te loggen.

import AvatarUI
import SwiftUI

struct SettingsAccountPage: View {
    @Bindable var entitlement: EntitlementModel
    @Bindable var model: ShellModel
    /// E18.1: e-mail+OTP-login vanuit Account als je uitgelogd bent.
    /// E53.7: sheet leeft op Avatar2App (entitlement.presentSignIn).
    /// E53.7: delete-account confirm op FloatingOverlayHost via ShellModel.

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Account")
                .dsTextStyle(.h1)
                .foregroundStyle(DSColor.Foreground.primary)

            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                SettingsSectionCard(title: "Account") {
                    VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                        SettingsRow(
                            title: "Email",
                            subtitle: entitlement.isSignedIn
                                ? "The address linked to your account"
                                : "You're not signed in"
                        ) {
                            if entitlement.isSignedIn {
                                Text(entitlement.accountEmail ?? "—")
                                    .dsTextStyle(.labelBase)
                                    .foregroundStyle(DSColor.Foreground.muted)
                            } else {
                                // E18.8: sign-in zit nu in de Email-rij i.p.v.
                                // een los Session-blok.
                                DSPrimaryButton("Sign in", size: .small) { entitlement.presentSignIn() }
                            }
                        }
                        SettingsRow(
                            title: "Plan",
                            subtitle: entitlement.isProActive
                                ? "Manage billing in the Stripe portal"
                                : "Upgrade for unlimited images and credits"
                        ) {
                            if entitlement.isProActive {
                                DSNeutralButton("Manage subscription") {
                                    entitlement.openManageSubscription()
                                }
                            } else {
                                HStack(spacing: DSSpacing.gap2) {
                                    Text(entitlement.planLabel)
                                        .dsTextStyle(.labelBase)
                                        .foregroundStyle(DSColor.Foreground.muted)
                                    DSChip("Upgrade", type: .brand) {
                                        entitlement.requestUpgrade()
                                    }
                                }
                            }
                        }
                    }
                }

                SettingsSectionCard(title: "Credits") {
                    SettingsRow(
                        title: "Balance",
                        subtitle: creditsSubtitle
                    ) {
                        Text("\(entitlement.creditsRemaining)")
                            .dsTextStyle(.labelBase)
                            .foregroundStyle(DSColor.Foreground.primary)
                    }
                }

                // E18.8: Session-blok alleen nog voor Sign out (ingelogd);
                // sign-in zit nu in de Email-rij hierboven.
                if entitlement.isSignedIn {
                    SettingsSectionCard(title: "Session") {
                        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                            SettingsRow(
                                title: "Sign out",
                                subtitle: "You can sign back in any time with a code"
                            ) {
                                DSNeutralButton("Sign out") {
                                    entitlement.signOutAccount()
                                }
                            }
                            // E15.7 (audit C7): GDPR art. 17 — definitieve
                            // verwijdering, achter een bevestigingsdialoog
                            // (zelfde patroon als portret-delete).
                            SettingsRow(
                                title: "Delete account",
                                subtitle: "Permanently removes your account, subscription and credits"
                            ) {
                                DSNeutralButton("Delete account…") {
                                    model.presentation.confirm = .deleteAccount
                                }
                                .disabled(entitlement.isDeletingAccount)
                            }
                        }
                    }
                }
            }
            .padding(.top, DSSpacing.gap8)
        }
        .padding(.top, 76)
        .padding(.leading, DSSpacing.gap6)
        .padding(.trailing, DSSpacing.gap6)
        .task { await entitlement.refresh() }
    }

    private var creditsSubtitle: String {
        // 14.7 (audit B8): alleen een toekomstige refill-datum tonen — een
        // stale `current_period_end` uit het verleden valt terug op de
        // periodloze copy.
        if let reset = entitlement.upcomingMonthlyResetAt {
            return "Refills on \(reset.formatted(date: .abbreviated, time: .omitted))"
        }
        if entitlement.isProActive {
            return "Refills monthly with your plan"
        }
        // UXS-11 (UX11): "Credits come with a Pro plan" stond pal naast een
        // saldo van 34 op een Starter-account — de copy sprak het getal
        // ernaast tegen. Een Starter kán credits hebben (top-up of restant),
        // dus zeg dat dan ook.
        return entitlement.creditsRemaining > 0
            ? "Top-up credits — you can use these on any plan"
            : "Credits come with a Pro plan"
    }
}
