// Canvas-kaart (E03.12; Figma: de "Image"-nodes in App / Edit, Image
// added, Effects e.v., bv. 4017:1811). De foto staat nooit rand-tot-rand
// in het venster maar in een afgeronde donkere kaart: bg Card, r-4xl,
// inhoud gevuld en geclipt. Zonder ingestelde achtergrond toont de kaart
// een programmatisch stippenraster — transparante cutout-delen laten het
// raster zien en communiceren "achtergrond verwijderd". Rastermaten 1:1
// gemeten uit de 465×456-render: hartafstand 17pt, stip Ø3, kleur wit 15%
// (de neutral-strongest-waarde) op de kaart.

import SwiftUI

public struct DSCanvasCard<Content: View>: View {
    private let showsDotGrid: Bool
    private let content: Content

    public init(showsDotGrid: Bool = false, @ViewBuilder content: () -> Content) {
        self.showsDotGrid = showsDotGrid
        self.content = content()
    }

    public var body: some View {
        ZStack {
            DSColor.Background.card
            if showsDotGrid {
                DSDotGrid()
            }
            content
        }
        // Vast vierkant (E03.14, bevinding 11): het canvas is het
        // exportformaat (1:1); de inhoud vult de kaart (aspect-fill door
        // de caller) en wordt door de kaart geclipt.
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl4))
    }
}

/// Het stippenraster van de canvas-kaart; los bruikbaar als placeholder-
/// achtergrond. Getekend, geen asset.
public struct DSDotGrid: View {
    private static let spacing: CGFloat = 17
    private static let diameter: CGFloat = 3

    public init() {}

    public var body: some View {
        Canvas { context, size in
            var y = Self.spacing / 2
            while y < size.height {
                var x = Self.spacing / 2
                while x < size.width {
                    let rect = CGRect(
                        x: x - Self.diameter / 2,
                        y: y - Self.diameter / 2,
                        width: Self.diameter,
                        height: Self.diameter
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(DSColor.Background.neutralStrongest)
                    )
                    x += Self.spacing
                }
                y += Self.spacing
            }
        }
        .accessibilityHidden(true)
    }
}
