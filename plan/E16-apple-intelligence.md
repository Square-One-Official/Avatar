# E16 — Apple Intelligence-integraties

Team: **AI**

Design-onafhankelijk: alles capability-gated (macOS 27 + Apple Silicon vereist; app blijft op macOS 14 werken). Doel: de gepresenteerde features technisch werkend hebben vóór het definitieve design — daarna alleen verfijnen. Vereist Xcode 27 beta + macOS 27 beta op de dev-Mac (actie Thierry indien nog niet geïnstalleerd).

**GEPARKEERD (2026-06-12):** dev-Mac draait macOS 26; de Apple Intelligence-API's (Image
Playground / Foundation Models) vereisen macOS 27. Hele epic wacht op de macOS 27-beta op de
dev-Mac — niet verwijderd, komt terug zodra de beta geïnstalleerd is.

## 16.1 — Capability-laag
- status: blocked — wacht op macOS 27-beta op dev-Mac
- owner: —
- blockedBy: E01.2
- DoD: beide targets bouwen, tests groen
- Context: redesign-audit-en-plan.md §Strategie (twee OS-niveaus).

IntelligenceCapabilities in AvatarKit: detecteert OS-versie, chip, beschikbaarheid Image
Playground/Foundation Models; features vragen capabilities, UI toont features alleen als
beschikbaar. INTERFACE-STORY: API documenteren in Result.

**Result:** _(invullen bij done)_

## 16.2 — Image Playground: achtergrond-generatie
- status: backlog
- owner: —
- blockedBy: 16.1
- DoD: beide targets bouwen, tests groen
- Context: WWDC26 Image Playground API (fotorealistisch model); E07.1-paneel.

Spike → feature: genereer achtergronden uit prompt ('modern office, brand color #...') via Image
Playground API, on-device, 0 credits. Output landt in het Background-paneel als extra bron naast
presets/upload. Kwaliteitsoordeel + voorbeelden in Result.

**Result:** _(invullen bij done)_

## 16.3 — Foundation Models: import-kwaliteitscheck
- status: backlog
- owner: —
- blockedBy: 16.1
- DoD: beide targets bouwen, tests groen
- Context: WWDC26 Foundation Models vision; hook in PipelineRouter (E01.2).

On-device beeldanalyse bij import: te donker, meerdere personen, lage resolutie, bril-reflectie →
vriendelijke inline feedback vóór er credits/tijd verspild worden. Drempel laag houden (waarschuwen,
nooit blokkeren).

**Result:** _(invullen bij done)_

## 16.4 — Image Playground vs FLUX Fill: shoulder-fill-beslistest
- status: backlog
- owner: —
- blockedBy: 16.1
- DoD: beide targets bouwen, tests groen
- Context: knowledge file §Fill in Body (waarom FLUX Fill destijds won); backend fill-body.ts blijft fallback.

Kan Image Playground het Fill in Body-werk overnemen (0 credits, on-device)? Hard criterium:
gezichts-/kleding-pixels exact behouden. Side-by-side op 5 fixtures; beslissing + bewijs in Result.
Winnaar wordt de 2.0-route.

**Result:** _(invullen bij done)_

## 16.5 — Tap-to-segment-spike
- status: backlog
- owner: —
- blockedBy: 16.1
- DoD: beide targets bouwen, tests groen
- Context: WWDC26 sessie 'What's new in image understanding' (237); E10.1 gebruikt dit later.

Nieuwe Vision interactieve segmentatie (macOS 27): tap/box → mask. Twee toepassingen voorbereiden:
cutout-correctie ('tik op wat ontbreekt') en betere kleding-/haarmaskers voor E10/E11. Demo-target
of debug-scherm volstaat.

**Result:** _(invullen bij done)_
