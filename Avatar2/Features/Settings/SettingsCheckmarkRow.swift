// Gedeelde selecteerbare rij (checkmark rechts) voor Settings, onboarding
// en vergelijkbare pickers (Paywall credit packs). Eén hover/selected-taal.

import AvatarUI
import SwiftUI

enum SettingsSelectableRowSurface {
    /// Selected → neutral; hover → neutralStronger; idle → `idleBackground`.
    static func color(
        isSelected: Bool,
        isDisabled: Bool,
        isHovering: Bool,
        idleBackground: Color = .clear
    ) -> Color {
        if isSelected { return DSColor.Background.neutral }
        guard !isDisabled else { return idleBackground }
        if isHovering { return DSColor.Background.neutralStronger }
        return idleBackground
    }
}

/// Radio-achtige rij: titel + subtitel, optioneel leading, checkmark rechts.
struct SettingsCheckmarkRow<Leading: View>: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    var isDisabled: Bool = false
    var titleColor: Color?
    @ViewBuilder var leading: () -> Leading
    let action: () -> Void

    @State private var isHovering = false

    private var resolvedTitleColor: Color {
        if let titleColor { return titleColor }
        return isDisabled ? DSColor.Foreground.muted : DSColor.Foreground.primary
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DSSpacing.gap3) {
                leading()

                VStack(alignment: .leading, spacing: DSSpacing.gap0_5) {
                    Text(title)
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(resolvedTitleColor)
                    Text(subtitle)
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DSSpacing.gap2)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(
                        isSelected ? DSColor.Action.primaryForeground : DSColor.Foreground.muted
                    )
                    .opacity(isDisabled ? 0.4 : 1)
            }
            .padding(DSSpacing.gap4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                SettingsSelectableRowSurface.color(
                    isSelected: isSelected,
                    isDisabled: isDisabled,
                    isHovering: isHovering
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovering = $0 && !isDisabled }
        .animation(DSMotion.micro, value: isHovering)
    }
}

extension SettingsCheckmarkRow where Leading == EmptyView {
    init(
        title: String,
        subtitle: String,
        isSelected: Bool,
        isDisabled: Bool = false,
        titleColor: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.titleColor = titleColor
        self.leading = { EmptyView() }
        self.action = action
    }
}

/// Hover + selected achtergrond voor custom row-layouts (bv. Paywall met border).
struct SettingsSelectableRowHoverSurface: ViewModifier {
    let isSelected: Bool
    var isDisabled: Bool = false
    var idleBackground: Color = .clear
    var cornerRadius: CGFloat = DSRadius.lg

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                SettingsSelectableRowSurface.color(
                    isSelected: isSelected,
                    isDisabled: isDisabled,
                    isHovering: isHovering,
                    idleBackground: idleBackground
                ),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .onHover { isHovering = $0 && !isDisabled }
            .animation(DSMotion.micro, value: isHovering)
    }
}

extension View {
    func settingsSelectableRowHoverSurface(
        isSelected: Bool,
        isDisabled: Bool = false,
        idleBackground: Color = .clear,
        cornerRadius: CGFloat = DSRadius.lg
    ) -> some View {
        modifier(SettingsSelectableRowHoverSurface(
            isSelected: isSelected,
            isDisabled: isDisabled,
            idleBackground: idleBackground,
            cornerRadius: cornerRadius
        ))
    }
}
