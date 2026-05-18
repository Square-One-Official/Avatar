import SwiftUI

/// Non-destructive bottom toast. Two layouts driven by `toast.kind`:
///
/// - `.info` → Pro-only hard-limit notice. No CTA, just a dismiss.
/// - `.upgrade` → Free-tier soft gate. Single Upgrade pill on the right.
struct ProUpsellToastView: View {
    let toast: ProToast
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    @State private var hovering = false

    private var brand: Color { .appBrand }

    var body: some View {
        singleRowLayout
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
            .frame(maxWidth: 460)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }

    // MARK: - Layout

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
