// Canvas-camera (E27.1) — de viewport-transform over de HELE canvas-scène
// (kaart + achtergrond + onderwerp), zoals Framer/Figma. Eén `scale` + `offset`
// die in `EditorView` als `.scaleEffect(anchor: .center).offset()` op de
// DSCanvasCard hangt. Dit is VIEW-zoom (wat je ziet), NIET het ONDERWERP
// schalen — dat blijft de selectie-handle-math in EditorCanvasView (E24).
//
// Vervangt de mislukte per-onderwerp `viewZoom` uit E24.8/24.17.

import CoreGraphics

/// De viewport-transform. `scale` is geclampt op 0.25×–4×; `offset` verschuift
/// de scène (in viewport-punten, top-left origin = SwiftUI-conventie).
struct CanvasCamera: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero
    /// Zoomgrenzen — instance zodat de editor (0.25–4×) en de board (E27.4, mag
    /// verder uitzoomen om de hele set te tonen) hun eigen band kunnen kiezen.
    var minScale: CGFloat = 0.25
    var maxScale: CGFloat = 4

    func clampScale(_ s: CGFloat) -> CGFloat {
        min(maxScale, max(minScale, s))
    }

    /// ⌘0 (fit): terug naar de basislayout (scène vult de kaart, geen pan).
    mutating func reset() {
        scale = 1
        offset = .zero
    }

    /// E27.4: fit-to-content — past de zoom zo aan dat een gecentreerde inhoud
    /// van `contentSize` binnen `viewport` past (met marge), en centreert (offset
    /// 0, want de board-grid is al door `.frame(maxWidth/Height:.infinity)`
    /// gecentreerd). Geclampt aan de zoomband.
    mutating func fitToContent(contentSize: CGSize, in viewport: CGSize, padding: CGFloat = 0.9) {
        guard contentSize.width > 0, contentSize.height > 0,
              viewport.width > 0, viewport.height > 0 else { reset(); return }
        let raw = min(viewport.width / contentSize.width, viewport.height / contentSize.height) * padding
        scale = clampScale(raw)
        offset = .zero
    }

    /// Zoom rond een vast PUNT (cursorlocatie in viewport-punten) zodat het punt
    /// onder de cursor stil blijft staan. Gebruikt door ⌘-scroll/magnify in de
    /// NSEvent-catcher. Afleiding: met scherm = midden + scale·(p−midden) + offset
    /// volgt offset₁ = v·(1−r) + r·offset₀ met v = punt − midden, r = scale₁/scale₀.
    mutating func zoom(by factor: CGFloat, around point: CGPoint, in size: CGSize) {
        let newScale = clampScale(scale * factor)
        guard size.width > 0, size.height > 0, newScale != scale else {
            scale = newScale
            return
        }
        let r = newScale / scale
        let vx = point.x - size.width / 2
        let vy = point.y - size.height / 2
        offset.width = vx * (1 - r) + r * offset.width
        offset.height = vy * (1 - r) + r * offset.height
        scale = newScale
    }

    /// Zoom rond het MIDDEN van de viewport (pinch, ⌘+/⌘−, en ⌘1 → 100%). Het
    /// middenpunt blijft vast: offset schaalt mee met de zoomverhouding.
    mutating func zoomCentered(by factor: CGFloat) {
        let newScale = clampScale(scale * factor)
        guard newScale != scale else { return }
        let r = newScale / scale
        offset.width *= r
        offset.height *= r
        scale = newScale
    }

    /// ⌘0 (100%): zet de zoom terug op 1× én centreert de scène (pan = 0). In
    /// dit camera-model is 1× tegelijk de fit-schaal — een pixel-echte 100%
    /// vraagt de bron-pixelmaat en hoort bij 27.2/27.3. Recenteren is een
    /// expliciete wens (anders blijft een verschoven canvas off-center staan).
    mutating func resetToActualSize() {
        scale = 1
        offset = .zero
    }
}
