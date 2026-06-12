# E09 — Effects

Team: **FEAT+AI**



## 9.1 — [AI] Stijl-route bepalen
- status: done
- owner: AI
- blockedBy: E01.5 (done — gepromoveerd naar ready op besluit Thierry 2026-06-12)
- DoD: beide targets bouwen, tests groen

Drie-armige bakeoff (besluit Thierry 2026-06-12): **Nano Banana (Replicate/fal) vs FLUX.2 vs
OpenAI gpt-image (via Replicate)** op 5 portretten.

Testset: de 4 stijlen (Clay/Wood/3D/Scribble) **plus edit-cases**: tanden bleken, rimpels
verminderen, belichting fixen, haar en kleding. **Hard criterium: identity-behoud** — FLUX Fill
(de bestaande fill-body-route) als referentie; een arm die identiteit verliest valt af ongeacht
stijlkwaliteit. De uitkomst mag **per feature een ander model** zijn (stijl ≠ kleding ≠ haar) —
dat bepaalt ook het standaard- vs premiumtarief in E14.3 (4 vs 7 credits). Testmechanisme:
de dev-only model-picker uit E15.5; zolang die er niet is kan de bakeoff direct via de
`model_override`-parameter (E01.10 — sinds de E13.0-port van 2026-06-12 op productie). Voor
backend-werk dat ná die port op v2-main landt geldt: in-app testen tegen een
**Vercel-preview-deploy** van de branch tot de volgende E13.0-port.

**Result:** Drie-armige bakeoff volledig gedraaid (140/140: 3 armen × 9 cases × 5 portretten + 5 fill-body-referenties) via nieuw dev-only `/v1/stylize` + `stylize`-feature in MODEL_REGISTRY (nano-banana/flux-2-pro/gpt-image-1.5, payload-adapters in lib/replicate.ts) op een Vercel-preview-deploy. **Winnaar op het harde criterium identity-behoud: nano-banana — aanbevolen default voor stijlen (E09.2), edits (E12), haar (E11) én kledingwissel (E10); flux-fill-pro blijft voor outpaint; flux-2-pro afgewezen (identity-drift), gpt-image-1.5 reserve (herkadert, traag).** Rapport + per-feature-tabel: plan/e09-1-bakeoff.md; alle outputs/sheets: ~/Documents/Claude/Projects/Aaavatar/e09-bakeoff/. Beide targets bouwen, packagetests groen.

## 9.2 — Effects-paneel
- status: backlog
- owner: —
- blockedBy: 9.1, E06.1
- DoD: beide targets bouwen, tests groen

Geen Original-card: gekozen stijl = active state, nogmaals klikken deselecteert. Previews in eigen
stijl volgen later (placeholder-previews nu). Endpoint /v1/stylize.

**Result:** _(invullen bij done)_

