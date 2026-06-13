# E06 — Editor-framework

Team: **FEAT**

Figma: App / Edit. Raamwerk waar alle feature-panelen in hangen.

## 6.1 — Toolbar + panel-systeem
- status: done
- owner: FEAT
- blockedBy: E03.3
- DoD: beide targets bouwen, tests groen

Met verkleinende foto bij actief paneel (E03.3-patroon).

Notities (FEAT, bij oplevering):
- De icon-lagen in het Figma-frame heten allemaal nog "square.and.arrow.up" — namen zijn stale,
  de render is de bron; SF-benaderingen gekozen (wand.and.stars, sparkles, tshirt.fill,
  comb.fill, person.and.background.dotted, photo.on.rectangle.angled). Het Images-icoon is in
  het frame een mini-portret; placeholder-SF tot E05.4.
- App / Edit toont rechtsboven avatar/share/gear: avatar = sidebar-toggle (E05.4), share =
  export (E08.2) — buiten 6.1-scope gelaten. Undo/redo in de toolbar-strook komen met E06.2
  (losse DSIconButtons conform het E03.3-besluit).

**Result:** EditorView in Avatar2/Features/Editor/ op DSEditPanelContainer (E03.3): zes tools uit App / Edit als DSToolbarItem-enum (EditorTool) met lime active-ring, tik-op-actief deselecteert, foto verkleint centraal via de container-spring; per tool een lege DSEditPanel-chrome met stub-regel die naar de leverende story wijst (6.3/E07.1/E09.2/E10.2/E11.2/E05.4); gemount in ShellView op canvas .result. Beide targets bouwen groen, alle tests groen (1 nieuwe Avatar2-test: EditorToolTests).

## 6.2 — Undo/redo + hold-to-compare
- status: ready
- owner: —
- blockedBy: 6.1
- DoD: beide targets bouwen, tests groen

Beide staan in het design (10 jun); bouwen conform Figma, op canvas-niveau.

**Result:** _(invullen bij done)_

## 6.3 — Edit-paneel
- status: ready
- owner: —
- blockedBy: 6.1, E03.4
- DoD: beide targets bouwen, tests groen

Actielijst (zakelijke acties boven beauty-acties), elke actie via ProChip. Acties mogen stubs zijn.
Let op: paneel krijgt later nog een design-iteratie — vervangbaar bouwen.

**Result:** _(invullen bij done)_


## 6.4 — Canvas-transform: pan/zoom/snap
- status: ready
- owner: —
- blockedBy: 6.1 (done)
- DoD: beide targets bouwen, tests groen
- Context: besluit Thierry 2026-06-13 — port van v1-mechanics. GEEN Figma-afhankelijkheid: implementeer op macOS-conventies + onderstaande spec (de ontwerpbron van deze story). Mechanics 1-op-1 porten uit v1 EditorView (drag/snap/haptics, regels ~252–350) en de guide-overlay; visueel in DS-stijl.

Spec (Thierry):
- Drag = pan, scroll/pinch = zoom (0,5×–3×) van de foto binnen de vaste 1:1-canvaskaart;
  dubbelklik = auto-frame.
- Tijdens drag een subtiele alignment-guide-overlay (ooglijn + hoofd-ovaal), fade-in bij
  dragstart, fade-out na loslaten.
- Magnetische snapping op canvas-midden-X en de standaard-ooglijn, met haptic tick.
- Transform persistent per portret (Portrait2-velden; bewerking → updatedAt).

**Result:** _(invullen bij done)_

## 6.5 — Automatic framing-actie
- status: backlog
- owner: —
- blockedBy: 6.4
- DoD: beide targets bouwen, tests groen
- Context: besluit Thierry 2026-06-13. GEEN Figma-afhankelijkheid (zelfde spec-bron als 6.4). v1 AutoAligner is de referentie: neem de getunede doelwaarden over — niet opnieuw raden. ProcessedSubject (eyeCenter/interEyeDistance/bodyBottomY) zit in AvatarKit.

Spec (Thierry): "Automatic framing"-actie in het Edit-paneel — ogen op de standaard-ooglijn
(~44% van boven), horizontaal centreren op eyeCenter, schalen op interEyeDistance als vast
percentage van de canvasbreedte; geanimeerde overgang.

**Result:** _(invullen bij done)_
