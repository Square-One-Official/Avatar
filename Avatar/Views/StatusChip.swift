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
/// Inline action embedded in a chip. The button reads as a quiet sibling to
/// the message — same ink color, slightly stronger weight, capsule
/// underlay so the affordance is unmistakable but the chip itself stays
/// compact.
struct StatusChipAction {
    let label: String
    let run: () -> Void
}

struct StatusChip: View {
    let severity: StatusSeverity
    let message: String
    var style: StatusChipStyle = .solid
    /// Optional dismiss control. When provided, an `xmark` button appears at
    /// the trailing edge.
    var onDismiss: (() -> Void)?
    /// Optional inline CTA (e.g. "Try again") rendered before the dismiss
    /// button. Use sparingly — only when the chip describes a state the
    /// user can act on right there.
    var action: StatusChipAction?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: severity.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(severity.ink)

            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(severity.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let action {
                Button(action: action.run) {
                    Text(action.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(severity.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(severity.ink.opacity(0.16))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle(pressedScale: 0.97))
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(severity.ink.opacity(0.7))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.dismiss)
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

extension ErrorBanner {
    /// Maps the optional banner action enum onto a `StatusChip` CTA.
    @MainActor
    func statusChipAction(appState: AppState) -> StatusChipAction? {
        switch action {
        case .openPrivacySettings:
            return StatusChipAction(label: Loc.openPrivacySettingsCTA) {
                appState.openPrivacySettings()
            }
        case nil:
            return nil
        }
    }
}
