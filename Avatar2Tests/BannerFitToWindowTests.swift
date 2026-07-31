// UXS-6 (UX2) — de Banner-Studio-canvas moet in het venster passen.
//
// De audit-klacht: bij openen viel de 1500×500-banner buiten een 1100×760-
// venster en was er geen zoom-UI. `fitCameraScale` is de camera-schaal die de
// studio bij openen, bij venster-resize en op ⌘0/de chip toepast; deze suite
// borgt dat die schaal de banner écht binnen de viewport brengt — op de twee
// venstermaten uit het audit-protocol.

import CoreGraphics
import Testing
@testable import Avatar2

@Suite struct BannerFitToWindowTests {

    /// De hoogte-marge die de fit aanhoudt (selectie-handles + chrome).
    private static let fitPadding: CGFloat = 0.94

    private func fittedSize(canvas: CGSize, viewport: CGSize) -> CGSize {
        let drawn = BannerCanvasChromeMetrics.fitLayout(
            canvasSize: canvas,
            viewport: viewport,
            horizontalPadding: 0
        ).drawn
        let scale = BannerCanvasChromeMetrics.fitCameraScale(
            canvasSize: canvas,
            viewport: viewport
        )
        return CGSize(width: drawn.width * scale, height: drawn.height * scale)
    }

    @Test func defaultBannerFitsBreedVenster() {
        let canvas = CGSize(width: 1500, height: 500)
        let viewport = CGSize(width: 1100, height: 760)
        let fitted = fittedSize(canvas: canvas, viewport: viewport)

        #expect(fitted.width <= viewport.width)
        #expect(fitted.height <= viewport.height)
    }

    @Test func defaultBannerFitsSmalVenster() {
        let canvas = CGSize(width: 1500, height: 500)
        let viewport = CGSize(width: 820, height: 620)
        let fitted = fittedSize(canvas: canvas, viewport: viewport)

        #expect(fitted.width <= viewport.width)
        #expect(fitted.height <= viewport.height)
    }

    /// LinkedIn-formaat (1584×396) is extremer breed — juist die moet passen.
    @Test func extraBredeBannerFitsOok() {
        let canvas = CGSize(width: 1584, height: 396)
        for viewport in [CGSize(width: 1100, height: 760), CGSize(width: 820, height: 620)] {
            let fitted = fittedSize(canvas: canvas, viewport: viewport)
            #expect(fitted.width <= viewport.width)
            #expect(fitted.height <= viewport.height)
        }
    }

    /// De fit laat bewust marge over — anders raken selectie-handles de rand.
    @Test func fitLaatMargeOver() {
        let viewport = CGSize(width: 1100, height: 760)
        let fitted = fittedSize(canvas: CGSize(width: 1500, height: 500), viewport: viewport)
        let usedWidthFraction = fitted.width / viewport.width
        #expect(usedWidthFraction <= Self.fitPadding + 0.001)
    }

    /// Een vierkante banner is hoogte-gebonden i.p.v. breedte-gebonden; ook die
    /// mag niet buiten beeld vallen.
    @Test func vierkanteBannerIsHoogteGebonden() {
        let viewport = CGSize(width: 1100, height: 760)
        let fitted = fittedSize(canvas: CGSize(width: 1000, height: 1000), viewport: viewport)
        #expect(fitted.height <= viewport.height)
        #expect(fitted.width <= viewport.width)
    }

    /// Vóór de eerste layout is de viewport 0×0 — dat mag geen NaN of 0-schaal
    /// opleveren waarmee de canvas onzichtbaar wordt.
    @Test func legeViewportGeeftVeiligeSchaal() {
        let scale = BannerCanvasChromeMetrics.fitCameraScale(
            canvasSize: CGSize(width: 1500, height: 500),
            viewport: .zero
        )
        #expect(scale == 1)
    }
}
