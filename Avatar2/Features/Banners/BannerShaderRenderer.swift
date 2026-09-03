// E38.2 — Rastert de GPU-shader-stack IN het banner-beeld. `BannerDocRenderer`
// componeert fill+tekst+logo op de CPU (CGContext) tot een basis-CGImage; de
// SwiftUI `Shader`-API draait echter op een view. Deze @MainActor-helper wikkelt
// het basisbeeld in een SwiftUI `Image` op canvas-maat, stapelt de ingeschakelde
// shader-lagen erop (`.bannerShaders`) en rastert het geheel met `ImageRenderer`
// terug naar een CGImage — zodat wat-je-ziet (Studio-canvas) = wat-je-exporteert.
// Géén shaders → het basisbeeld wordt ongemoeid teruggegeven (geen ImageRenderer-
// kost).

import SwiftUI
import CoreGraphics

@MainActor
enum BannerShaderRenderer {
    /// Bakt de ingeschakelde shader-lagen in `base` (gerenderd op `size`). Lege/
    /// uitgeschakelde stack → `base` onveranderd. nil als de rasterisatie faalt.
    static func bake(_ base: CGImage, shaders: [BannerShaderLayer], size: CGSize) -> CGImage? {
        let active = shaders.filter(\.enabled)
        guard !active.isEmpty else { return base }
        let view = Image(decorative: base, scale: 1.0)
            .resizable()
            .frame(width: size.width, height: size.height)
            .bannerShaders(active)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        return renderer.cgImage ?? base
    }
}
