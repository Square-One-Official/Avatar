# E07 — Background

Team: **FEAT**



## 7.1 — Background-paneel
- status: done
- owner: FEAT (AI-agent, marathon 2026-06-13)
- blockedBy: E06.1
- DoD: beide targets bouwen, tests groen

Kleuren-rij = presets (incl. prints, blijven). Brand colors voegt gebruiker toe via
eyedropper/sampler, meerdere, persistent (barebones brand kit). Plus custom upload.

**Result:** BackgroundPanel (frame App / Choose Background 4017:1099): "Image"-rij (custom upload via NSOpenPanel + gegenereerde gradient-presets — ontworpen print-assets staan in ASSETS.md rij 3) en "Color"-rij (6 DS-projectkleur-presets + persistente brand colors + eyedropper via NSColorSampler). Keuze schrijft op Portrait2 (backgroundColorHex xor backgroundImageData, migratie nil); het canvas toont de achtergrond live achter de cutout en zet het dot-grid uit. Brand colors persistent via BrandColorKit (UserDefaults). Export-kwaliteit-compositing = E07.2. Smoke-run (ontgrendeld): panel 1-op-1 het frame, presets + eyedropper + upload aanwezig, brand-kleuren persistent zichtbaar. Beide targets bouwen groen, suite groen.

## 7.2 — Compositing in AvatarKit
- status: done
- owner: FEAT (AI-agent, marathon 2026-06-13; AvatarKit cross-team, geen overlap met de INFRA/DS-sessie)
- blockedBy: 7.1
- DoD: beide targets bouwen, tests groen

Cutout over kleur/afbeelding, export-kwaliteit behouden.

**Result:** `BackgroundCompositor` (AvatarKit/Engines) — composite(cutout:over:placement:outputSize:): zet de cutout (RGBA) over een kleur óf achtergrondafbeelding op een vierkant exportvlak (default 2048²), volledig in linear-sRGB op de doelresolutie (geen tussentijdse downscale; aspect-fill van de achtergrond). De Placement neemt exact de Portrait2-transform (offset/scale in 1024-canvas-units, scale 0 = fill-fit) en mapt die naar exportpixels — WYSIWYG met de E07.1-preview, top-left→bottom-left Y-flip voor CoreImage. 3 unit-tests (vierkant+opaak, transparant-toont-achtergrond, image-fill) groen. Geen UI (service); beide targets bouwen groen, volledige suite groen. NB: de editor-export-knop die dit aanroept hangt aan E08.2 (Export).

