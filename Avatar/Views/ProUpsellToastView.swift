import SwiftUI

/// Non-destructive bottom toast. Two flavors:
/// - Free user trips a soft Pro gate → shows Upgrade CTA pill.
/// - Pro user trips a hard technical limit (e.g. batch cap) → no CTA,
///   just the message and a dismiss affordance.
struct ProUpsellToastView: View {
    let toast: ProToast
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    @State private var hovering = false

    private var brand: Color {
        Color(red: 0x9A / 255.0, green: 0xB7 / 255.0, blue: 1.0)
    }

    var body: some View {
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
            } else {
                Spacer(minLength: 4)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
        .frame(maxWidth: 460)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
