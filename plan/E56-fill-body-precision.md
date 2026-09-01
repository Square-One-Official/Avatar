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
