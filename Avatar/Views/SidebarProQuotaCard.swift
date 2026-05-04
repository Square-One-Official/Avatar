import SwiftUI

/// Subtle bottom-of-sidebar nudge for free users: a single 6-dot strip
/// (AI cluster on the left, basic cluster on the right, separated by a
/// gap), a "X of Y left" headline with the tier breakdown beneath, and a
/// green `Pro` badge in the upsell CTA. Reads from `proEntitlement`
/// (server-tracked, survives delete-then-reimport) and routes a tap to
/// the paywall. Hidden once the user is Pro. Sits below `SidebarUpdateCard`
/// so a pending update relaunch always reads as the higher-priority CTA.
///
/// **Why one row of dots.** The previous two-row layout doubled the chrome
/// for what users perceive as one resource — "6 generations, two flavors."
/// **Why uniform fill across tiers.** An earlier version used brand-blue
/// for AI and a muted neutral for basic; the saturation gap made a fresh
/// strip read as "3 used, 3 left" even when nothing had been consumed.
/// Same hue everywhere, with a 10pt gap signalling the cluster split.
struct SidebarProQuotaCard: View {
    @Environment(AppState.self) private var appState
    @State private var hovering = false

    private var aiCapacity: Int { FreeTier.freeMagicCutoutAllowance }
    private var aiRemaining: Int { max(0, min(aiCapacity, appState.proEntitlement.freeCutoutsRemaining)) }

    private var basicCapacity: Int { max(0, FreeTier.maxPortraits - FreeTier.freeMagicCutoutAllowance) }
    private var basicRemaining: Int { max(0, min(basicCapacity, appState.proEntitlement.freeBasicImportsRemaining)) }

    private var totalCapacity: Int { aiCapacity + basicCapacity }
    private var totalRemaining: Int { aiRemaining + basicRemaining }

    private var brand: Color { .appBrand }

    var body: some View {
        Button {
            appState.showProUpgradeSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Single 6-dot strip. Both clusters use the same hue at full
                // strength so a fresh user reads "6 available," not "3 used,
                // 3 still here." A 10pt gap (vs. 5pt internal spacing) is
                // the only tier signal — the breakdown line below names them.
                HStack(spacing: 10) {
                    QuotaDots(remaining: aiRemaining, capacity: aiCapacity, fillColor: brand)
                    QuotaDots(remaining: basicRemaining, capacity: basicCapacity, fillColor: brand)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.proQuotaTotalRemaining(remaining: totalRemaining, total: totalCapacity))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(Loc.proQuotaTierBreakdown(ai: aiRemaining, basic: basicRemaining))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(Loc.proQuotaUpgradeBeforeBadge)
                    InlineProBadge()
                    Text(Loc.proQuotaUpgradeAfterBadge)
                }
                .font(.system(size: 11))
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
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: aiRemaining)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: basicRemaining)
        .help(Loc.proQuotaTooltip)
    }
}

/// Inline green pill that calls out the Pro tier inside the upsell line.
/// Distinct from the louder all-caps `ProBadge` used as a feature marker
/// elsewhere — this one reads as a word inside a sentence, not a label.
private struct InlineProBadge: View {
    var body: some View {
        Text("Pro")
            .font(.system(size: 10, weight: .semibold))
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
