# E10 — Clothes

Team: **FEAT+AI**



## 10.1 — [AI] Kleding-masker
- status: done
- owner: AI
- blockedBy: E02.1
- DoD: beide targets bouwen, tests groen

Person-seg minus gezicht/haar (macOS 26-pad); tap-to-segment volgt bij macOS 27.

**Plan:**
1. `ClothesMaskGenerator` in `AvatarKit/Engines/`: person-seg (gepinde rev, accurate, 16-bit) minus een hoofd/haar-exclusiezone uit de face rect — crown- en beard-ellipsen met de bewezen v1-getallen (0.6×/1.4× resp. 0.3×/0.7× faceW) plus een gezichts-ovaal; clothes = person × (1−zone), clamp, linear-sRGB render. Bewust geen extra refinement (minimaal pad; FLUX Fill-consument in 10.2 bepaalt dilate/feather).
2. Geen gezicht → `noFaceFound`, geen person-seg-massa → `noPersonFound`; de geometrie-beperkingen (achterhoofd, hoeden) zijn bekend en worden in macOS 27 vervangen door tap-to-segment (correctie-laag uit de audit).
3. Vision herkent synthetische fixtures niet als persoon/gezicht (geprobed): zone-opbouw en mask-compositie zijn daarom interne, deterministisch geteste functies; e2e dekt het noPersonFound-pad.

**Result:** `ClothesMaskGenerator` in `AvatarKit/Engines/` — `mask(for:) async throws -> CGImage` (wit = kleding, bron-resolutie, linear-sRGB); person-seg (rev1/accurate/16-bit) × (1 − crown∪beard∪gezicht-zone uit grootste face rect); fouten `.noPersonFound` (ook bij lege matte, drempel 1/255 gemiddelde) / `.noFaceFound` / `.renderFailed`; 7 nieuwe tests (zone-dekking, compositie, luminantie, e2e-foutpad), totaal 25 groen; beide targets bouwen via build-v2.sh. Contract voor E10.2: dilate/feather richting FLUX Fill is aan de consument.

## 10.2 — Clothes-paneel
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: 10.1, E06.1
- DoD: beide targets bouwen, tests groen

'Change outfit', gefixte chips, vrije prompt → bestaande FLUX Fill-backend met kledingmasker.

**Result:** ClothesPanel (Features/Editor, frame 4016:13760): "Change upper clothes" + outfit-preset-chips (T-Shirt/Polo/Blazer/Hoody/Sweater) + vrije prompt ("Describe a color or style") met lime send-knop (disabled bij lege input); gemount op de Clothing-tool. **Generatie-route geparkeerd** (DECISIONS-PENDING): E10.1's kledingmasker (masked FLUX Fill) vs E09.1's nano-banana instruction-edit — aanbeveling nano-banana via productie-/v1/stylize (E09.2); generate-actie is nu een stub (onApply), paneel vervangbaar opgezet. Smoke-run (ontgrendeld): 1-op-1 het frame. Beide targets bouwen groen, suite groen.

## 10.3 — [AI] Upscale/Boost-resolution-model (spike)
- status: backlog
- owner: AI
- blockedBy: —
- DoD: model gekozen + kosten bevestigd
- Context: besluit Thierry 2026-06-13 — "Boost resolution" = 1 credit (CreditMeter.upscale, al live). Alleen de MODELKEUZE is open: kies een Replicate-upscale-model (bv. Real-ESRGAN/Clarity), bevestig kosten/call (verwacht ~$0,002–0,01, past binnen 1 credit), en wire de actie. Geen blocker voor andere stories.

**Result:** _(invullen bij done)_

## 10.4 — Kledingwissel-route wiren (na E09.2)
- status: blocked
- owner: FEAT
- blockedBy: E09.2
- DoD: beide targets bouwen, tests groen; acceptatiecriterium gehaald
- Context: besluit Thierry 2026-06-13 — nano-banana instruction-edit is het PRIMAIRE pad ("change the upper clothing to <preset>, keep face/hair/pose"). **Acceptatiecriterium (hard):** alléén kleding wijzigt; gezicht/haar/pose/achtergrond pixel-identiek. ClothesMaskGenerator (E10.1) + FLUX Fill = precisie-fallback. E10.2's ClothesPanel-onApply (nu stub) hierop aansluiten zodra E09.2 het productie-/v1/stylize levert.

**Result:** _(invullen bij done)_
