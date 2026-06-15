# E27 — Canvas-viewport: zoom & pan (+ board-view)

Team: FEAT + DS. Aangemaakt 2026-06-15. **Hernummerd van E26** (E26 is al
[motion-polish](E26-motion-polish.md)) op verzoek Thierry.

Behandel de canvas als een echte viewport met een **camera** (scale + offset) over de hele scène,
zoals Framer/Figma. Dit vervangt de canvas-zoom-pogingen uit 24.8/24.17 (die liepen vast doordat
view-zoom en onderwerp-schaling door elkaar liepen).

**Kernonderscheid (bewaken):** VIEW-zoom (camera over de hele scène) ≠ ONDERWERP schalen (de
afbeelding-in-het-frame, via selectie-handles — dat blijft E24). De camera verplaatst/zoomt wat je
ziet; de handles schalen het onderwerp binnen het frame.

Spelregels strikt: claim → Plan → bouwen → DoD (beide targets groen) → MERGE → Result. Done = ná
merge. Elke UI-story visuele smoke + screenshot. Figma-afwijkingen onder "Figma-TODO:".

## Stories

| ID | Story | Team | Status | Branch |
|----|-------|------|--------|--------|
| 27.1 | Canvas-camera: zoom + pan | FEAT | in_progress | `v2/E27-27.1` |
| 27.2 | Zoom-HUD + sneltoetsen | DS/FEAT | backlog (na 27.1) | `v2/E27-27.2` |
| 27.3 | Transform/guides/popovers correct onder de camera | FEAT/DS | backlog (na 27.1) | `v2/E27-27.3` |
| 27.4 | Board-view: meerdere portretten (later) | FEAT | backlog (na 27.1) | `v2/E27-27.4` |

---

## 27.1 — Canvas-camera: zoom + pan  · FEAT
- status: done
- owner: FEAT (AI-agent)
- blockedBy: —
- DoD: beide targets groen + gemerged + Result + screenshot

**Result:** de canvas is nu een echte viewport met één `CanvasCamera`
(`scale` 0.25–4× geclampt + `offset`), als VIEW-transform op de DSCanvasCard
(`.scaleEffect(anchor: .center).offset()`) BUITEN `EditorCanvasView` — de hele
scène (kaart + achtergrond + onderwerp) transformeert mee. De mislukte
per-onderwerp `viewZoom` uit 24.8/24.17 is volledig verwijderd (binding +
`scaleEffect` op het beeld + `magnifyGesture`/`applyViewZoom` weg, de
handle-positie-math terug naar 1× → handles zitten direct op het onderwerp).
- **Zoom:** pinch (`MagnificationGesture`) zoomt om het midden; verborgen
  `keyboardShortcut`-knoppen leveren ⌘+/⌘= (in), ⌘− (uit), ⌘0 (fit = reset),
  ⌘1 (100% = 1× om het midden, pan behouden). `.clipped()` houdt de ingezoomde
  scène binnen de canvas-slot (lekt niet over panelen/toolbar). Camera reset bij
  portret-wissel.
- **Pan/zoom-events:** `CanvasInteractionCatcher` (NSViewRepresentable) installeert
  een lokale `NSEvent`-monitor — scroll/two-finger = pan, ⌘-scroll = zoom rond de
  cursor, spatie-drag = pan. De catcher-NSView geeft via `hitTest → nil` álle
  muis-clicks door, en de monitor consumeert alléén scroll/⌘-scroll/spatie-drag
  (leftMouseDragged wordt enkel bij ingedrukte spatie gepakt) → de subject-drag
  (24.32) en de deselect-tap (`Color.clear`) blijven ongemoeid.
- **Camera ≠ onderwerp:** VIEW-zoom (camera) staat los van de ONDERWERP-schaal
  (selectie-handles, `Portrait2.scale`, E24) — die laatste werkt onveranderd.

**DoD/Verificatie:** beide targets bouwen + alle pakkettests groen
(`build-v2.sh` → "alles groen"). Visuele smoke per camera-zoomniveau (square
frame, `--cam-zoom`): 50% (/tmp/cam_050.png — hele kaart verkleind, toolbar vast),
100%/fit (/tmp/cam_100.png), 200% (/tmp/cam_200.png — ingezoomd om midden, binnen
de slot geclipt), 400%/max (/tmp/cam_400.png — clamp op 4×). Regressie:
24.31 Original-modus rendert correct onder 200% camera (/tmp/cam_original_200.png);
24.32 selectie-handles + selectiekader exact op het onderwerp bij fit
(/tmp/cam_handles_circle.png) en de alignment-gids onder 150% zoom
(/tmp/cam_handles_150.png) — selectie/deselect/ESC zijn structureel ongewijzigd
(deselect-tap + ESC-knop intact; runtime-klikgedrag is zoals in 24.32
niet-screenshotbaar). Window-capture via CGWindowID (terminal-overlap omzeild).

**Figma-TODO:** een zwevende zoom-HUD met het zoom-% + fit-knop (27.2) ontbreekt
nog; ⌘1 "100%" is in dit camera-model gelijk aan 1× (een pixel-echte 100% vraagt
de bron-pixelmaat → 27.2/27.3). Handles/guides/popovers correct in screen-space
houden onder de camera = 27.3. Sign/zoomgevoeligheid van scroll-pan en
spatie-drag tegen de Figma-/gevoels-referentie leggen.

Eén camera-transform (scale + offset) op de hele canvas-scène. Pinch-to-zoom, scroll/⌘-scroll en
⌘+/⌘− zoomen de VIEW; spatie-drag of two-finger-pan verschuift. NIET de afbeelding-in-frame schalen.
Zoom-range + grenzen (bv. 25%–400%), soepel rond de cursor in/uitzoomen.

**Plan (vastgelegd vóór de bouw — regressie-risico op de kern-canvas):**
1. **`CanvasCamera`** (struct: `scale` 0.25–4.0 geclampt, `offset` CGSize) — de enige
   viewport-transform. Vervangt de per-onderwerp `viewZoom` uit 24.8/24.17 volledig: verwijder
   `EditorCanvasView.viewZoom` + `.scaleEffect(viewZoom)` op het onderwerp + `canvasViewZoom` in
   EditorView; de handle-positie-math (regels ~357-361, nu met `viewZoom`-factor) valt terug naar 1×.
2. **Toepassing op scène-niveau:** `DSCanvasCard { … }.scaleEffect(camera.scale, anchor: .center)
   .offset(camera.offset)` in `EditorView` — camera zit BUITEN `EditorCanvasView`, zodat de hele
   scène (kaart + achtergrond + onderwerp) mee-transformeert (handles/guides screen-space = 27.3).
3. **Zoom:** `MagnificationGesture` (pinch) op de DSCanvasCard + ⌘+/⌘−/⌘0(fit)/⌘1(100%) via
   verborgen `keyboardShortcut`-knoppen. Zoom-rond-cursor: pas `offset` aan o.b.v. de
   gesture-/cursor-locatie zodat het punt onder de cursor vast blijft.
4. **Pan zonder de 24.32-arbitrage te breken:** scroll/two-finger + ⌘-scroll vereisen een
   `NSViewRepresentable`-event-catcher (scrollWheel = pan, ⌘-scrollWheel/magnify = zoom) als
   ACHTERGROND-laag die clicks doorlaat (`hitTest` → nil voor muis-down, maar scroll/magnify vangt).
   Spatie-drag = `.onKeyPress(.space)` schakelt pan-mode → DragGesture op de camera. **Let op:** de
   subject-drag (24.32, op het onderwerp) en de deselect-tap (Color.clear) moeten ONGEMOEID blijven —
   de camera-pan mag alleen op lege canvas-ruimte of in pan-mode pakken. Eerst los smoken dat 24.32
   intact blijft.
5. **Volgorde van bouwen:** (a) `CanvasCamera` + scène-transform + pinch + ⌘-toetsen (pure SwiftUI,
   laag risico) → tussentijds smoken; (b) dan de NSEvent-catcher voor scroll/two-finger-pan; (c)
   regressietest 24.32 (deselect + ESC) + 24.31 (Original-modus) onder zoom.
6. **Smoke:** uitzoomen naar 50%/200%/400%, pannen, ⌘0 fit, ⌘1 100%; onderwerp-schaling (handles)
   blijft los van VIEW-zoom; 24.32-deselect werkt nog op elk zoomniveau. Screenshots per zoomniveau.

## 27.2 — Zoom-HUD + sneltoetsen  · DS/FEAT
- status: backlog
- blockedBy: 27.1

Zwevende zoom-HUD (−/slider/+ en fit) met het huidige zoom-%. Sneltoetsen: ⌘0 = fit, ⌘1 = 100%,
⌘+/⌘−. Consistent met de DS-stijl.

## 27.3 — Transform/guides/popovers correct onder de camera  · FEAT/DS
- status: backlog
- blockedBy: 27.1

Handles, thirds-guides en toolbar-popovers blijven correct gepositioneerd én klikbaar op elk
zoomniveau (overlay in screen-space, niet mee-schalend tot onleesbaar/onbruikbaar). Dit lost meteen
het "transform-hoeken niet zichtbaar"-probleem op: je kunt uitzoomen om ze te zien.

## 27.4 — Board-view: meerdere portretten op de canvas  · FEAT (later)
- status: backlog
- blockedBy: 27.1

Spike → feature: toon meerdere portretten naast elkaar op de canvas (gallery/board), pan/zoom over
de hele set; klik een portret om het te editen. Architectuur eerst (scene-graph van portret-nodes +
de camera uit 27.1); leg de aanpak vast in de Result vóór de volledige bouw.
