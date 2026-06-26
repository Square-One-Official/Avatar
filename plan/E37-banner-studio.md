# E37 — Banner Studio (editor)

Team: **FEAT** (canvas + panels) · **INFRA** (BannerDoc-model/container/render) · **DS** (nieuwe
editor-chrome-componenten in AvatarUI)

Voortgekomen uit feedback (Thierry, 2026-06-26): "make banner" leidt naar een echte **banner-
editor** met een **onderste toolbar zoals bij Portraits**, maar simpeler en toegespitst op
banners. De Studio is een eigen sectie/overlay met een canvas-kaart en een capsule-toolbar.

## UX-onderzoek — welke tools heeft een banner-editor nodig?

Onderzocht tegen de toonaangevende cover/banner-makers (GoDaddy Studio, Canva, Picsart,
Photoroom, Unfold) — die delen allemaal een **onderste tool-toolbar**: Image · Text ·
Graphic/Element · Shape · Effects · Theme/Brand
([GoDaddy Studio](https://mobbin.com/screens/2f5ebbd6-3afb-4e70-b65a-2dd59582bda6),
[Picsart](https://mobbin.com/screens/d94f36bc-8dc1-424d-b02e-99f85355b322),
[Photoroom](https://mobbin.com/screens/deab17a7-1104-49f4-b8de-b6579effb29f),
[Unfold](https://mobbin.com/screens/8a6283d2-5cbb-46b2-9845-12dfab3b5d3d),
[Spotify cover-art Effects](https://mobbin.com/screens/b5b2282c-6f23-4145-9518-d9711dc5e31c)).

**Besluit (toegespitst, géén bloat — de minimale set voor een mooie banner):**
1. **Background / Fill** — solid (brand-kleuren + picker), mesh-gradient, **generate image** (AI,
   gefaseerd), **upload image**, of **use a portrait** (E40 omgekeerd: een avatar als element).
2. **Shaders** — procedurale Figma-stijl effecten als laag/effect (fractal noise, dithering,
   mesh-gradient, lens distortion, warp, grain, halftone). Eigen engine = **E38**.
3. **Text** — tekstblok toevoegen/bewerken: inhoud, font(-familie), grootte, gewicht, kleur,
   uitlijning, letter-/regelafstand.
4. **Logo / Brand** — een logo/merkbeeld plaatsen (upload, schalen/positioneren) + brand-
   kleurenpalet (`BrandColorKit`).
5. **Size / Layout** — platform-maatpresets (LinkedIn 1584×396, X 1500×500, generiek wijd) +
   uitlijn-/positiehulp.

Bewust **niet** in de MVP (om slop/bloat te vermijden): vrije vormen/stickers-bibliotheek,
video, filters-op-foto's. Kunnen later als "Elements".

**Design-uitgangspunt:** géén 1-op-1 Figma-ref (scherm bestaat niet in Figma). Bouw de toolbar
**in de geest van de portret-editor** — `DSEditPanelContainer` + `DSToolbarItem`/capsule
(`EditorView.toolbarItems`-patroon), `DSCanvasCard`, `DSEditPanel`, DS-tokens. Eenvoudiger dan de
portret-toolbar (minder tools, geen Enhance/Face/Hair/Shirt).

---

## 37.1 — BannerDoc-model + container + render-pijplijn
- status: done
- owner: INFRA (2026-06-26)
- team: INFRA

**Result:** `BannerDoc` @Model ([BannerDoc.swift](Avatar2/Features/Banners/BannerDoc.swift)) —
naast `Banner2`/`Portrait2`/`Folder2` in de container ([Avatar2App.swift](Avatar2/Avatar2App.swift)):
canvas-maat (default 1500×500) + een Codable laag-stack `BannerLayers` (fill: solid/meshGradient/
image · `[BannerTextLayer]` · `BannerLogoLayer?` · forward-compat `[BannerShaderLayer]` voor E38)
als externalStorage-JSON, met zware beeld-bytes (`fillImageData`/`logoImageData`/`previewImageData`)
als losse externalStorage-blobs. `BannerDoc.from(banner2:)` opent een platte E35-`Banner2` als één
image-fill-laag (geen dataverlies). [BannerDocRenderer](Avatar2/Features/Banners/BannerDocRenderer.swift)
componeert fill (via `BannerCompositor`, linear-sRGB) + logo + tekst (CoreText `CTLine`) tot een
ondoorzichtige wijde CGImage; `size`-override voor exportmaten; shaders-haak gereserveerd voor E38.2.
3 unit-tests (fill+tekst → opake 1500×500 PNG; export-maat-override 1584×396; Banner2-migratie
behoudt bytes) groen; volledige DoD groen (Avatar + Avatar2 + AvatarKit + AvatarUI).

Vervang het "platte beeld"-model door een **bewerkbaar, herbruikbaar document** (de editor moet
heropenen):
- `BannerDoc` @Model in `Avatar2/Features/Banners/` met: `name`, `createdAt`, `updatedAt`,
  `touch()`, canvas-`size` (default 1500×500), en een serialiseerbare **laag-stack**:
  - `fill` (solid-hex / mesh-gradient-stops / image-data / generated-image-ref),
  - `[textLayer]` (string, font, size, weight, colorHex, align, x/y, rotation),
  - `logoLayer?` (image-data, x/y, scale),
  - `[shaderLayer]` (shader-key + params — zie E38),
  - z-volgorde.
  Lagen als `Codable` value-types in één `@Attribute(.externalStorage)` JSON-blob + losse
  externalStorage voor zware image-bytes; plus een gecachte **`previewImageData`** (gerenderde
  wijde PNG) voor thumbnails/social-preview-compat.
- Registreer in de app-`modelContainer` ([Avatar2App.swift](Avatar2/Avatar2App.swift)) náást
  Portrait2/Folder2/Banner2 (lichtgewicht migratie). **Migratiepad:** bestaande `Banner2`
  (platte upload/gradient-banners) blijven leesbaar; bied "open in Studio" door ze als één
  image-fill-laag in te laden (geen dataverlies).
- `BannerDocRenderer.render(_:size:) -> CGImage` (off-main) die de laag-stack → wijde PNG
  componeert via het bestaande `BannerCompositor`-pad (linear-sRGB, aspect-fill). Shaders worden
  in 37.7/E38 in deze render gehaakt.
- DoD: beide targets bouwen, unit-test op render (fill + tekstlaag → opake PNG van juiste maat),
  tests groen, Result-regel.

## 37.2 — Studio-shell: canvas-kaart + onderste capsule-toolbar
- status: done
- owner: FEAT (2026-06-26)
- team: FEAT (+ DS voor nieuwe chrome)
- blockedBy: 37.1

**Result:** [BannerStudioView](Avatar2/Features/Banners/BannerStudioView.swift) — venster-niveau
crossfade-overlay (zoals de social-preview) op één `BannerDoc`, gewired via
`ShellModel.editingBanner`/`openBannerStudio`/`closeBannerStudio` + een `.overlay` in
[ShellView](Avatar2/Features/Shell/ShellView.swift). Topbar = Close · gecentreerd naam-veld
(rename) · Save (rendert preview-cache via `BannerDocRenderer`). Onderste capsule-toolbar via
`DSEditPanelContainer` met `BannerTool` **Background · Shaders · Text · Logo · Size**; elk opent
een `DSEditPanel`-plaatshouder (37.3–37.7 vullen ze). Live wijde canvas-kaart toont de
`BannerDocRenderer`-render. [BannersGalleryView](Avatar2/Features/Banners/BannersGalleryView.swift)
is nu `BannerDoc`-backed: "Make banner" → nieuw doc + Studio, tegel-klik opent het doc,
Rename/Duplicate/Delete op `BannerDoc`. **Bewuste DS-afwijking:** `DSCanvasCard` is 1:1-
vergrendeld → de wijde canvas is een DS-token-kaart (Background.card/xl4). **Compat-noot:** de
social-preview `BannerChooser` leest nog `Banner2`; reconciliatie → 37.6. DoD groen (Avatar +
Avatar2 + AvatarKit + AvatarUI), 3 BannerDocRenderTests groen.

De editor-romp:
- Nieuwe sectie/overlay (analoog aan `EditorView`/`SocialPreviewView` op shell-niveau):
  `ShellModel.openBanner(_:)` / `showBannerStudio` + routing in `ShellView`.
- **Canvas-kaart** (`DSCanvasCard`) toont de live `BannerDoc`-render op canvas-maat, met
  selecteerbare lagen (tap-to-select, sleep om te verplaatsen) en zoom-to-fit.
- **Onderste capsule-toolbar** in de geest van de portret-editor (`DSEditPanelContainer` +
  capsule-items): **Background · Shaders · Text · Logo · Size**. Elk item opent een `DSEditPanel`
  onderaan. Eenvoudiger gestyled dan de portret-toolbar.
- Topbar: titel/naam (rename), Close (terug naar herkomst — gallery of home, breadcrumb-patroon),
  en Save/Done (rendert preview-cache, schrijft `BannerDoc`).
- Undo/redo via het bestaande `ReversibleChange`-patroon.
- **Geen Figma-ref** — DS-tokens; toolbar-patroon = portret-editor, vereenvoudigd.
- DoD: beide targets bouwen, tests groen, Result-regel.

## 37.3 — Background/Fill-panel
- status: done
- owner: FEAT (2026-06-26)
- team: FEAT
- blockedBy: 37.2

**Result:** [BannerBackgroundPanel](Avatar2/Features/Banners/BannerBackgroundPanel.swift) — zet `BannerDoc.fill`: Color-rij (`DSColorPicker` + `BackgroundKit.colorPresets` + `BrandColorKit`-kleuren, geselecteerde swatch krijgt een ring), Gradient-rij (`BackgroundKit.gradientPresets` → `.meshGradient`-stops), Image-rij (Upload via NSOpenPanel + `BackgroundKit.downscaledPNG` → `.image`; Generate = disabled stub "coming soon"). Mutaties via `doc.layers`/`fillImageData` → `touch()` → live canvas-her-render. Gewired in `BannerStudioView.panel(.background)`. DoD groen.

`DSEditPanel` "Background": solid-kleur (brand-kleuren uit `BrandColorKit` + `DSColorPicker`),
mesh-gradient (meerdere stops; deelt de mesh-shader uit E38 of een nette gradient-fallback),
**Upload image** (NSOpenPanel, downscale/cache zoals `BackgroundImageKit`), en een **Generate
image**-knop (gated; wired op de banner-generatie zodra E34.8/34.9 of een nieuwe AI-story
landt — tot dan een nette disabled/Pro-stub). Schrijft `BannerDoc.fill`, undo'baar.
- **Geen Figma-ref** — DS-tokens; patroon = `BackgroundPanel`.
- DoD: beide targets bouwen, tests groen, Result-regel.

## 37.4 — Text-panel
- status: done
- owner: FEAT (2026-06-26)

**Result:** [BannerTextPanel](Avatar2/Features/Banners/BannerTextPanel.swift) — "Add text" + per-laag kaart: inhoud (TextField), grootte (slider 24–240), gewicht (Menu Regular/Medium/Semibold/Bold), kleur (`DSColorPicker`), verticale plaatsing (top/midden/onder → y), verwijderen. Mutaties via `doc.layers.texts` → `touch()` → live canvas (CoreText). Gewired in `BannerStudioView.panel(.text)`. Follow-up (wanneer de canvas laag-sleep + meerregelige render krijgt): font-familie, letter-/regelafstand, horizontale uitlijning. DoD groen.
- team: FEAT (+ DS indien nieuw text-control-component)
- blockedBy: 37.2

Tekstlagen: toevoegen/bewerken/verwijderen; inhoud, font-familie (systeemfonts; brand-font
later), grootte, gewicht, kleur (brand + picker), uitlijning, letter-/regelafstand. Live op
canvas (sleep/positioneer), `DSTextField` voor invoer, undo'baar. Render via CoreText in
`BannerDocRenderer` (spiegelt het watermerk-`CTLine`-pad in `PortraitExporter`).
- **Geen Figma-ref** — DS-tokens; patroon = tekst-edit ([Photoroom text](https://mobbin.com/screens/aaad7e92-d1cb-49b0-a9d0-d3966e03d5b7)).
- DoD: beide targets bouwen, tests groen, Result-regel.

## 37.5 — Logo/Brand-panel
- status: done
- owner: FEAT (2026-06-26)

**Result:** [BannerLogoPanel](Avatar2/Features/Banners/BannerLogoPanel.swift) — Logo: upload PNG (NSOpenPanel + downscale) → `doc.logoImageData` + `layers.logo`; schaal-slider (0.08–0.6), 3×3 plaatsings-grid (x/y), verwijderen. Brand colors: `BrandColorKit`-palet (swatches + `DSColorPicker` om toe te voegen). Live canvas-render via `BannerDocRenderer` (logo aspect-correct geschaald). Gewired in `BannerStudioView.panel(.logo)`. DoD groen.
- team: FEAT
- blockedBy: 37.2

Een logo/merkbeeld plaatsen: upload (PNG met alpha), schalen/positioneren op canvas, verwijderen;
+ brand-kleurenpalet-beheer (`BrandColorKit`, eyedropper) gedeeld met Background/Text. Undo'baar.
- **Geen Figma-ref** — DS-tokens; patroon = Brand Kit ([Unfold](https://mobbin.com/screens/c89383b7-fa06-4ae0-ac97-f728b7d9cba3)).
- DoD: beide targets bouwen, tests groen, Result-regel.

## 37.6 — Size/Layout-presets + export + social-preview-compat
- status: done
- owner: FEAT (2026-06-26)

**Result:** [BannerSizePanel](Avatar2/Features/Banners/BannerSizePanel.swift) — platform-maatpresets (X 1500×500, LinkedIn 1584×396, Wide 1600×500) zetten `doc.canvasSize` non-destructief (genormaliseerde tekst/logo-posities overleven). Export-knop in de Studio-topbar → `BannerDocRenderer.render(watermark: !isPro)` → NSSavePanel-PNG (free-tier hoek-watermerk "Made with Aaavatar" via nieuwe `drawWatermark`). Social-preview-compat: [BannerChooser](Avatar2/Features/SocialPreview/BannerChooser.swift) leest nu `BannerDoc.previewImageData` i.p.v. `Banner2` — banners uit de Studio verschijnen in de preview-kiezer. DoD groen.
- team: FEAT
- blockedBy: 37.2, 37.3

- "Size"-panel: platform-maatpresets (`SocialPlatform`: LinkedIn 1584×396, X 1500×500, generiek
  wijd); wisselen herschaalt het canvas non-destructief.
- Export: `BannerDocRenderer` → wijde PNG op exacte covermaat via `BannerCompositor`; NSSavePanel
  met platform-bestandsnamen; free-tier hoek-watermerk (hergebruik `PortraitExporter`-pad).
- Social-preview-compat: vul/ververs `BannerDoc.previewImageData` zodat `BannerChooser`
  (E35.4) en `BannerResolver` opgeslagen banners onveranderd kunnen tonen/kiezen.
- **Geen Figma-ref** — DS-tokens.
- DoD: beide targets bouwen, tests groen, Result-regel.

## 37.7 — Shaders-panel integratie (consumeert E38)
- status: done
- owner: FEAT (2026-06-26)
- team: FEAT
- blockedBy: 37.2, 38.2, 38.3
- Result: de "Shaders"-tool in `BannerStudioView.panel()` toont nu het echte `BannerShaderPanel`
  (E38.3/38.4) i.p.v. de "coming soon"-kaart: kies/stapel procedurale effecten op de `BannerDoc`,
  live op de canvas via de gebakken preview (E38.2), params via DS-sliders, stack-ordening via
  omhoog/omlaag. Bij export worden de effecten via `BannerShaderRenderer` + `ImageRenderer`
  gerasterd. DoD groen.

"Shaders"-tool: kies/stapel procedurale effecten (E38) op de `BannerDoc`; live op canvas via de
SwiftUI-`Shader`-render-haak; params via de DS-controls (38.3); stack-ordening (38.4). Effecten
worden in `BannerDocRenderer` bij export gerasterd.
- **Geen Figma-ref** — DS-tokens; patroon = Effects-rij + param-sheet (Figma-shaders, Spotify
  Effects).
- DoD: beide targets bouwen, tests groen, Result-regel.

---

## 37.8 — Canvas tap-select + drag (Apple-minimal)
- status: done
- owner: FEAT (2026-06-26)
- team: FEAT
- blockedBy: 37.2

**Result:** [BannerCanvasOverlay](Avatar2/Features/Banners/BannerCanvasOverlay.swift) +
[BannerCanvasSelection](Avatar2/Features/Banners/BannerCanvasSelection.swift) +
[BannerLayoutMetrics](Avatar2/Features/Banners/BannerLayoutMetrics.swift) — tap-select tekst/logo
op de canvas-kaart, sleep om te verplaatsen, subtiele selectiering (geen handles/rotatie).
Selectie sync't met Text/Logo-panelen; Text-tool opent met eerste laag geselecteerd. DoD groen.

## 37.9 — Curated fonts + L/C/R alignment
- status: done
- owner: FEAT (2026-06-26)
- team: FEAT (+ DS `DSSegmentedControl`)
- blockedBy: 37.4, 37.8

**Result:** [BannerFontCatalog](Avatar2/Features/Banners/BannerFontCatalog.swift) (~10 system
fonts) + [BannerTextPanel](Avatar2/Features/Banners/BannerTextPanel.swift) font-menu,
`DSSegmentedControl` voor links/midden/rechts, geselecteerde laag highlight.
[BannerDocRenderer](Avatar2/Features/Banners/BannerDocRenderer.swift) respecteert `alignRaw`.
Alignment unit-test in `BannerDocRenderTests`. DoD groen.

## 37.10 — Undo/redo + Done + debounced preview bake
- status: done
- owner: FEAT (2026-06-26)
- team: FEAT
- blockedBy: 37.2

**Result:** [BannerDocUndo](Avatar2/Features/Banners/BannerDocUndo.swift) — `ReversibleChange`
voor laag-verplaatsingen + background-reframe. [BannerStudioView](Avatar2/Features/Banners/BannerStudioView.swift):
Undo/Redo in topbar; Save → **Done**; debounced `previewImageData`-bake (800 ms). DoD groen.

## 37.11 — Image background drag-to-reframe
- status: done
- owner: FEAT (2026-06-26)
- team: FEAT + INFRA
- blockedBy: 37.3

**Result:** [BannerDoc](Avatar2/Features/Banners/BannerDoc.swift) — `fillImageFocalX/Y` (default
0.5). [BannerCompositor](AvatarKit/Sources/AvatarKit/Engines/BannerCompositor.swift) aspect-fill
vanuit focal point. [BannerBackgroundPanel](Avatar2/Features/Banners/BannerBackgroundPanel.swift):
drag-to-reframe hint; Generate-stub verwijderd; actieve gradient/image-indicators. DoD groen.

## 37.12 — Effects clarity + tool hints
- status: done
- owner: FEAT (2026-06-26)
- team: FEAT + DS
- blockedBy: 37.7

**Result:** Toolbar **Shaders → Effects**; paneltitel "Effects"; lege-staat copy "Applied to the
whole banner". [DSEditPanel](AvatarUI/Sources/AvatarUI/Components/DSEditPanel.swift) optionele
`subtitle` voor éénregelige first-open hints per tool. [BannerShaderPanel](Avatar2/Features/Banners/BannerShaderPanel.swift)
gebruikt nieuwe [DSSlider](AvatarUI/Sources/AvatarUI/Components/DSSlider.swift). DoD groen.
