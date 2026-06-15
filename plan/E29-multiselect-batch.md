# E29 — Multi-select & batch-bewerking

Team: FEAT + AI

Op de board (E27.4) meerdere portretten selecteren en in één keer bewerken. Bouwt op E28
(selectiemodel + targetende toolbars).

Spelregels strikt: claim → Plan → bouwen → DoD (beide targets groen) → MERGE → Result. Done = ná
merge. Elke UI-story visuele smoke + screenshot. Figma-afwijkingen onder "Figma-TODO:".

## 29.1 — Multi-select op de canvas [FEAT]
- status: in_progress
- owner: FEAT (AI-agent)
- blockedBy: E28.1
Selecteer meerdere portretten op de board: cmd/shift-klik om toe te voegen/af te halen + marquee
(sleep-rechthoek) op lege canvas. Duidelijke multi-select-state (alle geselecteerde gemarkeerd).
Klik op lege canvas = alles deselecteren. (Enkelklik = selecteer dat portret; dubbelklik = open in
de editor.)

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
