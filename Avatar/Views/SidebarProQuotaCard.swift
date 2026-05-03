import SwiftUI

/// Subtle bottom-of-sidebar nudge for free users: shows the two-tier
/// reverse trial — AI generations on top, basic generations below — and
/// routes a tap to the paywall. Reads from `proEntitlement` (server-
/// tracked, survives delete-then-reimport). Hidden once the user is Pro.
/// Sits below `SidebarUpdateCard` so a pending update relaunch always
/// reads as the higher-priority CTA.
///
/// **Why two rows.** A single 6-dot strip would visually merge the two
/// phases of free into one homogenous resource. Splitting it makes the
/// model legible: "AI is the premium thing, basic is the fallback." The
/// drop in fill weight between rows mirrors the drop in quality.
struct SidebarProQuotaCard: View {
    @Environment(AppState.self) private var appState
    @State private var hovering = false

    private var aiCapacity: Int { FreeTier.freeMagicCutoutAllowance }
    private var aiRemaining: Int { max(0, min(aiCapacity, appState.proEntitlement.freeCutoutsRemaining)) }
    private var aiUsed: Int { aiCapacity - aiRemaining }

    private var basicCapacity: Int { max(0, FreeTier.maxPortraits - FreeTier.freeMagicCutoutAllowance) }
    private var basicRemaining: Int { appState.proEntitlement.freeBasicImportsRemaining }
    private var basicUsed: Int { basicCapacity - basicRemaining }

    private var atLimit: Bool { aiRemaining == 0 && basicRemaining == 0 }
    private var aiExhausted: Bool { aiRemaining == 0 }

    private var brand: Color { .appBrand }

    var body: some View {
        Button {
            appState.showProUpgradeSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // AI row — premium tier, brand-colored when filled.
                QuotaRow(
                    label: Loc.proQuotaAIRow(remaining: aiRemaining, total: aiCapacity),
                    used: aiUsed,
                    capacity: aiCapacity,
                    fillColor: brand,
                    emptyOpacity: aiExhausted ? 0.35 : 0.18,
                    isPremium: true,
                    isExhausted: aiExhausted
                )

                // Basic row — neutral tone signals the quality drop. Renders
                // dimmed once the AI row is fully spent (this is the user's
                // "now we're in the fallback" moment).
                QuotaRow(
                    label: Loc.proQuotaBasicRow(remaining: basicRemaining, total: basicCapacity),
                    used: basicUsed,
                    capacity: basicCapacity,
                    fillColor: Color.primary.opacity(0.55),
                    emptyOpacity: 0.12,
                    isPremium: false,
                    isExhausted: basicRemaining == 0
                )
                .opacity(aiExhausted ? 1.0 : 0.78)

                // CTA strip — only escalates copy when fully out.
                Text(atLimit ? Loc.proQuotaUpgradeCTA : Loc.proQuotaSubtitle)
                    .font(.system(size: 11, weight: atLimit ? .semibold : .regular))
                    .foregroundStyle(atLimit ? brand : Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(hovering ? 0.14 : 0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.98))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        // Spring on the visual transition between AI-active and AI-exhausted
        // states — matches the rest of the app's spring vocabulary
        // (`PillSegmentedControl`).
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: aiExhausted)
        .help(Loc.proQuotaTooltip)
    }
}

/// One label + dot strip. Used twice in `SidebarProQuotaCard` to show
/// the AI tier and the basic tier as visually distinct rows.
private struct QuotaRow: View {
    let label: String
    let used: Int
    let capacity: Int
    let fillColor: Color
    let emptyOpacity: Double
    let isPremium: Bool
    let isExhausted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            QuotaDots(used: used, capacity: capacity, fillColor: fillColor, emptyOpacity: emptyOpacity)
            Text(label)
                .font(.system(size: 11, weight: isPremium ? .semibold : .regular))
                .foregroundStyle(isExhausted ? fillColor : Color.primary.opacity(0.82))
                .lineLimit(1)
        }
    }
}

/// Horizontal dot strip, filled left-to-right by `used`. Capacity drives
/// the dot count, so this works for both the 3-dot AI row and the 3-dot
/// basic row (and any other future capacity).
private struct QuotaDots: View {
    let used: Int
    let capacity: Int
    let fillColor: Color
    let emptyOpacity: Double

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<capacity, id: \.self) { idx in
                Circle()
                    .fill(idx < used ? fillColor : fillColor.opacity(emptyOpacity))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
