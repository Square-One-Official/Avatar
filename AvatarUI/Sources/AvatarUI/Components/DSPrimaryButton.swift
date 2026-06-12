// Figma "Components" → Button, Type=Fill, Color=Brand (lime pill).
// Maten: Default (h40, px gap-4, py gap-2.5, label UI/Labels/Base, icon 20)
// en Small (h24, px gap-2, py gap-1, label UI/Labels/Small).

import SwiftUI

public struct DSPrimaryButton: View {
    public enum Size: Sendable {
        case `default`
        case small

        var textStyle: DSTextStyle { self == .default ? .labelBase : .labelSmall }
        var horizontalPadding: CGFloat { self == .default ? DSSpacing.gap4 : DSSpacing.gap2 }
        var verticalPadding: CGFloat { self == .default ? DSSpacing.gap2_5 : DSSpacing.gap1 }
        var contentGap: CGFloat { self == .default ? DSSpacing.gap2 : DSSpacing.gap1 }
        var iconSize: CGFloat { self == .default ? 20 : 16 }
    }

    private let title: String
    private let icon: Image?
    private let size: Size
    private let action: () -> Void

    public init(_ title: String, icon: Image? = nil, size: Size = .default, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: size.contentGap) {
                if let icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.iconSize, height: size.iconSize)
                }
                Text(title)
                    .dsTextStyle(size.textStyle)
                    .lineLimit(1)
            }
            .foregroundStyle(DSColor.Action.onAction)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(DSColor.Background.action, in: Capsule())
        }
        .buttonStyle(DSStateOpacityButtonStyle())
    }
}
