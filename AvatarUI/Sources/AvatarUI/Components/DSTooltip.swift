// Tooltip — 1-op-1 op de Figma "Tooltip"-component (Components 58:1298):
// zwarte surface (background/tooltip #000000), witte tekst Content/Body/Small,
// r-lg (8) hoeken, met een caret die naar het doel wijst. Padding gap-3
// horizontaal / gap-2 verticaal. Gebruikt o.a. als hover-tooltip op
// icon-buttons (E18.10).

import SwiftUI

public struct DSTooltip: View {
    private let text: String
    /// Aan welke kant de caret zit (= de kant van het doel). `.bottom` = caret
    /// onderaan → tooltip stáát boven het doel (standaard).
    private let caretEdge: VerticalEdge

    public init(_ text: String, caretEdge: VerticalEdge = .bottom) {
        self.text = text
        self.caretEdge = caretEdge
    }

    private let caretWidth: CGFloat = 12
    private let caretHeight: CGFloat = 6

    public var body: some View {
        VStack(spacing: 0) {
            if caretEdge == .top {
                caret(pointingUp: true)
            }
            Text(text)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.primary)
                .lineLimit(1)
                .padding(.horizontal, DSSpacing.gap3)
                .padding(.vertical, DSSpacing.gap2)
                .background(
                    DSColor.Background.tooltip,
                    in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                )
            if caretEdge == .bottom {
                caret(pointingUp: false)
            }
        }
        .fixedSize()
    }

    private func caret(pointingUp: Bool) -> some View {
        DSTooltipCaret(pointingUp: pointingUp)
            .fill(DSColor.Background.tooltip)
            .frame(width: caretWidth, height: caretHeight)
    }
}

/// Driehoekje dat de tooltip naar het doel laat wijzen.
private struct DSTooltipCaret: Shape {
    let pointingUp: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointingUp {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
