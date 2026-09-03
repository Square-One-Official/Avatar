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

    /// Vensterradius van macOS (E03.15, bevinding 17). Geen publieke API
    /// om hem op te vragen; 12 is de gemeten benadering voor het
    /// titelbalkloze venster — bij een andere macOS-ronding is dít de
    /// enige constante die bijgesteld hoeft te worden.
    public static let window: CGFloat = 12

    /// Concentrische binnenradius: `outer − inset`, zodat de twee rondingen
    /// parallel lopen. Default `outer` is de vensterradius (kaart-aan-de-rand).
    /// Geef `outer:` mee voor elk ander nest (menu-rij in een menu-kaart).
    public static func concentric(inset: CGFloat, outer: CGFloat = window) -> CGFloat {
        max(outer - inset, 0)
    }
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

    // UXS-21: de app had 11 ad-hoc `.shadow(color: .black.opacity(…))`-recepten
    // met zeven verschillende radius/offset-combinaties. Drie semantische
    // niveaus dekken ze allemaal; zwart-met-alpha blijft de kleur (een schaduw
    // hoort donker te zijn in béíde themes, dus géén thema-token).
    /// Rustende oppervlakken die net van de achtergrond loskomen: kaarten,
    /// zwevende pillen, thumbnails.
    public static let card = DSShadow(
        color: .black.opacity(0.12),
        offset: CGSize(width: 0, height: 4),
        radius: 12,
        spread: 0
    )

    /// Chrome dat bóven content zweeft: floating toolbars, popovers, sheets.
    public static let overlay = DSShadow(
        color: .black.opacity(0.25),
        offset: CGSize(width: 0, height: 6),
        radius: 16,
        spread: 0
    )

    /// Handles/markers óp een canvas — nét genoeg om van het beeld te lichten.
    public static let handle = DSShadow(
        color: .black.opacity(0.25),
        offset: CGSize(width: 0, height: 1),
        radius: 1,
        spread: 0
    )
}

public extension View {
    /// Past een DS-schaduwtoken toe. `scale` schaalt radius én offset mee voor
    /// canvas-elementen die met de camera meeschalen (inverse zoom).
    func dsShadow(_ shadow: DSShadow, scale: CGFloat = 1) -> some View {
        dsVectorSafeShadow(
            color: shadow.color,
            radius: shadow.radius * scale,
            x: shadow.offset.width * scale,
            y: shadow.offset.height * scale
        )
    }
}
