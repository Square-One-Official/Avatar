// Layouttokens uit Figma "Aaavatar" — collecties `gap-*`, `border-radius/*`,
// `border-width/*` en de opacity-schaal (Hidden/Disabled/Subtle/Medium/Strong).

import SwiftUI

/// `gap-*` — spacing-schaal (Figma-naam → punten).
public enum DSSpacing {
    /// `gap-0`
    public static let gap0: CGFloat = 0
    /// `gap-px`
    public static let gapPx: CGFloat = 1
    /// `gap-0.5`
    public static let gap0_5: CGFloat = 2
    /// `gap-1`
    public static let gap1: CGFloat = 4
    /// `gap-1.5`
    public static let gap1_5: CGFloat = 6
    /// `gap-2`
    public static let gap2: CGFloat = 8
    /// `gap-2.5`
    public static let gap2_5: CGFloat = 10
    /// `gap-3`
    public static let gap3: CGFloat = 12
    /// `gap-3.5`
    public static let gap3_5: CGFloat = 14
    /// `gap-4`
    public static let gap4: CGFloat = 16
    /// `gap-5`
    public static let gap5: CGFloat = 20
    /// `gap-6`
    public static let gap6: CGFloat = 24
    /// `gap-8`
    public static let gap8: CGFloat = 32
    /// `gap-12`
    public static let gap12: CGFloat = 48
}

/// `border-radius/*`
public enum DSRadius {
    /// `border-radius/r-sm`
    public static let sm: CGFloat = 2
    /// `border-radius/r-default`
    public static let `default`: CGFloat = 4
    /// `border-radius/r-md`
    public static let md: CGFloat = 6
    /// `border-radius/r-lg`
    public static let lg: CGFloat = 8
    /// `border-radius/r-xl`
    public static let xl: CGFloat = 12
    /// `border-radius/r-2xl`
    public static let xl2: CGFloat = 16
    /// `border-radius/r-3xl`
    public static let xl3: CGFloat = 20
    /// `border-radius/r-4xl`
    public static let xl4: CGFloat = 24
    /// `border-radius/r-full`
    public static let full: CGFloat = 96
}

/// `border-width/*`
public enum DSBorderWidth {
    /// `border-width/b-thin`
    public static let thin: CGFloat = 1
    /// `border-width/b-medium`
    public static let medium: CGFloat = 2
}

/// Opacity-schaal (Figma 0–100 → 0–1).
public enum DSOpacity {
    /// `Hidden`
    public static let hidden: Double = 0
    /// `Disabled`
    public static let disabled: Double = 0.25
    /// `Subtle`
    public static let subtle: Double = 0.5
    /// `Medium`
    public static let medium: Double = 0.75
    /// `Strong`
    public static let strong: Double = 1.0
}

/// `Shadows/Default` — Effect(type: DROP_SHADOW, color: background/shadow,
/// offset: (0, 80), radius: 80, spread: -40). Ruwe Figma-waarden; spread
/// kent SwiftUI niet, componenten passen dit zelf toe.
public struct DSShadow: Sendable {
    public let color: Color
    public let offset: CGSize
    public let radius: CGFloat
    public let spread: CGFloat

    public static let `default` = DSShadow(
        color: DSColor.Background.shadow,
        offset: CGSize(width: 0, height: 80),
        radius: 80,
        spread: -40
    )
}
