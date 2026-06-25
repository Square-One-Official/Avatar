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
    private let surfaceClip: AnyShape
    private let content: Content
    private let backgroundColor: Color

    private let dotGridDimmed: Bool

    public init(
        showsDotGrid: Bool = false,
        dotGridDimmed: Bool = false,
        backgroundColor: Color = DSColor.Background.card,
        surfaceClip: AnyShape = AnyShape(RoundedRectangle(cornerRadius: DSRadius.xl4)),
        @ViewBuilder content: () -> Content
    ) {
        self.showsDotGrid = showsDotGrid
        self.dotGridDimmed = dotGridDimmed
        self.backgroundColor = backgroundColor
        self.surfaceClip = surfaceClip
        self.content = content()
    }

    public var body: some View {
        ZStack {
            // E24.26: de kaart-surface + het dot-grid clippen naar de frame-vorm
            // (`surfaceClip`). Bij een cirkel is buiten de cirkel dus niets meer
            // (transparant) → de window-bg (zwart) schijnt door, géén lichter
            // vierkant. Bij square = de normale afgeronde kaart.
            ZStack {
                backgroundColor
                if showsDotGrid {
                    // E24.29: tijdens transformeren (onderwerp geselecteerd) dimt
                    // het dot-grid zodat de uitlijn-gids + handles eruit springen en
                    // de canvas minder druk oogt. In rust staat het op vol.
                    DSDotGrid()
                        .opacity(dotGridDimmed ? 0.35 : 1)
                        .animation(DSMotion.fast, value: dotGridDimmed)
                }
            }
            .clipShape(surfaceClip)

            content
        }
        // Vast vierkant (E03.14, bevinding 11): het canvas is het
        // exportformaat (1:1); de inhoud vult de kaart (aspect-fill door
        // de caller).
        .aspectRatio(1, contentMode: .fit)
        // Buitenste clip = de kaartvorm zodat overlays (gids/handles) binnen het
        // canvas blijven; de surface zelf is al naar `surfaceClip` geclipt.
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
