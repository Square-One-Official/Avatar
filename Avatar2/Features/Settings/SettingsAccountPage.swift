// Account-pagina (E15.3) — geen eigen Figma-frame; geëxtrapoleerd in de
// 15.1-stijl (Setting Row-patroon), conform de werkregel. Gegevens via het
// EntitlementModel (e-mail uit AuthService, plan/credits/reset uit
// /v1/account). Geen sessie → uitnodiging om in te loggen.

import AvatarUI
import SwiftUI

struct SettingsAccountPage: View {
    @Bindable var entitlement: EntitlementModel
    /// E18.1: e-mail+OTP-login vanuit Account als je uitgelogd bent.
    @State private var showSignIn = false
    /// E15.7: bevestigingsdialoog vóór de definitieve account-verwijdering.
    @State private var showDeleteConfirm = false

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
                                DSPrimaryButton("Sign in", size: .small) { showSignIn = true }
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
                                    showDeleteConfirm = true
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
        .sheet(isPresented: $showSignIn) {
            SignInSheet(entitlement: entitlement)
        }
        // E15.7: zelfde confirm-patroon als portret-delete
        // (PortraitContextMenu) — destructieve actie nooit met één klik.
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await entitlement.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, cancels any subscription and removes your remaining credits. This can't be undone. Portraits stored on this Mac stay on this Mac.")
        }
    }

    private var creditsSubtitle: String {
        // 14.7 (audit B8): alleen een toekomstige refill-datum tonen — een
        // stale `current_period_end` uit het verleden valt terug op de
        // periodloze copy.
        if let reset = entitlement.upcomingMonthlyResetAt {
            return "Refills on \(reset.formatted(date: .abbreviated, time: .omitted))"
        }
        return entitlement.isProActive
            ? "Refills monthly with your plan"
            : "Credits come with a Pro plan"
    }
}
