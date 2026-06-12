# E09 — Effects

Team: **FEAT+AI**



## 9.1 — [AI] Stijl-route bepalen
- status: backlog
- owner: —
- blockedBy: E01.5
- DoD: beide targets bouwen, tests groen

Drie-armige bakeoff (besluit Thierry 2026-06-12): **Nano Banana (Replicate/fal) vs FLUX.2 vs
OpenAI gpt-image (via Replicate)** op 5 portretten.

Testset: de 4 stijlen (Clay/Wood/3D/Scribble) **plus edit-cases**: tanden bleken, rimpels
verminderen, belichting fixen, haar en kleding. **Hard criterium: identity-behoud** — FLUX Fill
(de bestaande fill-body-route) als referentie; een arm die identiteit verliest valt af ongeacht
stijlkwaliteit. De uitkomst mag **per feature een ander model** zijn (stijl ≠ kleding ≠ haar) —
dat bepaalt ook het standaard- vs premiumtarief in E14.3 (4 vs 5 credits). Testmechanisme:
de dev-only model-picker uit E15.5 (op zijn beurt geblokkeerd op E01.10).

**Result:** _(invullen bij done)_

## 9.2 — Effects-paneel
- status: backlog
- owner: —
- blockedBy: 9.1, E06.1
- DoD: beide targets bouwen, tests groen

Geen Original-card: gekozen stijl = active state, nogmaals klikken deselecteert. Previews in eigen
stijl volgen later (placeholder-previews nu). Endpoint /v1/stylize.

**Result:** _(invullen bij done)_

