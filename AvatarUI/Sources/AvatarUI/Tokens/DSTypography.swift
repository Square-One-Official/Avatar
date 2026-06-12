// Typografietokens uit Figma "Aaavatar" — collecties `fontfamily/*`,
// `fontsize/*`, `lineheight/*`, `fontweight/*` en de samengestelde
// tekststijlen `UI/Labels/*`, `Content/Body/*`, `Content/Headings/*`.
// Alleen de stijlen die in de dark "Stories"-frames voorkomen.

import SwiftUI

public enum DSTypography {

    /// `fontfamily/ui` = SF Pro, `fontfamily/display` = SF Pro Display —
    /// beide het systeemfont op macOS; SwiftUI kiest Text/Display optisch
    /// zelf op basis van puntgrootte.
    public enum FontSize {
        /// `fontsize/xs`
        public static let xs: CGFloat = 12
        /// `fontsize/sm`
        public static let sm: CGFloat = 14.2
        /// `fontsize/base`
        public static let base: CGFloat = 16
        /// `fontsize/lg`
        public static let lg: CGFloat = 18
        /// `fontsize/2xl`
        public static let xl2: CGFloat = 22.8
        /// `fontsize/3xl`
        public static let xl3: CGFloat = 25.6
        /// `fontsize/5xl`
        public static let xl5: CGFloat = 32.4
    }

    public enum LineHeight {
        /// `lineheight/xs`
        public static let xs: CGFloat = 16
        /// `lineheight/sm`
        public static let sm: CGFloat = 20
        /// `lineheight/base`
        public static let base: CGFloat = 24
        /// `lineheight/lg`
        public static let lg: CGFloat = 28
        /// `lineheight/2xl`
        public static let xl2: CGFloat = 36
        /// `lineheight/3xl`
        public static let xl3: CGFloat = 40
        /// `lineheight/5xl`
        public static let xl5: CGFloat = 48
    }

    /// `letterspacing/normal`
    public static let letterSpacingNormal: CGFloat = 0
    /// `paragraphspacing/base`
    public static let paragraphSpacingBase: CGFloat = 16
}

/// Samengestelde tekststijl: font + regelhoogte zoals in Figma gedefinieerd.
/// Pas toe via `.dsTextStyle(_:)` zodat de regelhoogte meekomt.
public struct DSTextStyle: Sendable {
    public let size: CGFloat
    public let lineHeight: CGFloat
    public let weight: Font.Weight

    public var font: Font { .system(size: size, weight: weight) }

    // UI/Labels/* — `fontfamily/ui`, semibold
    /// `UI/Labels/Small` — xs/16 semibold
    public static let labelSmall = DSTextStyle(size: DSTypography.FontSize.xs, lineHeight: DSTypography.LineHeight.xs, weight: .semibold)
    /// `UI/Labels/Base` — sm/20 semibold
    public static let labelBase = DSTextStyle(size: DSTypography.FontSize.sm, lineHeight: DSTypography.LineHeight.sm, weight: .semibold)
    /// `UI/Labels/Large` — base/24 semibold
    public static let labelLarge = DSTextStyle(size: DSTypography.FontSize.base, lineHeight: DSTypography.LineHeight.base, weight: .semibold)

    // Content/Body/* — `fontfamily/ui`, regular
    /// `Content/Body/Small` — sm/20 regular
    public static let bodySmall = DSTextStyle(size: DSTypography.FontSize.sm, lineHeight: DSTypography.LineHeight.sm, weight: .regular)
    /// `Content/Body/Medium` — base/24 regular
    public static let bodyMedium = DSTextStyle(size: DSTypography.FontSize.base, lineHeight: DSTypography.LineHeight.base, weight: .regular)

    // Content/Headings/* — `fontfamily/display`, medium
    /// `Content/Headings/H1` — 5xl/48 medium
    public static let h1 = DSTextStyle(size: DSTypography.FontSize.xl5, lineHeight: DSTypography.LineHeight.xl5, weight: .medium)
    /// `Content/Headings/H3` — 3xl/40 medium
    public static let h3 = DSTextStyle(size: DSTypography.FontSize.xl3, lineHeight: DSTypography.LineHeight.xl3, weight: .medium)
    /// `Content/Headings/H4` — 2xl/36 medium
    public static let h4 = DSTextStyle(size: DSTypography.FontSize.xl2, lineHeight: DSTypography.LineHeight.xl2, weight: .medium)
    /// `Content/Headings/H6` — lg/28 medium
    public static let h6 = DSTextStyle(size: DSTypography.FontSize.lg, lineHeight: DSTypography.LineHeight.lg, weight: .medium)
}

extension View {
    /// Figma-tekststijl: font + exacte regelhoogte (via lineSpacing-delta).
    public func dsTextStyle(_ style: DSTextStyle) -> some View {
        self
            .font(style.font)
            .lineSpacing(style.lineHeight - style.size)
            .padding(.vertical, (style.lineHeight - style.size) / 2)
    }
}
