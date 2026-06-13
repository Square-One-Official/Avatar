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
- status: backlog
- owner: —
- blockedBy: 11.1
- DoD: beide targets bouwen, tests groen

Kapsel-chips (zie figma-design-review copy-voorstel), vrije prompt; zelfde patroon als Clothes.

**Result:** _(invullen bij done)_

