// Kleurtokens uit Figma "Aaavatar" → variabelen zoals gebruikt op pagina's
// "Components" en "Stories" (secties App/Settings/Export/Onboarding).
//
// E23: theme-bewust. Elke token die tussen light/dark verschilt is een
// DYNAMISCHE kleur (`Color(lightHex:darkHex:)`) die resolvet op de effectieve
// appearance van de view — gevoed door `.preferredColorScheme` / de
// AppearancePreference (E15.1). Dark blijft de FALLBACK en is 1-op-1 de oude
// dark-only waarde, zodat de bestaande ~300 call-sites onveranderd blijven en
// een onvolledige light-pas de dark-app nooit breekt. De light-waarden zijn
// afgeleide placeholders (warm stone-palet, brand-lime ongewijzigd) →
// Figma-TODO: bevestigen tegen de Components-variabelen.

import AppKit
import SwiftUI

/// Figma-collectie `background/*` en `foreground/*` (theme-bewust).
public enum DSColor {

    /// `background/*`
    public enum Background {
        /// `background/App` — dark #000000 · light warm off-white
        public static let app = Color(lightHex: 0xFAFAF9, darkHex: 0x000000)
        /// `background/Card` — dark #1c1917 · light #ffffff
        public static let card = Color(lightHex: 0xFFFFFF, darkHex: 0x1C1917)
        /// `background/Inset` — dark #292524 · light stone-100
        public static let inset = Color(lightHex: 0xF5F5F4, darkHex: 0x292524)
        /// `background/neutral` — wit@5% (dark) · zwart@5% (light)
        public static let neutral = Color(lightHex: 0x000000, lightAlpha: 0x0D, darkHex: 0xFFFFFF, darkAlpha: 0x0D)
        /// `background/neutral-stronger` — wit@10% (dark) · zwart@10% (light)
        public static let neutralStronger = Color(lightHex: 0x000000, lightAlpha: 0x1A, darkHex: 0xFFFFFF, darkAlpha: 0x1A)
        /// `background/neutral-strongest` — wit@15% (dark) · zwart@15% (light)
        public static let neutralStrongest = Color(lightHex: 0x000000, lightAlpha: 0x26, darkHex: 0xFFFFFF, darkAlpha: 0x26)
        /// `background/action` — #d5f466 (lime-accent, brand; beide themes)
        public static let action = Color(hex: 0xD5F466)
        /// `background/shadow` — #190b0859 (donkere drop-shadow; beide themes)
        public static let shadow = Color(hex: 0x190B08, alpha: 0x59)
        /// `background/tooltip` — donkere chip in beide themes (#000 / #1c1917)
        public static let tooltip = Color(lightHex: 0x1C1917, darkHex: 0x000000)
        /// `background/canvas-isolated` — donkerder dan card maar lichter dan app;
        /// gebruikt als canvas-achtergrond bij geïsoleerd portret zonder ingestelde
        /// achtergrond, zodat de card-kleurige toolbar-capsule zichtbaar wordt.
        /// dark #111111 · light #ECEAE6
        public static let canvasIsolated = Color(lightHex: 0xECEAE6, darkHex: 0x111111)
    }

    /// `foreground/default/*`
    public enum Foreground {
        /// `foreground/default/primary` — wit (dark) · warm bijna-zwart (light)
        public static let primary = Color(lightHex: 0x1C1917, darkHex: 0xFFFFFF)
        /// `foreground/default/subtle` — 70% (wit/zwart)
        public static let subtle = Color(lightHex: 0x1C1917, lightAlpha: 0xB2, darkHex: 0xFFFFFF, darkAlpha: 0xB2)
        /// `foreground/default/muted` — 40% (wit/zwart)
        public static let muted = Color(lightHex: 0x1C1917, lightAlpha: 0x66, darkHex: 0xFFFFFF, darkAlpha: 0x66)
        /// `foreground/default/divider` — 10% (wit/zwart)
        public static let divider = Color(lightHex: 0x000000, lightAlpha: 0x1A, darkHex: 0xFFFFFF, darkAlpha: 0x1A)
        /// `foreground/default/primary-static-black` — #111111 (altijd donker,
        /// bv. splash-tekst op lichte achtergrond) — beide themes.
        public static let primaryStaticBlack = Color(hex: 0x111111)
        /// `foreground/default/thumb` — wit (dark) · donker (light)
        public static let thumb = Color(lightHex: 0x1C1917, darkHex: 0xFFFFFF)
    }

    /// Signaalkleuren (Figma Badge Type=Error/Success/Warning/Info). Pastel,
    /// in beide themes gelijk gehouden. Figma-TODO: light-varianten +
    /// contrast bevestigen zodra de Input-error/success-tokens in de library
    /// staan.
    public enum Signal {
        /// `background/error` — #fdbaba
        public static let error = Color(hex: 0xFDBABA)
        /// `background/success` — #bcfad3
        public static let success = Color(hex: 0xBCFAD3)
        /// `background/warning` — #ffeeb8
        public static let warning = Color(hex: 0xFFEEB8)
        /// `background/info` — #b8d3ff
        public static let info = Color(hex: 0xB8D3FF)
    }

    /// `foreground/action/primary/*` — brand-lime, beide themes gelijk.
    public enum Action {
        /// `foreground/action/primary/default` — #d5f466 (lime-accent)
        public static let primary = Color(hex: 0xD5F466)
        /// `foreground/action/primary/on-action` — #073c31
        public static let onAction = Color(hex: 0x073C31)
    }

    /// `Projects/*` — kleurlabels (Project color picker), beide themes gelijk.
    public enum Projects {
        /// `Projects/Project 1` — #ffaeae
        public static let project1 = Color(hex: 0xFFAEAE)
        /// `Projects/Project 4` — #ffffae
        public static let project4 = Color(hex: 0xFFFFAE)
        /// `Projects/Project 8` — #aeffc9
        public static let project8 = Color(hex: 0xAEFFC9)
        /// `Projects/Project 12` — #aec9ff
        public static let project12 = Color(hex: 0xAEC9FF)
        /// `Projects/Project 15` — #e4aeff
        public static let project15 = Color(hex: 0xE4AEFF)
        /// `Projects/Project 18` — #ffaec9
        public static let project18 = Color(hex: 0xFFAEC9)
    }
}

extension Color {
    /// 0xRRGGBB + losse alpha-byte (0x00–0xFF), zoals de Figma-hexnotatie.
    init(hex: UInt32, alpha: UInt8 = 0xFF) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: Double(alpha) / 255.0
        )
    }

    /// E23: theme-bewuste token. Resolvet light↔dark op de effectieve
    /// appearance van de view (via een dynamische NSColor). Dark = fallback.
    init(lightHex: UInt32, lightAlpha: UInt8 = 0xFF, darkHex: UInt32, darkAlpha: UInt8 = 0xFF) {
        let light = NSColor(srgbHex: lightHex, alpha: lightAlpha)
        let dark = NSColor(srgbHex: darkHex, alpha: darkAlpha)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

extension NSColor {
    /// sRGB uit 0xRRGGBB + alpha-byte.
    convenience init(srgbHex hex: UInt32, alpha: UInt8) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: CGFloat(alpha) / 255.0
        )
    }

    /// E23: theme-bewuste NSColor (voor AppKit-backed views zoals NSTextField).
    static func dsDynamic(lightHex: UInt32, darkHex: UInt32, alpha: UInt8 = 0xFF) -> NSColor {
        let light = NSColor(srgbHex: lightHex, alpha: alpha)
        let dark = NSColor(srgbHex: darkHex, alpha: alpha)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

/// E23: theme-bewuste NSColor-pendanten van de foreground-tokens (voor
/// AppKit-tekst die geen SwiftUI `Color` kan gebruiken). Light = warm
/// bijna-zwart (#1c1917), dark = wit — gelijk aan DSColor.Foreground.
public enum DSNSColor {
    public static let foregroundPrimary = NSColor.dsDynamic(lightHex: 0x1C1917, darkHex: 0xFFFFFF)
    public static let foregroundSubtle = NSColor.dsDynamic(lightHex: 0x1C1917, darkHex: 0xFFFFFF, alpha: 0xB2)
    public static let foregroundMuted = NSColor.dsDynamic(lightHex: 0x1C1917, darkHex: 0xFFFFFF, alpha: 0x66)
}
