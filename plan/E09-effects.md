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
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: 9.1 (done), E06.1 (done) — beide blockers klaar; gepromoveerd uit backlog en geclaimd op de keten-instructie van Thierry.
- DoD: beide targets bouwen, tests groen

**Plan:**
1. Backend (port-only, in-app testen tegen Vercel-preview): `/v1/stylize` van dev-only naar
   productie-gegated. Server-side stijl→prompt-mapping (clay/wood/3d/scribble, elk met de
   identity-clausule uit E09.1); `style`-param is de productieroute, vrij `prompt` blijft
   alléén voor dev-users (bakeoff-mechanisme). `dev_only`-gate weg; credit-gate
   (`MODEL_REGISTRY.stylize.credits` = 4) + `logCredit` + 402, exact zoals colorize.ts.
   nano-banana default (staat al in de registry).
2. Resultaat = flattened styled PNG (opaque). Kleine keuze (gedocumenteerd): géén
   alpha-herextractie — een Effects-render is een nieuw, vol portret dat de kaart vult; een
   her-cutout zou een extra cutout-call per stylize kosten zonder visuele winst. (E10.4/E11.2
   kunnen later hun eigen intent-param toevoegen aan ditzelfde endpoint.)
3. AvatarKit: `StylizeStyle`-enum (rawValue = backend-key) + `BackendClient.stylize(imagePNG:
   style:) -> (Data, Int)` (inline base64, `model_override` via DevModelOverrides.stylize).
   CreditMeter heeft `.generativeStandard` al (4 cr).
4. FEAT: `EffectsPanel` (4 stijl-kaarten, placeholder-previews op ASSETS.md, geselecteerd =
   active, nogmaals klikken deselecteert) + `EffectsModel` (@Observable: busy-state, result →
   `portraitModel.cutoutData`, 402 → entitlement-paywall). `entitlement` door EditorView
   geplumbd; effects-stub in de panel-switch vervangen. Smoke via `--open-panel effects`.

Geen Original-card: gekozen stijl = active state, nogmaals klikken deselecteert. Previews in eigen
stijl volgen later (placeholder-previews nu). Endpoint /v1/stylize.

Notitie (besluit Thierry 2026-06-13): E09.2 levert het productie-`/v1/stylize`-endpoint
(nano-banana default, zie E09.1) dat óók E10.4 (kledingwissel) en E11.2 (haar) consumeren —
instruction-edit met het harde acceptatiecriterium "alléén het doel wijzigt, rest pixel-identiek".
Het dev-only /v1/stylize uit E09.1 wordt hier de gegate productie-route (credits via CreditMeter,
402 → paywall). Model kiesbaar maken = E15.6 (nano-banana standaard, OpenAI alternatief).

**Result:** Effects-paneel end-to-end. **Backend** (port-only, in-app testen tegen Vercel-
preview): `/v1/stylize` van dev-only → productie — server-side `STYLE_PROMPTS`-mapping
(clay/wood/3d/scribble + identity-clausule uit E09.1), `style`-param is de productieroute, vrij
`prompt` blijft dev-only; `dev_only`-gate weg; credit-gate (`MODEL_REGISTRY.stylize.credits` = 4)
+ `logCredit("stylize")` + 402, identiek aan colorize.ts; nano-banana default. Geen
alpha-herextractie (opaque styled portret vult de kaart — E09.2-besluit). `npm run typecheck`
groen. **AvatarKit:** `StylizeStyle`-enum (rawValue = backend-key) + `BackendClient.stylize(
imagePNG:style:) -> (Data, Int)` (inline base64, `model_override` via DevModelOverrides.stylize).
**FEAT:** `EffectsPanel` + `EffectsModel` (Features/Editor/) — 4 stijl-kaarten met
placeholder-previews (ASSETS.md #4), geselecteerd = lime-ring active state, nogmaals tikken
herstelt het basisbeeld lokaal; tik → `stylize` → resultaat via nieuwe
`ShellModel.applyEffectResult` naar canvas + opgeslagen cutout; busy-spinner per kaart, 402 →
`entitlement.handleOutOfCredits()`, saldo-refresh na succes. `entitlement` + `onApplyResult`
door EditorView geplumbd; effects-stub in de panel-switch vervangen. Smoke (`--open-panel
effects`): paneel rendert 1100×760 met alle vier kaarten, "⚡4"-kostenhint en actieve
toolbar-tool (de live generatie vergt de gedeploye backend → preview-test, niet in de smoke).
Beide targets bouwen groen, alle suites groen.

**Voor de volgende E13.0-port:** stylize.ts staat productie-klaar op v2-main maar nog niet op
`api.aaavatar.nl` — tot de port draait de Effects-generatie tegen een Vercel-preview-deploy.

