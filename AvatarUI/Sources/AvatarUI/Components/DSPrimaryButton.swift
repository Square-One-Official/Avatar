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
    private let fullWidth: Bool
    private let action: () -> Void

    /// E18.9: leesbare disabled-staat — i.p.v. de hele lime-pil te dimmen
    /// (donkere tekst op dof-lime = onleesbaar) een neutrale pil met
    /// muted-maar-leesbare tekst.
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: String,
        icon: Image? = nil,
        size: Size = .default,
        fullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.size = size
        self.fullWidth = fullWidth
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            DSButtonLabel(title: title, icon: icon, size: size)
                .fixedSize(horizontal: !fullWidth, vertical: false)
                .foregroundStyle(isEnabled ? DSColor.Action.onAction : DSColor.Foreground.muted)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, size.horizontalPadding)
                .padding(.vertical, size.verticalPadding)
                .background(isEnabled ? DSColor.Background.action : DSColor.Background.neutralStronger, in: Capsule())
        }
        .buttonStyle(DSStateOpacityButtonStyle())
    }
}
