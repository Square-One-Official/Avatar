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
- status: done
- owner: AI/INFRA (2026-06-26)
- verified: 2026-07-02 — DoD opnieuw groen op v2-main ná de E37.19-merge (Halftone-intensity):
  `swift test` AvatarKit 89/89 + AvatarUI 37/37, `xcodebuild test -scheme Avatar2` 119 tests
  (1 skipped, 0 failures) incl. 6× `ShaderEffectTests`. Board-rij E38 stond nog op "38.1 ready"
  (stale) en is gelijkgetrokken met dit epic-bestand; geen codewijziging nodig.
- note: Metal Toolchain (17E188, ~688 MB) geïnstalleerd via `xcodebuild -downloadComponent
  MetalToolchain` (Thierry akkoord 2026-06-26) → `.metal` compileert. Deblokkeerde 38.x + 37.7.
- team: AI/INFRA
- Result: `Avatar2/Features/Banners/BannerShaders.metal` — 6 `[[stitchable]]` shaders met gedeelde
  helpers (hash/valueNoise/fbm/Bayer/luma): color-effects **grain**, **noise** (fBm-overlay),
  **dither** (ordered Bayer), **halftone**; distortion-effects **lens** (barrel/pincushion) en
  **warp** (sinus). `ShaderEffect.swift` — value-model (`ShaderParam`, `ShaderArg` [.bounds /
  .param], `ShaderEffect` met `stage` color/distortion + geordende arg-spec die 1-op-1 matcht met
  de Metal-signatuur) + `ShaderCatalog.all` + `View.bannerShaders(_:)` die de ingeschakelde lagen
  in volgorde via `.colorEffect`/`.distortionEffect(maxSampleOffset:)` stapelt; args via
  `.boundingRect`/`.float`. `BannerShaderLayer` (E37.1) blijft het persistente model;
  `effect.makeLayer()` levert defaults. macOS 14+ Shader-API = app-deploymenttarget, geen gate
  nodig. `ShaderEffectTests` (3, groen): catalogus/laag-consistentie + élke shader rendert via
  `ImageRenderer` een beeld van de juiste maat + disabled-laag wordt overgeslagen. DoD groen
  (build-v2.sh "alles groen"; 7/7 Avatar2-tests).

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
- status: done
- owner: AI/INFRA (2026-06-26)
- team: AI/INFRA (+ FEAT-haak)
- blockedBy: 38.1
- Result: `BannerShaderRenderer.bake(_:shaders:size:)` (@MainActor) wikkelt het CPU-basisbeeld
  (`BannerDocRenderer`, fill+tekst+logo) in een SwiftUI `Image` op canvas-maat, stapelt de
  ingeschakelde shaders (`.bannerShaders`) en rastert met `ImageRenderer` terug naar CGImage; lege
  stack → basis onveranderd (geen ImageRenderer-kost). `BannerStudioView` heeft nu één
  `composedImage(watermark:)`-pad dat preview/save/export voedt → wat-je-ziet = wat-je-exporteert
  (de canvas toont het gebakken `preview`, niet langer een los modifier). Free-tier watermerk gaat
  via `BannerDocRenderer.stampWatermark(on:)` SCHERP bovenop de gebakken shaders (niet
  mee-vervormd). Shaders normaliseren via `.boundingRect` zodat preview- en exportmaat consistent
  zijn. DoD groen.

Haak de shader-stack in de `BannerDoc`-render: live op de Studio-canvas-kaart (gestapelde
modifiers in z-volgorde) én in `BannerDocRenderer`/`ImageRenderer` bij export, zodat wat-je-ziet
= wat-je-exporteert. Performantie: coalesce/debounce param-updates (zoals de 12 ms color-preview)
en render off-main.
- DoD: beide targets bouwen, tests groen, Result-regel.

## 38.3 — Param-controls (DS) + per-shader panel-UI
- status: done
- owner: DS+FEAT (2026-06-26)
- team: DS (+ FEAT)
- blockedBy: 38.1
- Result: `BannerShaderPanel` (in `DSEditPanel`): een horizontale catalogus-rij van effect-chips
  (icoon + naam) om toe te voegen, daaronder per actieve laag een kaart met generieke DS-`Slider`s
  gedreven door `ShaderEffect.params` (label + range uit de catalogus, dict-binding op
  `BannerShaderLayer.params`). Bindt op een lokale `@State`-werk-kopie (zoals het text-paneel) →
  vloeiende sliders; `onChange` schrijft terug naar `doc.layers.shaders` → live canvas-bake
  (E38.2). Polish (2026-06-26): elke catalogus-chip toont nu een **live preview-thumbnail** —
  een representatief mini-staal (gradient + vormen) met de shader (default-params) er live op via
  `.bannerShaders`, zodat je het effect ziet vóór toevoegen. DoD groen.

DS-controls voor shader-parameters (sliders/segments/color in AvatarUI-stijl, reduce-motion-
proof), generiek gedreven door `ShaderEffect.params`. Een effect-kaartenrij (kies shader) +
param-sheet eronder — patroon = `EffectsPanel` + Figma-shader-paneel. Live preview-thumbnails per
shader.
- DoD: beide targets bouwen, tests groen, Result-regel.

## 38.4 — Shader-stacking/ordening
- status: done
- owner: FEAT (2026-06-26)
- team: FEAT
- blockedBy: 38.2, 38.3
- Result: `BannerShaderPanel` stapelt meerdere shaders op één banner; per laag: aan/uit (oog-toggle
  + dim-opacity), verwijderen (trash), en herordenen via omhoog/omlaag (`swapAt`, eind-disabled).
  De volgorde van `doc.layers.shaders` = de z-volgorde waarin `View.bannerShaders` ze toepast
  (eerste laag eerst), dus herordenen verandert het render-resultaat. DoD groen.

Meerdere shaders stapelen op één banner, met herordenen/aan-uit/verwijderen (Figma stackt
effecten). UI in de Shaders-tool (E37.7). Volgorde respecteert z-stack in de render.
- DoD: beide targets bouwen, tests groen, Result-regel.
