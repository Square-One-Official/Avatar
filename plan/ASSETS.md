# Asset-register — placeholders in Aaavatar 2.0

Werkregel (CLAUDE.md → Vaste kennis): assets bouwen we met een duidelijk gemarkeerde
placeholder op de juiste afmetingen/verhouding uit Figma; elke placeholder staat hier
geregistreerd (wat, Figma-frame, formaat). Thierry levert definitieve assets later in één
batch — een placeholder stilletjes als definitief behandelen mag niet.

| # | Wat | Figma-frame | Formaat | Status placeholder |
|---|-----|-------------|---------|--------------------|
| 1 | Splash-achtergrondafbeelding (fluid blauwe gradient) | Onboarding / Splash (2611:39453) | full-bleed, frame 1240×800 | placeholder gebouwd (E04.5, OnboardingSplashView) |
| 2 | Memoji-avatars (6 figuren; cirkels = projects-palet) | App / First use (4008:7050, Frame 28 4016:552) | 6× 112×112 in ring 469×524 | placeholder gebouwd (E04.5, FirstUseEmptyState) |
| 3 | Background-print-presets (cracked stone, leopard, etc.) | App / Choose Background (4017:1099, "Image"-rij) | tegels 36×36 / canvas 1024² | E07.1 gebruikt gegenereerde gradient-presets als placeholder; ontworpen prints volgen als asset-batch |
| 4 | Effects-stijl-previews (clay / wood / 3d / scribble) | App / Effects | 4× thumbnail 84×84 | E09.2 gebruikt een neutrale tegel + sparkles-glyph als placeholder; echte stijl-previews volgen als asset-batch |
| 5 | Frame-lokale zwevende toolbar (Frame ▾ / Background / grid) | **n.v.t. — geen Figma-referentie** (capsule-frame 4114:978 toont 'm niet; team-vondst, E31) | zwevende capsule boven het portret, knoppen h32 | **placeholder-design** (E31.4, `CanvasActionToolbar`) — gebouwd in de geest van het hoofddesign; Thierry levert het echte design later (Figma-TODO) |

**GTM-besluit (2026-08-16):** de 2.0-beta gaat live **met deze placeholders**. Dat is een geaccepteerd launch-risico, geen stille promotie tot definitieve assets. De batch blijft later één levering.
