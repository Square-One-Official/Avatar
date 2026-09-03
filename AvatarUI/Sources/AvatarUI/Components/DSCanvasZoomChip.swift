// Zoom-readout linksonder op een canvas (UXS-6/UXS-16).
//
// De app heeft drie canvassen — editor, board en Banner Studio — en die hadden
// elk hun eigen capsule-recept (of, in het geval van de Studio, helemaal geen
// zoom-UI). Dezelfde affordance er drie keer los in laten staan is precies hoe
// ze uit elkaar gaan lopen; dit is die ene component.
//
// Gedrag: toont de huidige zoom als percentage waarbij **fit = 100%** (niet de
// absolute schaal — "100%" moet "alles past" betekenen, niet "1 punt per pixel";
// daar is ⌘1/Actual Size voor). Klik = terug naar fit.

import SwiftUI

public struct DSCanvasZoomChip: View {
    private let title: String
    private let help: String
    private let action: () -> Void

    /// Percentage-variant (editor, Banner Studio).
    public init(
        scale: CGFloat,
        fitScale: CGFloat,
        help: String = "Zoom to Fit (⌘0)",
        action: @escaping () -> Void
    ) {
        self.title = Self.percentLabel(scale: scale, fitScale: fitScale)
        self.help = help
        self.action = action
    }

    /// Tekst-variant (board: "Fit").
    public init(
        title: String,
        help: String = "Zoom to Fit (⌘0)",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.help = help
        self.action = action
    }

    /// Zoom als percentage van de fit-stand. Pure functie zodat de afronding
    /// testbaar is — een chip die "0%" of "NaN%" toont is erger dan geen chip.
    public static func percentLabel(scale: CGFloat, fitScale: CGFloat) -> String {
        guard fitScale > 0, scale.isFinite, fitScale.isFinite else { return "100%" }
        let percent = Int((scale / fitScale * 100).rounded())
        return "\(max(percent, 1))%"
    }

    @Environment(\.dsVectorExport) private var vectorExport

    public var body: some View {
        Button(action: action) {
            Text(title)
                .dsTextStyle(.labelSmall)
                .monospacedDigit()
                .foregroundStyle(DSColor.Foreground.primary)
                .padding(.horizontal, DSSpacing.gap3)
                .frame(height: 30)
                .background {
                    if vectorExport {
                        // Vector-export: material rastert; kaartkleur als benadering.
                        Capsule().fill(DSColor.Background.card.opacity(0.92))
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                    }
                }
                .overlay(Capsule().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
        .help(help)
        .padding(DSSpacing.gap4)
    }
}
