// Kleurtokens uit Figma "Aaavatar" → variabelen zoals gebruikt op pagina's
// "Components" en "Stories" (secties App/Settings/Export/Onboarding → Dark).
// Aaavatar 2.0 is dark-only: dit zijn de dark-mode-waarden, statisch.

import SwiftUI

/// Figma-collectie `background/*` en `foreground/*` (dark mode).
public enum DSColor {

    /// `background/*`
    public enum Background {
        /// `background/App` — #000000
        public static let app = Color(hex: 0x000000)
        /// `background/Card` — #1c1917
        public static let card = Color(hex: 0x1C1917)
        /// `background/Inset` — #292524
        public static let inset = Color(hex: 0x292524)
        /// `background/neutral` — #ffffff0d
        public static let neutral = Color(hex: 0xFFFFFF, alpha: 0x0D)
        /// `background/neutral-stronger` — geen dark-frame gebruikt deze;
        /// geïnterpoleerd op de dark-schaal 5/10/15% wit (= divider-waarde).
        public static let neutralStronger = Color(hex: 0xFFFFFF, alpha: 0x1A)
        /// `background/neutral-strongest` — #ffffff26
        public static let neutralStrongest = Color(hex: 0xFFFFFF, alpha: 0x26)
        /// `background/action` — #d5f466 (lime-accent)
        public static let action = Color(hex: 0xD5F466)
        /// `background/shadow` — #190b0859
        public static let shadow = Color(hex: 0x190B08, alpha: 0x59)
    }

    /// `foreground/default/*`
    public enum Foreground {
        /// `foreground/default/primary` — #ffffff
        public static let primary = Color(hex: 0xFFFFFF)
        /// `foreground/default/subtle` — #ffffffb2
        public static let subtle = Color(hex: 0xFFFFFF, alpha: 0xB2)
        /// `foreground/default/muted` — #ffffff66
        public static let muted = Color(hex: 0xFFFFFF, alpha: 0x66)
        /// `foreground/default/divider` — #ffffff1a
        public static let divider = Color(hex: 0xFFFFFF, alpha: 0x1A)
        /// `foreground/default/primary-static-black` — #111111
        public static let primaryStaticBlack = Color(hex: 0x111111)
        /// `foreground/default/thumb` — #ffffff
        public static let thumb = Color(hex: 0xFFFFFF)
    }

    /// `foreground/action/primary/*`
    public enum Action {
        /// `foreground/action/primary/default` — #d5f466 (lime-accent)
        public static let primary = Color(hex: 0xD5F466)
        /// `foreground/action/primary/on-action` — #073c31
        public static let onAction = Color(hex: 0x073C31)
    }

    /// `Projects/*` — kleurlabels zoals gebruikt in de dark "Stories"-frames
    /// (Project color picker). Alleen de daar voorkomende indices.
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
}
