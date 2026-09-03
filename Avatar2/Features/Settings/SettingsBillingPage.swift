// Billing & Invoices (Settings, 2026-09-02) — geen eigen Figma-frame;
// geëxtrapoleerd in de 15.1-stijl (SettingsSectionCard) naar het referentie-
// ontwerp dat Thierry aandroeg: H1 met "Manage subscription" rechts, een
// Plan-kaart (naam + kortingsbadge, lijstprijs rechts, "Next payment"-strook
// op inset) en een Invoices-kaart met één inset-rij per factuur (icoon,
// datum + omschrijving, bedrag, status-badge, download). Data via
// `GET /v1/billing` (EntitlementModel.billing); schrijfacties blijven in de
// Stripe Customer Portal.

import AvatarKit
import AvatarUI
import SwiftUI

struct SettingsBillingPage: View {
    @Bindable var entitlement: EntitlementModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                SettingsSectionCard(title: "Plan") { planContent }
                SettingsSectionCard(title: "Credits") { creditsContent }
                SettingsSectionCard(title: "Invoices") { invoicesContent }
            }
            .padding(.top, DSSpacing.gap8)
        }
        .padding(.top, ShellMetrics.settingsPageTopInset)
        .padding(.horizontal, DSSpacing.gap6)
        // Herlaadt bij elke (her)opening én bij een sessiewissel terwijl de
        // pagina open staat (sign-in vanuit de kaart).
        .task(id: entitlement.isSignedIn) {
            // Saldo (account) én facturen (billing) vers — je komt hier vaak
            // terug uit Stripe Checkout/Portal.
            async let account: Void = entitlement.refresh()
            async let billing: Void = entitlement.refreshBilling()
            _ = await (account, billing)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DSSpacing.gap4) {
            Text("Billing & Invoices")
                .dsTextStyle(.h1)
                .foregroundStyle(DSColor.Foreground.primary)
            Spacer(minLength: DSSpacing.gap4)
            headerAction
        }
        .frame(maxWidth: SettingsLayout.sectionWidth, alignment: .leading)
    }

    @ViewBuilder
    private var headerAction: some View {
        if !entitlement.isSignedIn {
            DSPrimaryButton("Sign in") { entitlement.presentSignIn() }
        } else if entitlement.isProActive {
            DSNeutralButton("Manage subscription") { entitlement.openManageSubscription() }
        } else {
            DSPrimaryButton("Upgrade to Pro") { entitlement.requestUpgrade() }
        }
    }

    // MARK: - Plan

    @ViewBuilder
    private var planContent: some View {
        if !entitlement.isSignedIn {
            SettingsRow(
                title: "Sign in to see your plan",
                subtitle: "Your subscription and invoices are linked to your account"
            ) {
                DSPrimaryButton("Sign in", size: .small) { entitlement.presentSignIn() }
            }
        } else if let billing = entitlement.billing {
            if let plan = billing.plan {
                PlanSummary(plan: plan)
            } else {
                noSubscriptionSummary
            }
        } else if let error = entitlement.billingError {
            SettingsRow(title: "Couldn't load your plan", subtitle: error) {
                DSNeutralButton("Try again", size: .small) {
                    Task { await entitlement.refreshBilling() }
                }
            }
        } else {
            loadingRow("Loading your plan…")
        }
    }

    /// Ingelogd zonder Stripe-abonnement: Starter, of een Pro-comp zonder
    /// facturatie (dev-/pro-allowlist).
    @ViewBuilder
    private var noSubscriptionSummary: some View {
        HStack(alignment: .top, spacing: DSSpacing.gap4) {
            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                Text(entitlement.planLabel)
                    .dsTextStyle(.h4)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text(entitlement.isProActive ? "Complimentary access" : "Free plan")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            Spacer(minLength: DSSpacing.gap4)
            if !entitlement.isProActive {
                DSChip("Upgrade", type: .brand) { entitlement.requestUpgrade() }
            }
        }
    }

    // MARK: - Credits

    /// Saldo + bijkopen. Packs zijn server-side Pro-only (403 pro_required),
    /// dus Starter ziet de ladder niet maar een Upgrade-chip.
    @ViewBuilder
    private var creditsContent: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            SettingsRow(
                title: "Balance",
                subtitle: entitlement.isSignedIn
                    ? BillingCopy.creditsSubtitle(
                        upcomingReset: entitlement.upcomingMonthlyResetAt,
                        isPro: entitlement.isProActive,
                        credits: entitlement.creditsRemaining
                    )
                    : "Sign in to see your balance"
            ) {
                if entitlement.isSignedIn {
                    Text("\(entitlement.creditsRemaining)")
                        .dsTextStyle(.h4)
                        .foregroundStyle(DSColor.Foreground.primary)
                        .monospacedDigit()
                }
            }
            if !entitlement.isSignedIn {
                EmptyView()
            } else if entitlement.isProActive {
                addCredits
            } else {
                SettingsRow(
                    title: "Add credits",
                    subtitle: "Credit packs are available on Pro — never expire, stack with your monthly credits"
                ) {
                    DSChip("Upgrade", type: .brand) { entitlement.requestUpgrade() }
                }
            }
        }
    }

    /// Patroon: bedrag-tegels met Save-badge, daaronder een samenvatting met
    /// het totaal en één Pay-knop (Stripe Checkout in de browser). Geen
    /// per-credit-tarieven — je kiest een hoeveelheid, niet een prijs.
    private var addCredits: some View {
        let pack = entitlement.selectedPack
        let total = BillingCopy.packPrice(pack)
        return VStack(alignment: .leading, spacing: DSSpacing.gap3) {
            VStack(alignment: .leading, spacing: DSSpacing.gap0_5) {
                Text("Add credits")
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text("Choose an amount. Credits never expire and stack with your monthly credits.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            HStack(spacing: DSSpacing.gap2) {
                ForEach(CreditPack.displayOrder) { candidate in
                    CreditPackTile(pack: candidate, isSelected: candidate == pack) {
                        entitlement.selectedPack = candidate
                    }
                }
            }
            VStack(spacing: 0) {
                HStack {
                    Text("\(pack.credits) credits")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.primary)
                    Spacer(minLength: DSSpacing.gap4)
                    Text(total)
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.subtle)
                }
                .padding(.bottom, DSSpacing.gap3)
                Rectangle()
                    .fill(DSColor.Foreground.divider)
                    .frame(height: DSBorderWidth.thin)
                HStack {
                    Text("Total due")
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.primary)
                    Spacer(minLength: DSSpacing.gap4)
                    Text(total)
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.primary)
                }
                .padding(.top, DSSpacing.gap3)
            }
            .padding(DSSpacing.gap4)
            .background(DSColor.Background.inset, in: RoundedRectangle(cornerRadius: DSRadius.lg))
            HStack(alignment: .center, spacing: DSSpacing.gap3) {
                Text("You'll complete payment on Stripe in your browser.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                Spacer(minLength: DSSpacing.gap4)
                if entitlement.isCheckoutBusy {
                    DSProgressView().controlSize(.small)
                }
                DSPrimaryButton("Pay \(total) now") {
                    Task { await entitlement.startTopup() }
                }
                .disabled(entitlement.isCheckoutBusy)
            }
            if let error = entitlement.checkoutError {
                Text(error)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.destructive)
            }
        }
    }

    // MARK: - Invoices

    @ViewBuilder
    private var invoicesContent: some View {
        if !entitlement.isSignedIn {
            emptyRow("Sign in to see your invoices")
        } else if let billing = entitlement.billing {
            if billing.invoices.isEmpty {
                emptyRow("No invoices yet")
            } else {
                VStack(spacing: DSSpacing.gap2) {
                    ForEach(billing.invoices) { invoice in
                        InvoiceRow(invoice: invoice) { entitlement.openInvoice(invoice) }
                    }
                }
            }
        } else if entitlement.billingError != nil {
            emptyRow("Invoices unavailable right now")
        } else {
            loadingRow("Loading invoices…")
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .dsTextStyle(.bodySmall)
            .foregroundStyle(DSColor.Foreground.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: DSSpacing.gap2) {
            DSProgressView()
                .controlSize(.small)
            Text(text)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Plan summary

/// Naam + kortingsbadge links, lijstprijs + cadans rechts; daaronder de
/// "Next payment"-strook op inset.
private struct PlanSummary: View {
    let plan: BillingPayload.Plan

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            HStack(alignment: .top, spacing: DSSpacing.gap4) {
                VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                    HStack(spacing: DSSpacing.gap2) {
                        Text(plan.name)
                            .dsTextStyle(.h4)
                            .foregroundStyle(DSColor.Foreground.primary)
                        if let discount = BillingCopy.discountLabel(plan.discount, fallbackCurrency: plan.currency) {
                            BillingStatusBadge(label: discount, tone: .success)
                        }
                    }
                    Text(BillingCopy.renewalCaption(plan))
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                }
                Spacer(minLength: DSSpacing.gap4)
                VStack(alignment: .trailing, spacing: DSSpacing.gap1) {
                    Text(BillingCopy.price(plan.amount, currency: plan.currency))
                        .dsTextStyle(.h4)
                        .foregroundStyle(DSColor.Foreground.primary)
                    Text(BillingCopy.cadenceCaption(plan))
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                }
            }
            if let next = plan.nextPayment {
                HStack(spacing: DSSpacing.gap2) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: DSIconSize.base, weight: .medium))
                        .foregroundStyle(DSColor.Foreground.subtle)
                    (
                        Text("Next payment ")
                        + Text(BillingCopy.price(next.amount, currency: next.currency)).fontWeight(.semibold)
                        + Text(" on \(BillingCopy.date(next.at))")
                    )
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.primary)
                }
                .padding(DSSpacing.gap3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DSColor.Background.inset, in: RoundedRectangle(cornerRadius: DSRadius.lg))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Invoice row

private struct InvoiceRow: View {
    let invoice: BillingPayload.Invoice
    let open: () -> Void

    var body: some View {
        let status = BillingCopy.invoiceStatus(invoice.status)
        HStack(spacing: DSSpacing.gap3) {
            RoundedRectangle(cornerRadius: DSRadius.md)
                .fill(DSColor.Background.neutral)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "doc.text")
                        .font(.system(size: DSIconSize.lg, weight: .medium))
                        .foregroundStyle(DSColor.Foreground.subtle)
                }
            VStack(alignment: .leading, spacing: DSSpacing.gap0_5) {
                Text(BillingCopy.invoiceDate(invoice))
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text(invoice.description)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: DSSpacing.gap4)
            Text(BillingCopy.price(invoice.amount, currency: invoice.currency))
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)
            BillingStatusBadge(label: status.label, tone: status.tone)
            DSIconButton(
                Image(systemName: "arrow.down.to.line"),
                label: "Download invoice",
                size: .small,
                action: open
            )
            .disabled(EntitlementModel.invoiceURL(for: invoice) == nil)
        }
        .padding(DSSpacing.gap3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.Background.inset, in: RoundedRectangle(cornerRadius: DSRadius.lg))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(BillingCopy.invoiceDate(invoice)), \(invoice.description), \(BillingCopy.price(invoice.amount, currency: invoice.currency)), \(status.label)")
    }
}

// MARK: - Credit pack tile

/// Bedrag-tegel: hoeveelheid + optionele Save-badge, geselecteerd = rand in
/// brand-inkt (zelfde selectie-idioom als de paywall-rijen).
private struct CreditPackTile: View {
    let pack: CreditPack
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                Text("\(pack.credits) credits")
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                if let savings = BillingCopy.savingsLabel(pack) {
                    DSBadge(savings)
                } else {
                    // Zelfde hoogte als een badge zodat de drie tegels gelijk blijven.
                    Text(" ")
                        .dsTextStyle(.labelSmall)
                        .padding(.vertical, DSSpacing.gap1)
                }
            }
            .padding(DSSpacing.gap3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsSelectableRowHoverSurface(
                isSelected: isSelected,
                idleBackground: DSColor.Background.inset
            )
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.lg).strokeBorder(
                    isSelected ? DSColor.Action.primaryForeground : DSColor.Foreground.divider,
                    lineWidth: DSBorderWidth.thin
                )
            }
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.lg))
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
        .accessibilityLabel("\(pack.credits) credits, \(BillingCopy.packPrice(pack))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Status badge

/// DSBadge-maten (r-md, px gap-2, py gap-1, labelSmall) op de DS-signaal-
/// kleuren. Lokaal: AvatarUI's DSBadge kent alleen neutral/brand; een
/// Signal-variant is DS-werk (E03) zodra een tweede feature 'm nodig heeft.
private struct BillingStatusBadge: View {
    let label: String
    let tone: BillingCopy.Tone

    var body: some View {
        Text(label)
            .dsTextStyle(.labelSmall)
            .lineLimit(1)
            .foregroundStyle(ink)
            .padding(.horizontal, DSSpacing.gap2)
            .padding(.vertical, DSSpacing.gap1)
            .background(background, in: RoundedRectangle(cornerRadius: DSRadius.md))
    }

    private var background: Color {
        switch tone {
        case .success: return DSColor.Signal.success
        case .warning: return DSColor.Signal.warning
        case .error: return DSColor.Signal.error
        case .neutral: return DSColor.Background.neutral
        }
    }

    private var ink: Color {
        switch tone {
        case .success: return DSColor.Action.onAction
        case .warning, .error: return DSColor.Foreground.primaryStaticBlack
        case .neutral: return DSColor.Foreground.primary
        }
    }
}
