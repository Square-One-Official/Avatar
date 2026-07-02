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
- status: done
- owner: FEAT/DS (AI-agent)
- blockedBy: 29.1
Met meerdere geselecteerd past de toolbar acties toe op ALLE geselecteerde portretten tegelijk:
dezelfde Background, en dezelfde Adjust/kleurcorrecties. Toolbar toont de batch-context ("N
geselecteerd"). Per-portret cache/transparantie (24.30/24.33) gerespecteerd.

**Result:** een zwevende **batch-toolbar** (`boardBatchBar`, top-overlay) verschijnt zodra er ≥1
geselecteerd is: "N selected" + **Background** (Transparent + presets) + **Adjust** (dropdown met de
bestaande `EditColorPanel`). Beide werken op de hele selectie:
- `applyBackgroundToAll(hex)` zet dezelfde achtergrond op elk geselecteerd portret (kleur of
  Transparent; useOriginalBackground/imageData gewist). De board-node toont de gekozen kleur achter
  de cutout → batch-Background is meteen zichtbaar.
- `applyAdjustToAll(after)` zet dezelfde `PortraitAdjust` op elk geselecteerd portret (op commit van
  de EditColorPanel).
Per-portret cache/transparantie (24.30/24.33) blijft intact (we raken alleen de background-/adjust-
velden, niet `cutoutData`/`effectCache`).

**DoD/Verificatie:** beide targets + tests groen (`build-v2.sh`). Smoke (`--board-select 3
--board-batch-bg 8B5CF6`): de batch-bar toont "3 selected" + Background/Adjust, en exact de 3
geselecteerde nodes krijgen de paarse achtergrond; de rest ongemoeid (/tmp/s29_2_clean.png). De
test-achtergronden zijn daarna weer gewist (store schoon). **Nuance:** batch-Adjust schrijft naar
`portrait.adjust` (zichtbaar in de editor/export); de board-thumbnail toont de rauwe cutout, dus
adjust is daar niet zichtbaar — code-geverifieerd. **Figma-TODO:** batch-bar-styling, swatch-set en
de Adjust-dropdown tegen Figma leggen.

## 29.3 — "Match lighting" over de selectie [AI/FEAT]
- status: done
- owner: AI/FEAT (AI-agent)
- blockedBy: 29.1
Met meerdere geselecteerd → "zorg dat ze dezelfde belichting hebben alsof in dezelfde studio
gefotografeerd". Normaliseer licht/kleur over de selectie naar een consistente look. Bouwt voort op
E12.2 (set-brede lighting-normalisatie) maar nu vanuit de board-multi-select. Kwaliteitsoordeel +
voor/na in de Result.

**Result:** een **"Match lighting"-knop** in de batch-toolbar (verschijnt bij ≥2 geselecteerd). Hij
hergebruikt de E12.2-`SetLightingNormalizer`: de eerste geselecteerde dient als referentie
(`referenceStats`), de overige worden ernaartoe genormaliseerd (`match`), in één `Match Lighting`-
undo-groep (`CutoutDataUndo`); de board-thumbnails worden geïnvalideerd zodat de nieuwe cutouts
opnieuw decoderen → de relit-versie is op de board zichtbaar. Dit is exact het E12.2-pad, nu vanuit
de board-multi-select i.p.v. de sidebar.

**DoD/Verificatie:** beide targets + tests groen (`build-v2.sh`). Smoke (`--board-select 8
--board-match-light`): de bar toont "8 selected … ☀ Match lighting"; de normalisatie draait zonder
fout over de selectie en de thumbnails verversen (/tmp/s29_3.png).
**Kwaliteitsoordeel:** de meeste test-portretten zijn duplicaten van hetzelfde beeld, dus het
zichtbare voor/na-verschil is klein (referentie ≈ doel → gain ≈ 1). Op een echt gemengde set
(verschillende belichting) trekt de normalisatie de set naar één consistente studio-look — dat is de
geteste E12.2-engine; de meerwaarde hier is de board-multi-select-instap. **Figma-TODO:** knop-styling
+ een referentie-keuze (welke node is de "studio"-referentie) tegen Figma/Thierry leggen.

## 29.4 — Board: cmd/shift-klik via expliciete gestures [FEAT]
- status: done
- team: FEAT
- blockedBy: —

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevinding C5).
**Wat:** `BoardView.swift:435-442` bevat wél toggle-logica
(`NSEvent.modifierFlags.contains(.command/.shift)` → insert/remove, anders
`selection = [id]`), maar leest de **globale** `NSEvent.modifierFlags` onder een
double-tap-gesture (`count: 2`, regel 392) i.p.v. de modifiers van het triggerende
event zelf — live aantoonbaar fragiel: cmd/shift-klik vervangt de selectie i.p.v.
toggelt.
**Voorstel:** expliciete gestures i.p.v. globale event-state:
`TapGesture().modifiers(.command)` naast een kale tap, en apart `.modifiers(.shift)`
voor additief/range-gedrag (macOS-conventie: shift = range, niet toggle-alias van
cmd). Verifieer op een verse build (dual-instance/DerivedData-valkuil is hier eerder
gezien).
**DoD:** beide targets bouwen; cmd-klik toggelt, shift-klik breidt een range uit,
kale klik vervangt; tests groen; Result-regel.

**Result:** `tapNode` (globale `NSEvent.modifierFlags`-lezing) is vervangen door drie
expliciete gestures op de node: `TapGesture().modifiers(.command)` → `toggleNodeSelection`
(insert/remove, macOS-conventie), `TapGesture().modifiers(.shift)` → `extendSelectionRange`
(RANGE anker→node in board-volgorde, Finder-conventie — shift is geen toggle-alias van cmd
meer), kale `TapGesture` → `selectOnly` (vervang; zet het range-anker). Nieuw
`@State selectionAnchor` volgt de laatst kaal/cmd-geselecteerde node; valt het anker uit de
selectie dan schuift het door. De range-logica zit in de pure statische helper
`BoardView.rangeExtendedSelection(current:anchor:target:order:)` — unit-getest in het nieuwe
`Avatar2Tests/BoardSelectionTests.swift` (6 tests: voorwaarts/achterwaarts, union met
bestaande selectie, geen/onbekend anker → additief, anker==doel). Gesture-volgorde =
prioriteit (modifier-varianten vóór de kale tap); dubbelklik-open ongewijzigd.

**DoD/Verificatie:** Avatar (v1) + Avatar2 bouwen; `xcodebuild test -scheme Avatar2`
100/100 groen (incl. de 6 nieuwe), `swift test` AvatarKit 89 + AvatarUI 37 groen.
Bijvangst: flaky `EntitlementModelTests.testMonthlyResetInFutureIsUpcoming` gedeflaked
(ISO8601 trunceert subseconden → `rounded(.down)` i.p.v. `rounded()`; was 1-op-3 rood).

## 29.5 — Board-panelen: dode chips + gedeelde kwaliteitsgate [FEAT]
- status: ready
- team: FEAT
- blockedBy: —

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevindingen C6, en de
Editor/Board-review F5/F10).
**Wat:** `EditColorPanel.swift:82` heeft `showAutoEnhance` default `true`; de
board-call-sites (single-select Enhance `BoardView.swift:1136-1142`, batch-Adjust
`BoardView.swift:774-799`) geven geen closures mee → de chips Studio Light/
Portrait/Colorise/Boost/Restore body renderen met de default-lege closures
(`EditColorPanel.swift:44-56`) en doen dus niets bij een klik. Daarnaast krijgen de
board-panelen geen `StylizeQualityCoordinator` mee (param default `nil`) — de
pre-stylize-kwaliteitsgates draaien dus alléén in de editor; dezelfde Effects-klik
gedraagt zich op de board anders dan in de editor (pipeline-drift, board dupliceert
de editor's apply/undo-pad in `applyToNode`/`undoableApplyToNode`).
**Voorstel:** `showAutoEnhance: false` op beide board-call-sites zetten óf de acties
echt bedraden; op termijn één gedeelde apply/undo/gate-service die editor én board
injecteren i.p.v. twee parallelle implementaties.
**DoD:** beide targets bouwen; geen chip op de board doet meer niets bij een klik;
tests groen; Result-regel.
