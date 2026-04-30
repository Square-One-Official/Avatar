import SwiftUI

/// One semantic level for inline status feedback. Drives icon, fill, and ink
/// colors so every chip in the app reads the same way at a glance.
///
/// Pick by intent, not by feeling:
/// - `.info`     neutral notice / tip / passive upsell
/// - `.success`  positive confirmation, "saved", "done"
/// - `.warning`  recoverable: offline, retrying, soft cap, fallback used
/// - `.danger`   destructive or unrecoverable failure that needs attention
enum StatusSeverity {
    case info
    case success
    case warning
    case danger

    var icon: String {
        switch self {
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger:  return "xmark.octagon.fill"
        }
    }

    var fill: Color {
        switch self {
        case .info:    return .appInfo
        case .success: return .appSuccess
        case .warning: return .appWarning
        case .danger:  return .appDanger
        }
    }

    var ink: Color {
        switch self {
        case .info:    return .appInfoInk
        case .success: return .appSuccessInk
        case .warning: return .appWarningInk
        case .danger:  return .appDangerInk
        }
    }
}

/// Visual density. Defaults to `.solid` (filled capsule, prominent) for the
/// floating bottom chip used by the import flow. `.soft` uses a tinted fill
/// at lower opacity for inline contexts inside cards or sheets where a full
/// solid would dominate the layout.
enum StatusChipStyle {
    case solid
    case soft
}

/// Reusable inline status chip. One component for every soft-error / info /
/// success surface in the app, so all of them share padding, weight, radius,
/// and icon set.
struct StatusChip: View {
    let severity: StatusSeverity
    let message: String
    var style: StatusChipStyle = .solid
    /// Optional dismiss control. When provided, an `xmark` button appears at
    /// the trailing edge.
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: severity.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(severity.ink)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(severity.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(severity.ink.opacity(0.7))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(fillColor)
        )
        .overlay(
            Capsule().strokeBorder(severity.ink.opacity(style == .soft ? 0.18 : 0.0))
        )
    }

    private var fillColor: Color {
        switch style {
        case .solid: return severity.fill
        case .soft:  return severity.fill.opacity(0.30)
        }
    }
}
