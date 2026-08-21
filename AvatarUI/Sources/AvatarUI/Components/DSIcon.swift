// DSIcon (E20.1) — semantische icoon-laag. De rest van de app vraagt iconen
// op betekenis (`.edit`, `.face`, `.share`) i.p.v. op concrete symbol-namen,
// zodat een icoon-wissel hier centraal gebeurt. Grootte/gewicht komen mee als
// parameter; de KLEUR zet de aanroeper met `.foregroundStyle` (template-images),
// default primary.
//
// BACKING: SF Symbols — BESLIST 2026-07-12 (E49.4, zie plan/DECISIONS-PENDING.md).
// Figma tekende Phosphor, maar de Phosphor-SPM-package (asset-catalog) breekt de
// CLI-DoD (`swift test`, geen actool); de dependency is verwijderd. De bedoelde
// Phosphor-naam staat per case in commentaar: mocht Thierry later alsnog naar
// Phosphor willen (font-gebaseerde bron), dan is deze file de enige omschakelplek.

import SwiftUI

public struct DSIcon: View {
    public enum Symbol {
        // Bottom-toolbar tools
        case edit, effects, face, clothing, hair, background, images
        // App-bar / chrome
        case share, settings, undo, redo, add, close
        // Canvas-controls
        case crop, autoFrame, flip, restoreBody
        // Canvas-toolbar (frame-pil + dropdowns)
        case frame, grid, shapeCircle, shapeSquare
        // Face-edits (FaceActionsPanel-presetkaarten)
        case whitenTeeth, applyMakeup, reduceWrinkles
        // Overig
        case check, sparkle, colorize, boost
        // Privacy tiers (Privacy Tier Picker)
        case privacyOnDevice, privacyAppleCloud, privacyAdvanced
    }

    public enum Weight {
        case light, regular, bold

        var fontWeight: Font.Weight {
            switch self {
            case .light: return .light
            case .regular: return .regular
            case .bold: return .semibold
            }
        }
    }

    private let symbol: Symbol
    private let size: CGFloat
    private let weight: Weight

    public init(_ symbol: Symbol, size: CGFloat = 20, weight: Weight = .regular) {
        self.symbol = symbol
        self.size = size
        self.weight = weight
    }

    public var body: some View {
        Image(systemName: Self.systemName(for: symbol))
            .font(.system(size: size, weight: weight.fontWeight))
            .foregroundStyle(DSColor.Foreground.primary)
    }

    /// SF-Symbol per betekenis (interim). De becommentarieerde naam is de
    /// bedoelde Phosphor-icoon zodra de package-route werkt.
    private static func systemName(for symbol: Symbol) -> String {
        switch symbol {
        case .edit:        return "paintpalette"        // Ph.palette
        case .effects:     return "sparkles"            // Ph.sparkle
        case .face:        return "face.smiling"        // Ph.smiley
        case .clothing:    return "tshirt"              // Ph.tShirt
        case .hair:        return "scissors"            // Ph.scissors (Figma-TODO: kam)
        case .background:  return "photo"               // Ph.image
        case .images:      return "square.grid.2x2"     // Ph.images
        case .share:       return "square.and.arrow.up" // Ph.shareNetwork
        case .settings:    return "gearshape.fill"      // Ph.gearSix
        case .undo:        return "arrow.uturn.backward" // Ph.arrowArcLeft
        case .redo:        return "arrow.uturn.forward"  // Ph.arrowArcRight
        case .add:         return "plus"                // Ph.plus
        case .close:       return "xmark"               // Ph.x
        case .crop:        return "crop"                // Ph.crop
        case .autoFrame:   return "viewfinder"          // Ph.cornersOut
        case .flip:        return "arrow.left.and.right.righttriangle.left.righttriangle.right" // Ph.flipHorizontal
        case .restoreBody: return "arrow.up.left.and.arrow.down.right" // Ph.arrowsOutCardinal
        case .frame:       return "rectangle.dashed"    // Ph.frameCorners
        case .grid:        return "square.grid.3x3"     // Ph.gridNine
        case .shapeCircle: return "circle"              // Ph.circle
        case .shapeSquare: return "square"              // Ph.square
        case .whitenTeeth: return "mouth"               // Ph.tooth
        case .applyMakeup: return "paintpalette"        // Ph.palette
        case .reduceWrinkles: return "face.smiling"     // Ph.smiley
        case .check:       return "checkmark"           // Ph.check
        case .sparkle:     return "sparkles"            // Ph.sparkle
        case .colorize:    return "paintpalette"        // Ph.palette
        case .boost:       return "arrow.up.left.and.arrow.down.right" // upscale
        case .privacyOnDevice:  return "lock.shield"           // Ph.shieldCheck
        case .privacyAppleCloud: return "sparkles"             // Ph.sparkle
        case .privacyAdvanced: return "cloud.fill"            // Ph.cloud
        }
    }

    /// E49.4: het kale SF-Image per betekenis — voor contexten die zélf tinten
    /// en maatvoeren (bv. `DSCapsuleToolButton`s active-lime of dropdown-rijen).
    /// Anders dan de `DSIcon`-view zet dit GEEN vaste foregroundStyle, zodat de
    /// omgevings-tint (active/hover-states) blijft werken.
    public static func image(_ symbol: Symbol) -> Image {
        Image(systemName: systemName(for: symbol))
    }
}
