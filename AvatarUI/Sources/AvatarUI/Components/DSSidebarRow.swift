// Figma "Stories" → App / Sidebar images (dark) → "Slot" (4011:5010):
// rij met padding gap-2 en gap-2, avatar 48×48 (radius 16), titelkolom
// gap-0.5 met naam (UI/Labels/Base, primary) en rol (UI/Labels/Base,
// muted). Hover krijgt het afgeronde Inset-kleurvlak met ~100ms fade
// (E03.18, punt 22); selectie is één tint sterker (Inset + neutral-laag)
// zodat de actieve rij herkenbaar blijft terwijl je elders hovert.

import SwiftUI

public struct DSSidebarRow<Avatar: View>: View {
    private let name: String
    private let role: String?
    private let isSelected: Bool
    private let isMultiSelected: Bool
    private let action: () -> Void
    private let avatar: Avatar

    public init(
        name: String,
        role: String? = nil,
        isSelected: Bool = false,
        isMultiSelected: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder avatar: () -> Avatar
    ) {
        self.name = name
        self.role = role
        self.isSelected = isSelected
        self.isMultiSelected = isMultiSelected
        self.action = action
        self.avatar = avatar()
    }

    @State private var isHovering = false

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap2) {
                avatar
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: DSRadius.xl2, style: .continuous))
                VStack(alignment: .leading, spacing: DSSpacing.gap0_5) {
                    Text(name)
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.primary)
                    if let role {
                        Text(role)
                            .dsTextStyle(.labelBase)
                            .foregroundStyle(DSColor.Foreground.muted)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                // E19.4: multi-select-indicator (lime check), los van de
                // canvas-selectie-highlight.
                if isMultiSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DSColor.Action.primaryForeground)
                }
            }
            .padding(DSSpacing.gap2)
            .background {
                let shape = RoundedRectangle(cornerRadius: DSRadius.xl2)
                ZStack {
                    if isSelected || isHovering || isMultiSelected {
                        shape.fill(DSColor.Background.inset)
                    }
                    if isSelected {
                        // Eén tint sterker dan hover (Inset + neutral-laag).
                        shape.fill(DSColor.Background.neutral)
                    }
                    // E19.4: lime rand bij multi-select.
                    if isMultiSelected {
                        shape.strokeBorder(DSColor.Action.primaryForeground, lineWidth: DSBorderWidth.medium)
                    }
                }
            }
        }
        .buttonStyle(DSStateOpacityButtonStyle())
        .onHover { isHovering = $0 }
        .dsMotion(DSMotion.micro, value: isHovering)
        .accessibilityLabel(Text(role.map { "\(name), \($0)" } ?? name))
    }
}
