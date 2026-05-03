import SwiftUI

/// Non-destructive bottom toast. Three layouts driven by `toast.kind`:
///
/// - `.info` → Pro-only hard-limit notice. No CTA, just a dismiss.
/// - `.upgrade` → Free-tier soft gate. Single Upgrade pill on the right.
/// - `.aiTrialExhausted` → After the 3rd AI generation. Two CTAs: an
///   Upgrade pill (primary, brand) and a "Continue with basic" ghost
///   button (dismiss). Wider layout so neither button feels cramped.
struct ProUpsellToastView: View {
    let toast: ProToast
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    @State private var hovering = false

    private var brand: Color {
        Color(red: 0x9A / 255.0, green: 0xB7 / 255.0, blue: 1.0)
    }

    var body: some View {
        // The dual-CTA layout is wide enough that we stack vertically:
        // message on top, two buttons below. The single-CTA and info
        // variants stay horizontal so they read as compact chips.
        Group {
            switch toast.kind {
            case .aiTrialExhausted:
                dualCTALayout
            case .upgrade, .info:
                singleRowLayout
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovering ? 0.18 : 0.10))
        )
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 6)
        // Wider for the dual-CTA so the buttons can breathe.
        .frame(maxWidth: toast.kind == .aiTrialExhausted ? 560 : 460)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    // MARK: - Layouts

    /// Compact single-row layout used by `.info` and `.upgrade`. Matches
    /// the old behavior so existing call sites are visually unchanged.
    private var singleRowLayout: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.showsUpgrade ? "sparkles" : "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(toast.showsUpgrade ? brand : .secondary)

            Text(toast.message)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if toast.showsUpgrade {
                upgradePill
            } else {
                Spacer(minLength: 4)
            }

            dismissButton
        }
    }

    /// Stacked layout for the AI-trial-exhausted moment. Title gets
    /// extra weight (this IS the headline of the moment), body wraps,
    /// and the two CTAs sit side-by-side at the bottom.
    private var dualCTALayout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(brand)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.aiTrialExhaustedTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(toast.message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    upgradePill
                    Button(action: onDismiss) {
                        Text(Loc.aiTrialContinueBasicCTA)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.78))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().strokeBorder(Color.primary.opacity(0.18))
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    Spacer(minLength: 0)
                }
            }

            dismissButton
        }
    }

    // MARK: - Shared sub-elements

    /// Primary brand-colored Upgrade pill used by both layouts.
    private var upgradePill: some View {
        Button(action: onUpgrade) {
            Text(Loc.proQuotaUpgradeCTA)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(brand))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
