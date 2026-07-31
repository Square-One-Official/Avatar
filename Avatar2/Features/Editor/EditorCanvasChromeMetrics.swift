// Canvas-layout voor de portret-editor: kaart covert het venster;
// camera-fit zorgt dat frame + naam-chip bij openen in beeld passen.

import CoreGraphics

enum EditorCanvasChromeMetrics {

    struct Layout: Equatable {
        let cardSide: CGFloat
        let origin: CGPoint

        var cardCenter: CGPoint {
            CGPoint(x: origin.x + cardSide / 2, y: origin.y + cardSide / 2)
        }
    }

    /// Kaart vult het venster (cover): geen witte randen links/rechts.
    static func coverLayout(viewport: CGSize) -> Layout {
        let side = max(viewport.width, viewport.height)
        return Layout(
            cardSide: side,
            origin: CGPoint(
                x: (viewport.width - side) / 2,
                y: (viewport.height - side) / 2
            )
        )
    }
}
