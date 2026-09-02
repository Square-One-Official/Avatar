// Account-pagina (E15.3) — geen eigen Figma-frame; geëxtrapoleerd in de
// 15.1-stijl (Setting Row-patroon), conform de werkregel. Gegevens via het
// EntitlementModel (e-mail uit AuthService). Geen sessie → uitnodiging om in
// te loggen.
//
// 15.8 (2026-09-02, besluit Thierry): Account = identiteit (e-mail, sessie,
// verwijderen); alles wat geld is — plan, credits, facturen — leeft op
// Billing & Invoices (SettingsBillingPage).

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
        .padding(.top, ShellMetrics.settingsPageTopInset)
        .padding(.leading, DSSpacing.gap6)
        .padding(.trailing, DSSpacing.gap6)
        .task { await entitlement.refresh() }
    }
}
