// Figma "Stories" → App / Sidebar images (dark) → "Slot" (4011:5010):
// rij met padding gap-2 en gap-2, avatar 48×48 (radius 16), titelkolom
// gap-0.5 met naam (UI/Labels/Base, primary) en rol (UI/Labels/Base,
// muted). Geselecteerde rij krijgt bg background/Inset op r-2xl; de
// overige rijen zijn transparant.

import SwiftUI

public struct DSSidebarRow<Avatar: View>: View {
    private let name: String
    private let role: String?
    private let isSelected: Bool
    private let action: () -> Void
    private let avatar: Avatar

    public init(
        name: String,
        role: String? = nil,
        isSelected: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder avatar: () -> Avatar
    ) {
        self.name = name
        self.role = role
        self.isSelected = isSelected
        self.action = action
        self.avatar = avatar()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap2) {
                avatar
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
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
            }
            .padding(DSSpacing.gap2)
            .background(
                isSelected ? DSColor.Background.inset : .clear,
                in: RoundedRectangle(cornerRadius: DSRadius.xl2)
            )
        }
        .buttonStyle(DSStateOpacityButtonStyle())
        .accessibilityLabel(Text(role.map { "\(name), \($0)" } ?? name))
    }
}
