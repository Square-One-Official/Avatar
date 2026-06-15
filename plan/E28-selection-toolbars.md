# E28 — Selectie-gestuurde editing: per-portret toolbars

Team: FEAT + DS

Het editen wordt selectie-centrisch: de toolbars horen bij het GESELECTEERDE portret, niet bij de
app als geheel. Bouwt op E27 (camera + board-modus). Context = de editor-canvas (één portret); de
selectie is de single source of truth die ook de board/multi-select (E29) zal voeden.

Spelregels strikt: claim → Plan → bouwen → DoD (beide targets groen) → MERGE → Result. Done = ná
merge. Elke UI-story visuele smoke + screenshot. Figma-afwijkingen onder "Figma-TODO:".

## 28.1 — Selectiemodel (één bron van waarheid) [FEAT]
- status: done
- owner: FEAT (AI-agent)
- blockedBy: —
Eén "geselecteerd portret" als single source of truth. Bij openen is standaard het portret
geselecteerd (toolbars meteen zichtbaar — duidelijk voor first-time users). Klikken op lege canvas
(buiten het portret) = deselecteren. Portret wisselen (library) = opnieuw geselecteerd (re-target).

**Result:** `EditorView.canvasSubjectSelected` is de single source of truth van de editor-selectie
en defaultt nu op **true** (bij openen is het portret geselecteerd → handles + toolbars meteen
zichtbaar). Bij een portret-wissel (`persistentModelID`-change) wordt opnieuw geselecteerd
(re-target). De deselect op lege-canvas-klik leunt op de bestaande tap + ESC; de betrouwbaarheids-fix
zit in 28.4. DoD: beide targets + tests groen (`build-v2.sh`); smoke: portret opent geselecteerd —
handles + canvas-/bottom-toolbar zichtbaar (/tmp/s28_1.png).

## 28.2 — Canvas-toolbar zweeft boven het geselecteerde portret [DS/FEAT]
- status: done
- owner: DS/FEAT (AI-agent)
- blockedBy: 28.1
De canvas-toolbar (Frame/Background/Adjust/AI) is alléén zichtbaar bij selectie en zweeft boven het
geselecteerde portret; niks geselecteerd → toolbar verdwijnt.

**Result:** de `CanvasActionToolbar`-overlay rendert nu binnen `if canvasSubjectSelected` (28.1),
met een opacity+move-transitie; bij deselect sluit ook een open canvas-dropdown (`canvasMenu = nil`).
DoD: beide targets + tests groen. Smoke: geselecteerd = toolbar bovenaan zichtbaar (/tmp/s28_1.png);
na ESC-deselect = toolbar weg (/tmp/s28_2_deselected.png). De bottom-toolbar volgt in 28.3.

## 28.3 — Onderste tool-buttons → toolbar-layout, targetend [DS/FEAT]
- status: done
- owner: DS/FEAT (AI-agent)
- blockedBy: 28.1
De onderste icon-buttons (Effects/Face/Clothing/Hair) volgen óók de selectie: niks geselecteerd →
ook deze verdwijnen (besluit Thierry: beide toolbars weg bij geen selectie). Overweeg een minimale
"voeg portret toe/klik om te bewerken"-affordance; leg de keuze vast in Result.

**Result:** `DSEditPanelContainer` kreeg `showsToolbar` (default true) — `false` verbergt de
`DSBottomToolbar` én een eventueel open paneel (met transitie). `EditorView` geeft
`showsToolbar: canvasSubjectSelected || isSidebarVisible` (de Images/sidebar-modus is een tool-keuze,
geen canvas-deselect). Bij deselect sluit ook het bottom-paneel (`activeTool = nil`). Affordance-keuze:
een **minimale "Click the portrait to edit"-pill** onderaan bij geen selectie (geen "voeg portret
toe" — dat hoort op de board/E29). DoD: beide targets + tests groen. Smoke: na ESC-deselect zijn
BEIDE toolbars weg + de hint-pill verschijnt (/tmp/s28_3_deselected.png). De zoom-HUD/undo-redo
blijven (app-/canvas-chrome, geen portret-toolbar).

## 28.4 — Deselect op lege-canvas-klik werkt ALTIJD [FEAT]
- status: in_progress
- owner: FEAT (AI-agent)
- blockedBy: —
Aanhoudende bug: ESC deselecteert wel, maar BUITEN het portret op de canvas klikken laat de transform
staan. Klikken op lege canvas moet altijd deselecteren (transform + toolbars weg). Supersedes 24.32
voor het lege-canvas-geval; diagnose waarom de canvas-tap niet doorkomt (overlay/hit-test?) en fix.
Smoke: selecteer → versleep → klik op lege canvas = deselect; klik op het portret = re-select.
