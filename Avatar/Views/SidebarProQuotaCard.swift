import SwiftUI

/// Subtle bottom-of-sidebar nudge for free users: a single 6-dot strip
/// split into an AI tier (brand-blue) and a basic tier (muted), with a
/// description line and a green `Pro` badge in the upsell CTA. Reads
/// from `proEntitlement` (server-tracked, survives delete-then-reimport)
/// and routes a tap to the paywall. Hidden once the user is Pro.
/// Sits below `SidebarUpdateCard` so a pending update relaunch always
/// reads as the higher-priority CTA.
///
/// **Why one row.** The previous two-row layout doubled the chrome for
/// what users perceive as one resource — "6 generations, two flavors."
/// One strip with a colour drop between clusters keeps the tier
/// distinction without the visual weight of two stacked progress bars.
struct SidebarProQuotaCard: View {
    @Environment(AppState.self) private var appState
    @State private var hovering = false

    private var aiCapacity: Int { FreeTier.freeMagicCutoutAllowance }
    private var aiRemaining: Int { max(0, min(aiCapacity, appState.proEntitlement.freeCutoutsRemaining)) }

    private var basicCapacity: Int { max(0, FreeTier.maxPortraits - FreeTier.freeMagicCutoutAllowance) }
    private var basicRemaining: Int { max(0, min(basicCapacity, appState.proEntitlement.freeBasicImportsRemaining)) }

    private var aiExhausted: Bool { aiRemaining == 0 }

    private var brand: Color { .appBrand }

    var body: some View {
        Button {
            appState.showProUpgradeSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Single 6-dot strip — AI cluster on the left (brand blue),
                // basic cluster on the right (muted neutral). A small gap
                // between clusters reads as "premium, then fallback" without
                // needing a second row.
                HStack(spacing: 10) {
                    QuotaDots(
                        remaining: aiRemaining,
                        capacity: aiCapacity,
                        fillColor: brand,
                        emptyOpacity: aiExhausted ? 0.35 : 0.20
                    )
                    QuotaDots(
                        remaining: basicRemaining,
                        capacity: basicCapacity,
                        fillColor: Color.primary.opacity(0.55),
                        emptyOpacity: 0.14
                    )
                }

                Text(Loc.proQuotaCombinedRow(
                    aiRemaining: aiRemaining,
                    basicRemaining: basicRemaining
                ))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.85))
                .lineLimit(1)

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
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: aiExhausted)
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

/// Horizontal dot strip filled left-to-right by `remaining`. Filled =
/// generations available, dim = consumed — matches the "X left" verbal
/// cue users see in the description line.
private struct QuotaDots: View {
    let remaining: Int
    let capacity: Int
    let fillColor: Color
    let emptyOpacity: Double

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<capacity, id: \.self) { idx in
                Circle()
                    .fill(idx < remaining ? fillColor : fillColor.opacity(emptyOpacity))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
