// Figma "Components" → Badge (Style=Fill, Type=Default/Brand).
// Padding px gap-2 / py gap-1, gap gap-1, radius r-md, label UI/Labels/Small,
// optionele 16pt leading icon. In de dark "Stories"-frames bestaan alleen
// fill-badges (neutral en brand); outline volgt zodra een story die nodig
// heeft. De chip is dezelfde component, klikbaar (hover Medium .75,
// pressed Subtle .5 — identiek aan Button).

import SwiftUI

public struct DSBadge: View {
    public enum BadgeType: Sendable {
        case neutral
        case brand

        var background: Color {
            self == .brand ? DSColor.Background.action : DSColor.Background.neutral
        }
        var foreground: Color {
            self == .brand ? DSColor.Action.onAction : DSColor.Foreground.primary
        }
    }

    private let label: String
    private let icon: Image?
    private let type: BadgeType

    public init(_ label: String, icon: Image? = nil, type: BadgeType = .neutral) {
        self.label = label
        self.icon = icon
        self.type = type
    }

    public var body: some View {
        HStack(spacing: DSSpacing.gap1) {
            if let icon {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            }
            Text(label)
                .dsTextStyle(.labelSmall)
                .lineLimit(1)
        }
        .foregroundStyle(type.foreground)
        .padding(.horizontal, DSSpacing.gap2)
        .padding(.vertical, DSSpacing.gap1)
        .background(type.background, in: RoundedRectangle(cornerRadius: DSRadius.md))
    }
}

/// Klikbare badge (zelfde look, Figma-states Hover/Pressed via opacity).
public struct DSChip: View {
    private let label: String
    private let icon: Image?
    private let type: DSBadge.BadgeType
    private let action: () -> Void

    public init(
        _ label: String,
        icon: Image? = nil,
        type: DSBadge.BadgeType = .neutral,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.type = type
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            DSBadge(label, icon: icon, type: type)
        }
        .buttonStyle(DSStateOpacityButtonStyle())
    }
}

/// Quota-indicator (resterende gratis portretten e.d.) — brand-badge,
/// zoals in de dark "Stories"-headers.
public struct DSQuotaBadge: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        DSBadge(text, type: .brand)
    }
}
