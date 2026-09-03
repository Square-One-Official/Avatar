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
