// Gedeelde screen-rect helpers voor canvas-chrome (tekst, logo, achtergrond).

import CoreGraphics

enum BannerCanvasChromeMetrics {

    struct Layout {
        let drawn: CGSize
        let origin: CGPoint
        let scale: CGFloat
    }

    static func screenRect(canvasRect: CGRect, layout: Layout) -> CGRect {
        CGRect(
            x: layout.origin.x + canvasRect.minX * layout.scale,
            y: layout.origin.y + canvasRect.minY * layout.scale,
            width: canvasRect.width * layout.scale,
            height: canvasRect.height * layout.scale
        )
    }

    static func fullCanvasScreenRect(canvasSize: CGSize, layout: Layout) -> CGRect {
        screenRect(canvasRect: CGRect(origin: .zero, size: canvasSize), layout: layout)
    }
}
