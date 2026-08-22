import SwiftUI

/// Subtle bottom-of-sidebar nudge for free users: a single 3-dot strip,
/// a "X of 3 left" headline, and a green `Pro` badge in the upsell CTA.
/// Reads from `proEntitlement.freeImportsRemaining` (server-tracked,
/// survives delete-then-reimport) and routes a tap to the paywall.
/// Hidden once the user is Pro. Sits below `SidebarUpdateCard` so a
/// pending update relaunch always reads as the higher-priority CTA.
struct SidebarProQuotaCard: View {
    @Environment(AppState.self) private var appState
    @Environment(PrivacyPreferences.self) private var privacyPrefs
    @State private var hovering = false

    private var capacity: Int { FreeTier.maxPortraits }
    private var remaining: Int {
        max(0, min(capacity, appState.proEntitlement.freeImportsRemaining))
    }

    private var brand: Color { .appBrand }
    private var localOnly: Bool { !privacyPrefs.cloudAllowed }

    var body: some View {
        Button {
            appState.showProUpgradeSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                QuotaDots(remaining: remaining, capacity: capacity, fillColor: brand)

                Text(Loc.proQuotaTotalRemaining(remaining: remaining, total: capacity))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(localOnly
                         ? Loc.proQuotaUpgradeBeforeBadgeLocalOnly
                         : Loc.proQuotaUpgradeBeforeBadge)
                    InlineProBadge()
                    Text(localOnly
                         ? Loc.proQuotaUpgradeAfterBadgeLocalOnly
                         : Loc.proQuotaUpgradeAfterBadge)
                }
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                // `appSurface` keeps the card on the same warmth axis as the
                // rest of the chrome (the previous `.ultraThinMaterial` was
                // picking up enough canvas tint to read blue). The white
                // overlay lifts it one notch above appSurface so it still
                // reads as elevated against neighbouring panels.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(hovering ? 0.12 : 0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.98))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .onHover { hovering = $0 }
        .motionAwareAnimation(.easeOut(duration: 0.15), value: hovering)
        .motionAwareAnimation(.spring(response: 0.32, dampingFraction: 0.78), value: remaining)
        .help(localOnly ? Loc.proQuotaTooltipLocalOnly : Loc.proQuotaTooltip)
    }
}

/// Inline green pill that calls out the Pro tier inside the upsell line.
/// Distinct from the louder all-caps `ProBadge` used as a feature marker
/// elsewhere — this one reads as a word inside a sentence, not a label.
private struct InlineProBadge: View {
    var body: some View {
        Text("Pro")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.appSuccessInk)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.appSuccess)
            )
    }
}

/// Horizontal dot strip filled left-to-right by `remaining`. Solid fill =
/// available, hollow ring = consumed. Splitting state across two visual
/// variables (shape + presence-of-fill) instead of one (opacity) keeps a
/// fresh user from misreading the strip as half-used.
private struct QuotaDots: View {
    let remaining: Int
    let capacity: Int
    let fillColor: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<capacity, id: \.self) { idx in
                if idx < remaining {
                    Circle()
                        .fill(fillColor)
                        .frame(width: 6, height: 6)
                } else {
                    Circle()
                        .strokeBorder(fillColor.opacity(0.30), lineWidth: 1)
                        .frame(width: 6, height: 6)
                }
            }
        }
    }
}
