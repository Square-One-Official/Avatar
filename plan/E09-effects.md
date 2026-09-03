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


## 9.3 — Eigen effecten (user-created custom effects)
- status: done (code) — **prod-uitrol wacht op Thierry: sql/015 + backend-deploy**
- owner: FEAT+INFRA
- team: FEAT+INFRA+AI
- blockedBy: —

**Wat:** een Pro-gebruiker maakt zijn eigen Effect uit een referentiebeeld + een
korte beschrijving. Effects → "Create"-kaart → beeld droppen + beschrijven →
*Save* (alleen bewaren) of *Apply & Save* (bewaren + meteen genereren). Het
referentiebeeld stuurt écht de stijl — het gaat als tweede beeld naar het model,
niet alleen als thumbnail — en de effecten syncen per account. Aanmaken kost
niets; pas het tóépassen kost een credit (zelfde tarief als een built-in effect).

**DoD:** beide targets bouwen + tests groen + Result-regel. ✅

**Result (gebouwd 2026-06-25, gemerged naar v2-main 2026-07-31):**
**Backend** — `sql/015_custom_effects.sql` (owner-scoped tabel, RLS aan, publieke
`custom-effects`-bucket voor referentie + thumbnail), [customEffects.ts](../backend/lib/customEffects.ts)
(list/get/create/delete + referentie-download), [/v1/custom-effects](../backend/api/v1/custom-effects.ts)
+ [/v1/custom-effects/[id]](../backend/api/v1/custom-effects/[id].ts) (Pro-gegate
list/create/delete), en een `custom_effect_id`-tak in [stylize.ts](../backend/api/v1/stylize.ts):
Pro-check + eigenaar-scope, prompt uit de opgeslagen beschrijving in een vast
`CUSTOM_STYLE_TEMPLATE` (rolclausule: bewerk beeld 1, leen alleen de *look* van
beeld 2) + de identity-clausule. `tsc --noEmit` schoon.
**AvatarKit** — `RemoteCustomEffect` (cacheKey `custom:<id>`), `customEffects()`,
`createCustomEffect()`, `deleteCustomEffect()` en `stylize(imagePNG:customEffectID:)`.
**App** — `EffectCard` verenigt built-in en custom op de bestaande string-cachekey,
dus selectie/cache/persistentie (`effectCache`/`effectActiveRaw`) blijven ongewijzigd;
Pro-gegate "Create"-kaart, custom-kaarten met contextmenu-delete, instant lokale
thumbnail na aanmaken; [CreateEffectSheet.swift](../Avatar2/Features/Editor/CreateEffectSheet.swift).

**Merge-besluiten (2026-07-31, de branch stond 224 commits achter):**
- Eén referentie-kanaal: de E34-`referenceDataUrl` is opgegaan in E54's
  `styleReferenceDataUrls`-array (portret eerst, referenties daarna) — CMS-
  stijlreferenties en het custom-referentiebeeld nemen nu dezelfde weg naar het
  model i.p.v. twee parallelle paden door `stylizeInputFor`.
- `stylize(imagePNG:customEffectID:)` geeft `StylizeCallResult` terug (was een
  tuple), gelijk aan de andere stylize-armen.
- Het EffectCard-paneel is opnieuw aangebracht bóvenop het huidige paneel, dus
  mét StylizeQualityCoordinator-gate, AIFeature-gating, async `onApply`,
  cutout-dimensies/`softSource`/`preserveFraming` en de E52.1-`ThumbnailCache`.
- E53.7-conform: de Create-modal leeft in `UIPresentationStore` en hangt via
  `dsPersistentSheet` op ShellView; het resultaat gaat via de store terug naar
  het paneel (geen paneel-`@State`).

**Nog te doen vóór live (gated — Thierry):** (1) `sql/015_custom_effects.sql` op de
prod-Supabase draaien (tabel + bucket bestaan daar nog niet); (2) backend
prod-deploy zodat `/v1/custom-effects` en de `custom_effect_id`-tak bestaan —
zonder (1) en (2) geeft de Create-knop een serverfout. De app-kant is
backward-compatibel: zonder de endpoints blijft de lijst leeg (soft-fail) en
werken de built-in effecten gewoon.
