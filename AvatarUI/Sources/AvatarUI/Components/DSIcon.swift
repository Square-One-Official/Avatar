// DSIcon (E20.1) — semantische icoon-laag. De rest van de app vraagt iconen
// op betekenis (`.edit`, `.face`, `.share`) i.p.v. op concrete symbol-namen,
// zodat een icoon-wissel hier centraal gebeurt. Grootte/gewicht komen mee als
// parameter; de KLEUR zet de aanroeper met `.foregroundStyle` (template-images),
// default primary.
//
// BACKING: bedoeld zijn Phosphor-iconen (Figma), maar de Phosphor-SPM-package
// (`phosphor-icons/swift`, 2.1.0) levert een asset-catalog die de CLI-DoD
// (`swift test --package-path AvatarUI`, geen actool) niet kan compileren →
// `Bundle.module`-fout. Daarom draait DSIcon interim op SF Symbols met een
// 1-op-1 plek voor de Phosphor-namen. Zie plan/DECISIONS-PENDING.md.
// Figma-TODO: terug naar Phosphor zodra de CLI-build-route is opgelost
// (AvatarUI-tests via xcodebuild, of een font-gebaseerde Phosphor-bron).

import SwiftUI

public struct DSIcon: View {
    public enum Symbol {
        // Bottom-toolbar tools
        case edit, effects, face, clothing, hair, background, images
        // App-bar / chrome
        case share, settings, undo, redo, add, close
        // Canvas-controls
        case crop, autoFrame, fixAngle, flip, restoreBody
        // Overig
        case check, sparkle, colorize, boost
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
        case .fixAngle:    return "camera"              // Ph.perspective
        case .flip:        return "arrow.left.and.right.righttriangle.left.righttriangle.right" // Ph.flipHorizontal
        case .restoreBody: return "arrow.up.left.and.arrow.down.right" // Ph.arrowsOutCardinal
        case .check:       return "checkmark"           // Ph.check
        case .sparkle:     return "sparkles"            // Ph.sparkle
        case .colorize:    return "paintpalette"        // Ph.palette
        case .boost:       return "arrow.up.left.and.arrow.down.right" // upscale
        }
    }
}
