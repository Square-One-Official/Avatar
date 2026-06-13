// Account-pagina (E15.3) — geen eigen Figma-frame; geëxtrapoleerd in de
// 15.1-stijl (Setting Row-patroon), conform de werkregel. Gegevens via het
// EntitlementModel (e-mail uit AuthService, plan/credits/reset uit
// /v1/account). Geen sessie → uitnodiging om in te loggen.

import AvatarUI
import SwiftUI

struct SettingsAccountPage: View {
    @Bindable var entitlement: EntitlementModel

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
                            Text(entitlement.accountEmail ?? "—")
                                .dsTextStyle(.labelBase)
                                .foregroundStyle(DSColor.Foreground.muted)
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

                if entitlement.isSignedIn {
                    SettingsSectionCard(title: "Session") {
                        SettingsRow(
                            title: "Sign out",
                            subtitle: "You can sign back in any time with a code"
                        ) {
                            DSNeutralButton("Sign out") {
                                entitlement.signOutAccount()
                            }
                        }
                    }
                }
            }
            .padding(.top, DSSpacing.gap8)

            Spacer()
        }
        .padding(.top, 76)
        .padding(.leading, DSSpacing.gap6)
        .padding(.trailing, DSSpacing.gap6)
        .task { await entitlement.refresh() }
    }

    private var creditsSubtitle: String {
        if let reset = entitlement.monthlyResetAt {
            return "Refills on \(reset.formatted(date: .abbreviated, time: .omitted))"
        }
        return entitlement.isProActive
            ? "Refills monthly with your plan"
            : "Credits come with a Pro plan"
    }
}
