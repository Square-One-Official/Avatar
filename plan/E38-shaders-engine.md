# E38 — Shaders-engine (Figma-stijl procedurale effecten)

Team: **AI/INFRA** (Metal-shaderbibliotheek + render-haak) · **DS** (param-controls) · **FEAT**
(panel-integratie in de Studio, zie E37.7)

Voortgekomen uit feedback (Thierry, 2026-06-26): "ik zou graag shaders zoals Figma willen" —
fractal noise, dithering, mesh-gradients, lens distortion, warp — als effect toepasbaar op een
banner. Referentie: Figma "Use shaders in designs" (shader-**fills** = standalone visuals zoals
patronen/noise/mesh-gradients/procedurale achtergronden; shader-**effects** = bewerken de huidige
pixels, bv. color-shift/distortie/grain/halftone; effecten zijn stapelbaar; "Clip to shape"
bevat een textuur binnen de laag).

## Technische aanpak (besluit)

De codebase doet vandaag alléén Core Image (geen Metal). Voor **live, Figma-achtige** shaders is
de juiste route de **SwiftUI `Shader`-API** (macOS 14+): Metal-shaderfuncties in een
gebundelde `.metal`-library, toegepast op een view via `.colorEffect` (per-pixel kleur),
`.distortionEffect` (positie-warp) en `.layerEffect` (sampling van de hele laag — nodig voor
dithering/halftone/lens). Live op canvas; bij **export** rasteren via `ImageRenderer` (de
shader-modifiers renderen mee). Géén Replicate/cloud — dit is lokaal/gratis en realtime.

- **Fill-shaders** (genereren beeld): mesh-gradient, fractal noise. → `.colorEffect` op een
  gevulde rect, of een Shader-`ShapeStyle`.
- **Effect-shaders** (bewerken bestaande pixels): dithering, halftone, grain, color-shift →
  `.colorEffect`/`.layerEffect`; lens distortion, warp → `.distortionEffect`.

**Design-uitgangspunt:** géén Figma 1-op-1; params + UI **in de geest van het DS** (DS-sliders/
segments). Catalogus-presets later CMS-baar (spiegelt `RemoteEffect`), maar de shader-math is
lokaal.

---

## 38.1 — Metal-shaderbibliotheek + ShaderEffect-model
- status: blocked
- owner: AI/INFRA (2026-06-26)
- blocker: **Metal Toolchain niet geïnstalleerd.** Xcode 26.4 (MacOSX26.4 SDK) levert de
  `metal`-compiler als losse component; `.metal`-bestanden compileren niet → build faalt met
  "cannot execute tool 'metal' due to missing Metal Toolchain; use: xcodebuild -downloadComponent
  MetalToolchain". De volledige shader-engine (38.1–38.4) + de Studio-shaders-tool (E37.7) wachten
  hierop. De code was geschreven en de Swift-kant compileert; alleen het `.metal`-doel blokkeert.
  **Deblokkeren:** `xcodebuild -downloadComponent MetalToolchain` (multi-GB, Thierry's keuze).
  Daarna: herplaats BannerShaders.metal + ShaderEffect + BannerShaderModifier (uit deze sessie) en
  bouw verder.
- team: AI/INFRA

- `.metal`-library met de kern-shaderfuncties (parametrisch): **fractalNoise** (fBm/Perlin,
  octaves/schaal/kleurmap), **dither** (ordered/Bayer + drempel + paletgrootte), **meshGradient**
  (N kleur-stops op een grid → vloeiende interpolatie), **lensDistortion** (barrel/pincushion,
  center+sterkte), **warp** (sinus/displacement, amplitude/frequentie), plus **grain** en
  **halftone** als bonus (zelfde patroon). Gebundeld in het Avatar2-target (Metal-resource).
- `ShaderEffect` value-model: `key` (stabiel), `displayName`, `kind` (fill/effect),
  `params: [ShaderParam]` (naam, range, default, type slider/segment/color). `Codable` zodat het
  in `BannerDoc.shaderLayers` (E37.1) past.
- SwiftUI-wrappers: een `bannerShader(_:params:)`-view-modifier die de juiste
  `.colorEffect/.distortionEffect/.layerEffect` kiest op basis van `kind`.
- **macOS-versie-gate:** Shader-API is macOS 14+. App-deploymenttarget verifiëren; zo nodig een
  nette fallback (statische render) achter een availability-check, niet crashen.
- DoD: beide targets bouwen, een unit/snapshot-test die elke shader op een testbeeld toepast en
  een niet-leeg/juist-formaat resultaat oplevert, tests groen, Result-regel.

## 38.2 — Live shader-render op canvas + raster-bij-export
- status: backlog
- owner: —
- team: AI/INFRA (+ FEAT-haak)
- blockedBy: 38.1

Haak de shader-stack in de `BannerDoc`-render: live op de Studio-canvas-kaart (gestapelde
modifiers in z-volgorde) én in `BannerDocRenderer`/`ImageRenderer` bij export, zodat wat-je-ziet
= wat-je-exporteert. Performantie: coalesce/debounce param-updates (zoals de 12 ms color-preview)
en render off-main.
- DoD: beide targets bouwen, tests groen, Result-regel.

## 38.3 — Param-controls (DS) + per-shader panel-UI
- status: backlog
- owner: —
- team: DS (+ FEAT)
- blockedBy: 38.1

DS-controls voor shader-parameters (sliders/segments/color in AvatarUI-stijl, reduce-motion-
proof), generiek gedreven door `ShaderEffect.params`. Een effect-kaartenrij (kies shader) +
param-sheet eronder — patroon = `EffectsPanel` + Figma-shader-paneel. Live preview-thumbnails per
shader.
- DoD: beide targets bouwen, tests groen, Result-regel.

## 38.4 — Shader-stacking/ordening
- status: backlog
- owner: —
- team: FEAT
- blockedBy: 38.2, 38.3

Meerdere shaders stapelen op één banner, met herordenen/aan-uit/verwijderen (Figma stackt
effecten). UI in de Shaders-tool (E37.7). Volgorde respecteert z-stack in de render.
- DoD: beide targets bouwen, tests groen, Result-regel.
