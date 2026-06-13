# E11 — Hair

Team: **FEAT+AI**



## 11.1 — [AI] Haar-route
- status: done
- owner: AI (opgelost via de E09.1-bakeoff; afgevinkt tijdens de FEAT-marathon)
- blockedBy: E10.2 (done)
- DoD: beide targets bouwen, tests groen

Mask+prompt via FLUX Fill vs Stable-Hair — kwaliteits-spike op 5 portretten.

**Result:** Geen aparte spike nodig — de **E09.1-bakeoff** (3-armig, 5 portretten) dekte de
haar-case al expliciet (`edit-hair`: "Change the hairstyle… keep the face/expression/clothing
exactly the same"). Uitkomst, gedocumenteerd in `plan/e09-1-bakeoff.md` (sectie "Aanbeveling per
feature"): **nano-banana** is de winnaar voor haar — de enige arm die op álle vijf portretten
het gezicht exact behield bij kapselwissel; flux-2-pro maakte er geregeld een ander gezicht van.
Stable-Hair is niet apart getest omdat de instruction-edit-route (nano) het hardere criterium
"alléén het haar wijzigt, gezicht/pose/achtergrond identiek" haalde zonder mask-plumbing — exact
de route die Thierry op 2026-06-13 koos (nano-banana instruction-edit primair, FLUX-Fill +
mask als precisie-fallback). De route loopt via het productie-`/v1/stylize` uit E09.2; E11.2 zet
het Hair-paneel erop. FLUX-Fill-mask-fallback blijft beschikbaar (E10.1-masker) maar is geen
default. Geen code-wijziging in deze story → targets/tests ongewijzigd groen.

## 11.2 — Hair-paneel
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: 11.1 (done)
- DoD: beide targets bouwen, tests groen

Kapsel-chips (zie figma-design-review copy-voorstel), vrije prompt; zelfde patroon als Clothes.

**Plan:**
1. Backend (port-only, preview-test): `/v1/stylize` krijgt een server-gemapte **hair-intent** —
   `hair_preset` (whitelist trim-flyaways/curly/straight/short/updo → vaste prompt + "keep face/
   expression/clothing exactly the same"-clausule uit de E09.1 edit-hair-case) en/of `hair_prompt`
   (vrije kapselbeschrijving in een **vast hair-edit-sjabloon** gegoten — constrained, geen rauw
   promptveld). nano-default + credit-gate + `generation_model` zoals al aanwezig.
2. AvatarKit: `HairStyle`-enum (rawValue = backend-key) + `BackendClient.editHair(imagePNG:
   preset:freeText:) -> (Data, Int)`.
3. FEAT: `HairPanel` + `HairModel` (zelfde patroon als ClothesPanel/EffectsModel): titel "Change
   hair", chips `Trim flyaways/Curly/Straight/Short/Updo`, vrije prompt "Describe a color or
   style", comb-glyph; tik → editHair → resultaat via `onApplyResult` naar canvas+cutout, 402 →
   paywall. Gemount op de Hair-tool (stub vervangen). Smoke via `--open-panel hair`.

**Result:** Hair-paneel end-to-end op de E11.1-route (nano-banana instruction-edit). **Backend**
(port-only, preview-test): `/v1/stylize` kreeg een server-gemapte hair-intent — `hair_preset`
(whitelist trim-flyaways/curly/straight/short/updo → vaste prompt + "keep face/expression/
clothing exactly the same"-clausule uit de E09.1 edit-hair-case) en `hair_prompt` (vrije
kapselbeschrijving in een vast hair-only-sjabloon `HAIR_FREE_TEMPLATE`, ≤200 tekens — geen rauw
promptveld). nano-default + credit-gate + `generation_model` erven van E09.2/E15.6. `npm run
typecheck` groen. **AvatarKit:** `HairStyle`-enum (rawValue = backend-key) + `BackendClient.
editHair(imagePNG:preset:freeText:)`. **FEAT:** `HairPanel` + `HairModel` (Features/Editor/) in
het Clothes-patroon — titel "Change hair", chips Trim flyaways/Curly/Straight/Short/Updo
(figma-design-review-copy), vrije prompt "Describe a color or style", comb-glyph (al ingesteld);
tik → editHair → `ShellModel.applyEffectResult` (canvas + cutout), busy-state, 402 →
`handleOutOfCredits`, saldo-refresh. Hair-stub in de panel-switch vervangen. Smoke (`--open-panel
hair`): paneel rendert 1100×760 met alle vijf chips, "⚡4"-kostenhint, vrije prompt + send,
actieve comb-tool (live generatie → preview, port-only). Beide targets bouwen groen, alle suites
groen.

