import SwiftUI

/// Subtle bottom-of-sidebar nudge for free users: shows how many lifetime
/// imports are left in the free trial and routes a tap to the paywall.
/// Reads directly from `proEntitlement.freeImportsUsed` (server-tracked,
/// survives delete-then-reimport) — NOT the current library count.
/// Hidden once the user is Pro. Sits below `SidebarUpdateCard` so a
/// pending update relaunch always reads as the higher-priority CTA.
struct SidebarProQuotaCard: View {
    @Environment(AppState.self) private var appState
    @State private var hovering = false
    @State private var pressed = false

    private var capacity: Int { FreeTier.maxPortraits }
    private var used: Int { min(capacity, appState.proEntitlement.freeImportsUsed) }
    private var remaining: Int { max(0, capacity - used) }
    private var atLimit: Bool { remaining == 0 }

    /// Same brand periwinkle the import drop zone uses, so the upsell reads
    /// as a continuation of the import surface rather than a new motif.
    private var brand: Color {
        Color(red: 0x9A / 255.0, green: 0xB7 / 255.0, blue: 1.0)
    }

    var body: some View {
        Button {
            appState.showProUpgradeSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                QuotaDots(used: used, capacity: capacity, brand: brand, atLimit: atLimit)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.proQuotaTitle(remaining: remaining, total: capacity))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(atLimit ? brand : .primary.opacity(0.85))
                        .lineLimit(1)
                    Text(Loc.proQuotaSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
        .help(Loc.proQuotaTooltip)
    }
}

/// Five horizontal dots, filled left-to-right by `used`. At-limit state
/// switches the empty dots to brand-tinted to reinforce the CTA without
/// changing layout.
private struct QuotaDots: View {
    let used: Int
    let capacity: Int
    let brand: Color
    let atLimit: Bool

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<capacity, id: \.self) { idx in
                Circle()
                    .fill(fill(for: idx))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func fill(for idx: Int) -> Color {
        if idx < used {
            return atLimit ? brand : Color.primary.opacity(0.55)
        }
        return atLimit ? brand.opacity(0.35) : Color.primary.opacity(0.14)
    }
}
