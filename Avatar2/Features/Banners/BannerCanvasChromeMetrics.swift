// Gedeelde screen-rect helpers voor canvas-chrome (tekst, logo, achtergrond).
// Camera-mapping volgt het portret-editor-patroon (E27): scherm = midden +
// camera.scale × (lokaal − midden) + offset.

import CoreGraphics
import SwiftUI

enum BannerCanvasChromeMetrics {

    static let maxCardWidth: CGFloat = 1100

    struct Layout {
        let drawn: CGSize
        let origin: CGPoint
        /// Fit-schaal: banner-canvas-pixels → lokale punten vóór camera.
        let scale: CGFloat
        let viewportSize: CGSize
        var camera: CanvasCamera

        var cardCenter: CGPoint {
            CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        }

        /// Totale schaal canvas-pixels → scherm (fit × camera).
        var canvasScale: CGFloat { scale * camera.scale }

        func mapLocalToScreen(_ local: CGPoint) -> CGPoint {
            let c = cardCenter
            return CGPoint(
                x: c.x + camera.scale * (local.x - c.x) + camera.offset.width,
                y: c.y + camera.scale * (local.y - c.y) + camera.offset.height
            )
        }

        func mapScreenToLocal(_ screen: CGPoint) -> CGPoint {
            let c = cardCenter
            guard camera.scale > 0 else { return screen }
            return CGPoint(
                x: c.x + (screen.x - c.x - camera.offset.width) / camera.scale,
                y: c.y + (screen.y - c.y - camera.offset.height) / camera.scale
            )
        }

        func screenToCanvas(_ screen: CGPoint) -> CGPoint {
            let local = mapScreenToLocal(screen)
            guard scale > 0 else { return .zero }
            return CGPoint(
                x: (local.x - origin.x) / scale,
                y: (local.y - origin.y) / scale
            )
        }

        /// `UnitPoint` voor `.scaleEffect` op de banner-kaart zodat zoom rond het
        /// viewport-midden loopt — identiek aan `mapLocalToScreen`.
        func cameraScaleAnchor(cardFrame: CGRect) -> UnitPoint {
            let c = cardCenter
            guard cardFrame.width > 0, cardFrame.height > 0 else { return .center }
            return UnitPoint(
                x: (c.x - cardFrame.minX) / cardFrame.width,
                y: (c.y - cardFrame.minY) / cardFrame.height
            )
        }
    }

    /// Fit-layout: banner gecentreerd in de viewport (zelfde maten als de kaart).
    static func fitLayout(
        canvasSize: CGSize,
        viewport: CGSize,
        maxCardWidth: CGFloat = maxCardWidth,
        horizontalPadding: CGFloat = 32,
        camera: CanvasCamera = CanvasCamera()
    ) -> Layout {
        let aspect = canvasSize.width / max(1, canvasSize.height)
        var w = min(maxCardWidth, max(1, viewport.width - horizontalPadding * 2))
        var h = w / aspect
        let maxH = viewport.height * 0.92
        if h > maxH {
            h = maxH
            w = h * aspect
        }
        let drawn = CGSize(width: w, height: h)
        let scale = w / max(1, canvasSize.width)
        let origin = CGPoint(
            x: (viewport.width - drawn.width) / 2,
            y: (viewport.height - drawn.height) / 2
        )
        return Layout(
            drawn: drawn,
            origin: origin,
            scale: scale,
            viewportSize: viewport,
            camera: camera
        )
    }

    /// Camera-schaal van de fit-stand (Studio-open, venster-resize, ⌘0 en de
    /// zoom-chip, UXS-6): de banner-kaart (`fitLayout`-drawn) op `padding` van
    /// de viewport — de marge houdt selectie-handles en chrome vrij. Dit is ook
    /// het 100%-anker van het chip-percentage (fit = 100%).
    static func fitCameraScale(
        canvasSize: CGSize,
        viewport: CGSize,
        padding: CGFloat = 0.94
    ) -> CGFloat {
        guard viewport.width > 0, viewport.height > 0 else { return 1 }
        let drawn = fitLayout(canvasSize: canvasSize, viewport: viewport, horizontalPadding: 0).drawn
        var camera = CanvasCamera()
        camera.fitToContent(contentSize: drawn, in: viewport, padding: padding)
        return max(camera.scale, 0.0001)
    }

    static func screenRect(canvasRect: CGRect, layout: Layout) -> CGRect {
        let localTL = CGPoint(
            x: layout.origin.x + canvasRect.minX * layout.scale,
            y: layout.origin.y + canvasRect.minY * layout.scale
        )
        let localBR = CGPoint(
            x: layout.origin.x + canvasRect.maxX * layout.scale,
            y: layout.origin.y + canvasRect.maxY * layout.scale
        )
        let screenTL = layout.mapLocalToScreen(localTL)
        let screenBR = layout.mapLocalToScreen(localBR)
        return CGRect(
            x: screenTL.x,
            y: screenTL.y,
            width: screenBR.x - screenTL.x,
            height: screenBR.y - screenTL.y
        )
    }

    static func fullCanvasScreenRect(canvasSize: CGSize, layout: Layout) -> CGRect {
        screenRect(canvasRect: CGRect(origin: .zero, size: canvasSize), layout: layout)
    }
}
