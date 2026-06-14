# E21 — Edit/Face-splitsing + tool-iconen

Team: **FEAT**. Autonome shift 2026-06-14.

## 21.1 — Split EditActionsPanel (Edit = kleur/technisch · Face = beauty)
- status: done
- owner: FEAT (AI-agent, marathon)
- DoD: beide targets bouwen + tests groen + visuele smoke

**Plan:** Beauty-acties uit Edit halen naar een nieuw Face-paneel; gedeelde rij-infra extraheren
zodat beide panelen identiek ogen (incl. latere leading-iconen). `.face`-tool toevoegen.

**Result:** `EditorActionList` (+ `EditorAction`/`EditorActionSection`) geëxtraheerd als gedeelde
één-koloms actielijst (leading-icoon-slot, credit-kost subtiel, Pro-badge, aan/uit-checkmark).
`EditActionsPanel` = kleur/technisch (Position and alignment · Optimise: Colorise/Boost · Adjust:
Improve lighting/Restore body). Nieuw `FaceActionsPanel` = beauty (Retouch: One-click retouch ·
Beauty: Whiten teeth/Apply make-up/Reduce wrinkles, elk 4 cr). `EditorTool.face` toegevoegd
(tussen Effects en Clothing) + panel-branch in EditorView; EditorToolTests bijgewerkt (7 tools).
Smoke ✓ (Face-paneel + geslankt Edit-paneel; glas-overlay).

**Besluiten verwerkt:** Restore body NIET naar Face (blijft in Edit tot de canvas-cluster E22.2);
framing blijft voorlopig in Edit (verhuist in E22.2) — geen tijdelijke regressie.

**Coupling-noot:** de Face-tool staat nu óók al in de bottom-toolbar (allCases drijft de items),
met een SF-placeholder-icoon. 21.2 doet de icon-pass (DSIcon/Phosphor) voor álle tools.

**Figma-TODO:** Face-paneel sectie-indeling (Retouch/Beauty) bevestigen.

## 21.2 — Face in toolbar (✓ via 21.1) + Phosphor/DSIcon voor álle tools
- status: todo (icon-pass; toolbar al voorzien)

## 21.3 / 20.2 — Leading-icoon per actie (Edit + Face)
- status: todo
