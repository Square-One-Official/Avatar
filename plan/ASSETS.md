# Asset-register — placeholders in Aaavatar 2.0

Werkregel (CLAUDE.md → Vaste kennis): assets bouwen we met een duidelijk gemarkeerde
placeholder op de juiste afmetingen/verhouding uit Figma; elke placeholder staat hier
geregistreerd (wat, Figma-frame, formaat). Thierry levert definitieve assets later in één
batch — een placeholder stilletjes als definitief behandelen mag niet.

**2.0.0-beta besluit (2026-08-21):** ship met de placeholders hieronder.
Definitieve asset-batch mag later in één keer, niet release-blokkerend.

| # | Wat | Figma-frame | Formaat | Status placeholder |
|---|-----|-------------|---------|--------------------|
| 1 | Splash-achtergrondafbeelding (fluid blauwe gradient) | Onboarding / Splash (2611:39453) | full-bleed, frame 1240×800 | placeholder OK for beta (E04.5, OnboardingSplashView) |
| 2 | Memoji-avatars (6 figuren; cirkels = projects-palet) | App / First use (4008:7050, Frame 28 4016:552) | 6× 112×112 in ring 469×524 | placeholder OK for beta (E04.5, FirstUseEmptyState) |
| 3 | Background-print-presets (cracked stone, leopard, etc.) | App / Choose Background (4017:1099, "Image"-rij) | tegels 36×36 / canvas 1024² | gradient-presets OK for beta; prints later |
| 4 | Effects-stijl-previews | App / Effects | thumbnails | CMS/CDN thumbs live for 6/9 styles; sparkles OK for rest |
| 5 | Frame-lokale zwevende toolbar | **n.v.t.** | zwevende capsule | placeholder-design OK for beta (E31.4) |
| 6 | Enhance Portrait-tegel scène-foto's (3× Pexels **berg-/natuurlandschap** achter de blur/diepte-preview) | **n.v.t.** (E53.10, besluit Thierry 2026-09-02) | 3× 512×512 JPEG, `Avatar2/Assets.xcassets/EnhanceScenePlaceholder{1,2,3}.imageset` | procedurele bokeh-placeholders (`EnhancePreviewScenes`); Thierry kiest definitieve Pexels-foto's, zelfde namen vervangen |
