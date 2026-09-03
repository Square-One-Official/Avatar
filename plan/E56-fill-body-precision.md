# E56 — Fill in body: minimale reparatie

Team: **FEAT + INFRA**

## 56.1 — Edge-aware generatie en stabiele kadrering
- status: done
- owner: FEAT+INFRA (GPT-5.6 Sol, 2026-09-01)
- blockedBy: —

**Probleem:** “Fill in body” normaliseert elke cutout naar een vaste 768×1024-
canvas en laat alle transparante marge genereren. Daardoor verschijnt veel meer
lichaam dan de gebruiker vroeg. Een ratio-reset publiceert bovendien eerst het
nieuwe beeld en start daarna asynchroon AutoFramer, waardoor het portret seconden
later nogmaals vergroot en centreert.

**Contract:**
- Alleen werkelijk afgesneden linker-, rechter- en onderranden worden aangevuld.
- De bestaande pixels blijven exact behouden.
- Zonder afgesneden lichaamsrand is de actie een niet-betaalde no-op.
- Resultaatbeeld en gecompenseerde transform worden atomair gepubliceerd; Fill in
  body start geen vertraagde AutoFramer.
- De Vision-facebox wordt vanuit Avatar2 meegestuurd.
- De werkstatus blijft zichtbaar tot generatie, rematting en toepassing klaar zijn.

**DoD:** backend-geometrie en clientmapping getest; rechts/links/onder/meerdere
randen/no-op/originele pixels/schermpositie gedekt; `backend` typecheck groen;
`scripts/build-v2.sh` groen; visuele voor/na-smoke vastgelegd.

**Uitrolvolgorde:** pas eerst `backend/sql/020_atomic_credit_spend.sql` toe,
deploy daarna de backend en publiceer pas daarna de app-update met het verplichte
mappingcontract.

**Result:** Edge-aware linker/rechter/onderrandmaskers vervangen de vaste
3:4-outpaint; no-op blijft gratis, native bronpixels en faceBox blijven beschermd,
credits worden atomair gereserveerd/terugbetaald en cutout plus gecompenseerde
transform verschijnen atomair met één Undo-stap. Backend-typecheck + 10
geometrie/fixturetests, de deterministische rechterrand- en meerranden-visuele
smoke en de volledige `scripts/build-v2.sh`-suite zijn groen (2026-09-01).

## 56.2 — Randdetectie op het onderwerp, niet op het canvas
- status: done
- owner: INFRA (Claude, 2026-09-03)
- blockedBy: —

**Probleem (crash-flow 2026-09-03, Loki Bright):** Fill in body leverde een
717×730-canvas op waarin FLUX de rechtermarge leeg (grijs) liet; de arm stopte
in een kaarsrechte lijn op x=640, 77 px vóór de canvasrand. Een tweede klik gaf
"Nothing to fill", omdat `computeMinimalBodyFillGeometry` alleen de buitenste
pixelkolom/-rij van het canvas bekeek. Elke transparante gutter (eerdere fill,
import met marge) verborg zo een harde snede. Besluit Thierry: "niet kijken naar
canvas maar gewoon naar de afbeelding".

**Contract:**
- Snedes worden gezocht op de alpha-bbox van het onderwerp: een lange rechte run
  van solide alpha (≥128) die abrupt eindigt (buitenste lijn ≤ ⅓ van de run),
  tot ~2% van de beeldmaat binnen het solide uiterste (zachte ramp na her-encoding, smalle uitloper onder de snede).
- Lengte-eis: zijkanten ≥ 12% van de bemonsterde rijen (bovenste 30% van het
  onderwerp uitgesloten voor haar), onderrand ≥ 30% van de solide breedte — een
  natuurlijke ronding raakt zijn uiterste lijn maar ~√(1/r) van de hoogte.
- Het canvas groeit alleen waar de bestaande marge de strook (12%/14% van het
  beeld) niet kan bevatten; het masker schildert één strook voorbij de snede en
  niet de hele gutter. Mapping-contract naar de client ongewijzigd
  (`originalX ≥ 0`, bron binnen canvas).

**Result:** `backend/lib/image.ts` (geometrie + maskerstroken rond de snede),
`backend/api/v1/fill-body.ts` (doc). Tests herschreven met antialiased
200 px-silhouetten (hoofd + torso): no-op op ronde randen, snede op canvasrand,
snede achter een gutter (padding 0 / alleen het tekort), haar-spike, specks,
links/onder/gecombineerd/inset; 12/12 groen, `tsc --noEmit` schoon, visuele
smoke draait. Geverifieerd op Loki's echte cutout (717×730 uit de app-store):
oud = no-op, nieuw = rechts+onder gedetecteerd op x=639/y=709, canvas 726×812
(rechts groeit alleen het tekort van 9 px, onder 82 px). Backend nog niet gedeployed (gated op Thierry).

## 56.3 — Masker begrensd op het onderwerp: geen ondertitelbalk-hallucinaties
- status: done
- owner: INFRA (Claude, 2026-09-03)
- blockedBy: —

**Probleem (Thierry, 2026-09-03, Jaya Willis):** Fill in body leverde soms een
donkere balk met wartaal ("Present body complets elll bobowriohd ourrent. wh…")
onderaan het portret op. De onderstrook van het masker liep over de volle
canvasbreedte (en de zijstroken over de volle hoogte), ook door de lege grijze
gutter naast het onderwerp. Een brede, dunne witte band onderaan een portret is
voor FLUX Fill precies de vorm van een ondertitel-/captionbalk; de prompt zei
alleen "no text" tussen tien andere ontkenningen, en FLUX volgt ontkenningen
slecht.

**Contract:**
- `computeMinimalBodyFillGeometry` geeft per snede het solide bereik op de
  snedelijn terug (`leftRun*`, `rightRun*`, `bottomRun*`, bron-px, inclusief).
- De maskerstrook langs een snede omsluit dat bereik plus één strookdiepte
  marge aan weerszijden (ruimte voor een schouder/mouw die uitwaaiert); de
  hoek van het canvas wordt alleen meegenomen als de aangrenzende rand óók
  gesneden is. Diepte en seam van de strook ongewijzigd (56.2).
- Prompt: eerst positief wat er wél moet komen (dezelfde stof/huid/schouders
  kort doorgetrokken, egale grijze studio-achtergrond), daarna een eigen
  nadrukkelijke clausule tegen tekst/letters/captions/subtitles/banners/
  logo's/watermerken, dan de bestaande objecten- en gezichtsclausules.
- Mapping-contract naar de client ongewijzigd.

**Result:** `backend/lib/image.ts` (run-extent in de geometrie + begrensde
stroken), `backend/lib/replicate.ts` (prompt). Twee nieuwe tests: onderstrook
blijft zwart in de gutterhoeken en dekt wel de volle torsobreedte; zijstrook
blijft zwart naast het hoofd bij een armsnede. 14/14 groen, `tsc --noEmit`
schoon, visuele smoke (`build/fill-body-smoke/*-mask.png`) toont nu een
lichaamsvormige stub i.p.v. een band. Backend nog niet gedeployed (gated op
Thierry). Als het toch nog voorkomt: volgende laag is een OCR-poort
(Vision op de client of tesseract server-side) met één gratis retry op een
nieuwe seed.
