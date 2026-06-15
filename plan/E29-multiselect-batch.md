# E29 — Multi-select & batch-bewerking

Team: FEAT + AI

Op de board (E27.4) meerdere portretten selecteren en in één keer bewerken. Bouwt op E28
(selectiemodel + targetende toolbars).

Spelregels strikt: claim → Plan → bouwen → DoD (beide targets groen) → MERGE → Result. Done = ná
merge. Elke UI-story visuele smoke + screenshot. Figma-afwijkingen onder "Figma-TODO:".

## 29.1 — Multi-select op de canvas [FEAT]
- status: done
- owner: FEAT (AI-agent)
- blockedBy: E28.1
Selecteer meerdere portretten op de board: cmd/shift-klik om toe te voegen/af te halen + marquee
(sleep-rechthoek) op lege canvas. Duidelijke multi-select-state (alle geselecteerde gemarkeerd).
Klik op lege canvas = alles deselecteren. (Enkelklik = selecteer dat portret; dubbelklik = open in
de editor.)

**Result:** `BoardView` kreeg een multi-select `selection: Set<PersistentIdentifier>`:
- **Enkelklik** op een node → selecteer alléén die node; **cmd/shift-klik** → toggle 'm in/uit de
  selectie; **dubbelklik** → open in de editor (`onOpen`). Sleep op een node = verplaatsen (E27.4).
- **Marquee**: sleep op de lege board spant een selectie-rechthoek (board-space, lijn ÷camera);
  nodes waarvan het midden erin valt worden geselecteerd (cmd/shift = bij de bestaande optellen).
- **Klik op lege board** → alles deselecteren.
- Geselecteerde nodes krijgen een lime selectie-ring + lime label; de HUD toont "N selected".

**DoD/Verificatie:** beide targets + tests groen (`build-v2.sh`). Smoke (`--board-select 5`): 5 nodes
met lime ring + label, HUD "5 selected" (/tmp/s29_1.png). Marquee/cmd-klik zijn op de bewezen
klik-/gesture-paden gebouwd (CGEvent-clicks registreren, zie 28.4); de selectie-rendering is via de
seed-haak geverifieerd. **Figma-TODO:** ring-styling + marquee-vulling/-rand tegen Figma.

## 29.2 — Batch toepassen via de toolbar [FEAT/DS]
- status: backlog
- blockedBy: 29.1
Met meerdere geselecteerd past de toolbar acties toe op ALLE geselecteerde portretten tegelijk:
dezelfde Background, en dezelfde Adjust/kleurcorrecties. Toolbar toont de batch-context ("N
geselecteerd"). Per-portret cache/transparantie (24.30/24.33) gerespecteerd.

## 29.3 — "Match lighting" over de selectie [AI/FEAT]
- status: backlog
- blockedBy: 29.1
Met meerdere geselecteerd → "zorg dat ze dezelfde belichting hebben alsof in dezelfde studio
gefotografeerd". Normaliseer licht/kleur over de selectie naar een consistente look. Bouwt voort op
E12.2 (set-brede lighting-normalisatie) maar nu vanuit de board-multi-select. Kwaliteitsoordeel +
voor/na in de Result.
