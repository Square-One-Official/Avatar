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
| 27.2 | Zoom-HUD + sneltoetsen | DS/FEAT | in_progress | `v2/E27-27.2` |
| 27.3 | Transform/guides/popovers correct onder de camera | FEAT/DS | in_progress | `v2/E27-27.3` |
| 27.4 | Board-view: meerdere portretten (later) | FEAT | fase 2 done (toggle+drag+fit); fase 2b (inline-edit) backlog | `v2/E27-27.4` |
| 27.5 | Board-performance: virtualisatie + thumbnail-cache | FEAT | in_progress | `v2/E27-27.5` |

---

## 27.5 — Board-performance (virtualisatie + thumbnail-cache)  · FEAT
- status: done
- owner: FEAT (AI-agent)
- blockedBy: 27.4

Board-modus scroll/zoom is traag met alle portretten. Oorzaak: elke node decodeert de volledige
cutout (`NSImage(data:)`) bij ELKE body-evaluatie (dus elke pan/zoom-frame), én álle nodes worden
altijd gerenderd. Fix: (a) gedecodeerde + verkleinde thumbnails cachen per portret-id (één keer
decoderen); (b) virtualiseren — alleen nodes renderen die in de zichtbare viewport vallen; (c) geen
re-decode bij scroll/zoom/pan. Voor/na meten in de Result.

**Result:** drie fixes in `BoardView`:
1. **`BoardThumbnailCache`** (referentietype in `@State`): decodeert elke cutout
   één keer per portret-id én **verkleint** 'm (max ~2× de kaartmaat) i.p.v. de
   volledige cutout (vaak 1024px+) elke frame te decoderen + tekenen.
   `cardSurface` leest nu uit de cache.
2. **Virtualisatie**: `visibleNodes()` rendert alleen de nodes waarvan het midden
   binnen de (met een cel-marge verruimde) zichtbare board-rect valt — afgeleid
   uit camera + viewport. Off-screen nodes worden niet gebouwd.
3. Daardoor **geen re-decode/-render-van-alles** meer bij pan/zoom/scroll.

**Meting (voor/na, `--board-perf` decode-teller):** ná fit-on-open **18 decodes**
(één per portret, alle zichtbaar); ná **12 zoom-operaties** (6× ⌘− + 6× ⌘=, elk
met vele re-render-frames) **nog steeds 18 decodes** → 0 re-decodes. Vóór de fix
riep `cardSurface` `NSImage(data:)` aan bij élke body-evaluatie → ~18 volledige
decodes + full-res draws *per pan/zoom-frame* (de oorzaak van de traagheid).
Beide targets + alle pakkettests groen (`build-v2.sh`); board rendert correct na
de zoom-cyclus (/tmp/perf_board.png).

**Figma-TODO:** n.v.t. (interne performance). **Nuance:** de cache is per
board-sessie (id-gekeyd); een cutout-wijziging in de editor wordt opgepikt bij de
volgende board-open (BoardView wordt dan opnieuw gemaakt). Een grotere set kan
later een echte off-screen recycling/`NSCache`-limiet krijgen indien nodig.

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
- status: done
- owner: DS/FEAT (AI-agent)
- blockedBy: 27.1 (done)

Zwevende zoom-HUD (−/slider/+ en fit) met het huidige zoom-%. Sneltoetsen: ⌘0 = fit, ⌘1 = 100%,
⌘+/⌘−. Consistent met de DS-stijl.

**Result:** nieuwe DS-component `DSZoomHUD` (`AvatarUI`) — één capsule in DS-stijl
(`.ultraThinMaterial` + `Foreground.divider`-rand, identiek aan de
CanvasActionToolbar) met **− / slider / +** en een **fit-knop die tegelijk het
huidige zoom-%** toont (klik = fit/⌘0). De slider loopt **logaritmisch** tussen
`min`/`max` (0.25–4×) zodat gelijke stappen gelijke zoom-verhoudingen geven en
100% (= de fit-schaal) in het midden valt: 50%/100%/200%/400% staan op 1/4, 1/2,
3/4, 1/1. De − dimt/disabled op min, de + op max. Puur presentational: schaal in,
callbacks uit (camera-math blijft in `CanvasCamera`/`EditorView`, FEAT).
`EditorView` plaatst de HUD linksonder (tegenover undo/redo rechtsonder) en wired
'm op de camera: slider → `setCameraScale` (absolute schaal om het midden), −/+ →
`zoomCentered`, fit/% → `camera.reset()`. De sneltoetsen ⌘0(fit)/⌘1(100%)/⌘+/⌘−
zijn al in 27.1 gelegd (verborgen `keyboardShortcut`-knoppen) en blijven gelden;
de HUD-tooltips noemen ze.

**DoD/Verificatie:** beide targets bouwen + alle pakkettests groen (`build-v2.sh`
→ "alles groen"). Visuele smoke per zoomniveau (`--cam-zoom`): 50%
(/tmp/hud_050.png — slider op 1/4, "50%"), 100%/fit (/tmp/hud_100.png — slider
gecentreerd, "100%"), 200% (/tmp/hud_200.png — slider op 3/4, "200%"). De HUD
staat vrij van de bottom-toolbar (midden) en de undo/redo-cluster (rechts).
Slider→camera en knop-acties zijn dezelfde camera-paden als de
(werkende) sneltoetsen; de % + slider-positie volgen `camera.scale` correct op
elk geseed niveau. Window-capture via CGWindowID.

**Figma-TODO:** er is (nog) geen Figma-frame voor de zoom-HUD — gebouwd in de
geest van de DS-stijl (capsule/material/divider zoals de CanvasActionToolbar);
plaatsing (linksonder), de fit-knop-als-%-readout, de slider-styling (native,
action-getint) en de exacte iconen (−/+ SF Symbols) tegen een Figma-referentie
leggen zodra die er is. ⌘1 "100%" = 1× in dit camera-model (zie 27.1).

## 27.3 — Transform/guides/popovers correct onder de camera  · FEAT/DS
- status: done
- owner: FEAT/DS (AI-agent)
- blockedBy: 27.1 (done)

Handles, thirds-guides en toolbar-popovers blijven correct gepositioneerd én klikbaar op elk
zoomniveau (overlay in screen-space, niet mee-schalend tot onleesbaar/onbruikbaar). Dit lost meteen
het "transform-hoeken niet zichtbaar"-probleem op: je kunt uitzoomen om ze te zien.

**Result:**
- **Handles + selectiekader + ESC → screen-space overlay** (`CanvasTransformOverlay`, FEAT). Ze staan
  nu BUITEN de camera-transform (E27.1) én buiten de canvas-clip, getekend als `.overlay` op de
  (camera-getransformeerde) DSCanvasCard in `EditorView`. Gevolg: (a) vaste schermgrootte op élk
  zoomniveau (10pt-dots, 1pt-kader — niet meer mee-schalend); (b) een groot-geschaald onderwerp
  waarvan de hoeken buiten het frame vallen wordt weer zichtbaar én grijpbaar door met de camera uit
  te zoomen — precies het "transform-hoeken niet zichtbaar"-probleem opgelost. Posities worden uit de
  onderwerp-transform berekend en via de camera (`scale`·(p−midden)+`offset`) naar het scherm gemapt;
  de drag-ratio is invariant onder camera-zoom, en de clamp + `TransformUndo` zijn 1-op-1 die van
  E24.8. `EditorCanvasView` houdt enkel nog het onderwerp + de deselect-tap + de pan-/dubbelklik-
  gestures (E24.32 intact); `isPanning` is gelift zodat de overlay de handles tijdens het pannen even
  verbergt (E24.29-gedrag).
- **Uitlijn-gids** blijft in-scène (markeert de frame-derde, zoomt dus mee), maar de lijn-diktes
  worden door de camera-zoom gedeeld (`inverseCameraScale`) → constant dun/leesbaar op elk niveau.
- **Toolbar-popovers** zaten al in screen-space (de `CanvasActionToolbar` hangt als overlay BUITEN de
  camera-transform) → geverifieerd correct gepositioneerd + klikbaar onder zoom; geen wijziging nodig.

**DoD/Verificatie:** beide targets bouwen + alle pakkettests groen (`build-v2.sh` → "alles groen").
Visuele smoke: handles op het onderwerp bij fit (/tmp/t3_handles_100.png) en — even groot — onder 50%
camera (/tmp/t3_handles_050.png); het kernbewijs: onderwerp ×2.5 geschaald valt bij fit buiten beeld
(hoeken weg, /tmp/t3_big_fit.png) maar wordt na uitzoomen naar 45% volledig zichtbaar mét grijpbare
hoek-handles bùiten het frame (/tmp/t3_big_zoomout.png); Frame▾-popover correct + leesbaar onder 200%
(/tmp/t3_popover_200.png); uitlijn-gids dun/constant onder 200% (/tmp/t3_guide_200.png). Deselect
(klik-buiten) + ESC zijn structureel ongewijzigd (deselect-tap in EditorCanvasView, ESC-knop in de
overlay) — runtime-klikgedrag zoals in 24.32 niet-screenshotbaar. Window-capture via CGWindowID.
Smoke-haak `--scale-subject <factor>` (#if DEBUG) toegevoegd voor de uitzoom-flow.

**Figma-TODO:** handle-/kader-styling (10pt-dot, 1pt-lime-kader) en de gids-diktes tegen een
Figma-referentie leggen zodra die er is; bevestigen of de gids-extent mág mee-zoomen of óók
screen-space (vast t.o.v. het frame) moet zijn.

## 27.4 — Board-view: meerdere portretten op de canvas  · FEAT (later)
- status: fase 2 done (steps 1-3: toggle + persistente posities + fit + drag); fase 2b (inline-edit) backlog
- owner: FEAT (AI-agent)
- blockedBy: 27.1 (done)

**Fase 2 — Result (steps 1-3, geverifieerd):**
- **Model** — `Portrait2` kreeg `boardX/boardY` (node-MIDDEN, board-space),
  `boardOrder` en `boardPlaced: Bool`. De Bool i.p.v. een nan-sentinel: SwiftData's
  lichtgewicht migratie vult nieuwe Double-kolommen met **0** (niet de Swift-
  default) voor bestaande rijen — een `.nan`-sentinel stapelde daardoor álle nodes
  op (0,0); een Bool defaultt wél betrouwbaar naar false. (Gevonden + gefixt
  tijdens de smoke.)
- **Camera** — `CanvasCamera.min/maxScale` zijn nu instance (editor 0.25–4×, board
  mag verder uitzoomen, min 0.1) + `fitToContent(contentSize:in:)`. De board fit
  on-open en blijft mee-fitten op viewport-/set-wijzigingen tot de gebruiker de
  camera zelf verzet (camera ≠ laatste fit). (Fix: de eerste fit latchte op een
  pre-settle viewport → nu via een top-level GeometryReader de echte slot-maat +
  refit-tot-aanraking.)
- **BoardView** — scene-graph van node-kaarten op absolute, **persistente**
  posities (auto-grid bij eerste open, geschreven naar het model), **sleepbaar**
  (scherm-delta ÷ camera-zoom → board-space) met `BoardMoveUndo` (genest
  undo/redo). Pan/zoom = de E27.1-camera (`CanvasInteractionCatcher` + pinch +
  ⌘±/⌘0=fit). Klik een node → `model.select` + editor.
- **Echte modus-toggle** — `ShellTopBar` 'Board'-knop (`square.grid.2x2`,
  active-state) i.p.v. de DEBUG-haak; `ShellModel.isBoardMode` + `toggleBoard()`.
  De `--board`-haak blijft als smoke-ingang.

**DoD/Verificatie:** beide targets + alle pakkettests groen (`build-v2.sh`).
Smoke: board opent **gefit** met alle 18 nodes in een grid (/tmp/board_p2_fit4.png);
node-posities correct gespreid (debug-log node0=(240,263), na de stacking-fix);
de 'Board'-toggle staat in de app-bar (/tmp/board_toggle_editor.png). De camera
pan/zoom over de set is dezelfde (geverifieerde) E27.1-machinerie; ⌘-zoom werkt
(eerder getoond). Interactieve klik-naar-editen + node-drag zijn gewired op
bewezen patronen en build-geverifieerd, maar — net als 24.32 — niet
screenshot-baar in deze omgeving (synthetische clicks op SwiftUI-controls vereisen
input-rechten die hier ontbreken; de ⌘-toets-route via System Events werkt wél en
bevestigt de board-camera-sneltoetsen).

**Fase 2b (backlog):** inline-editen op de gefocuste node (editor-chrome over één
board-node, binnen de board-camera) — raakt de 27.3-overlays, apart te ontwerpen.
**Figma-TODO:** node-kaart-styling, spacing, lege-staat, de toggle-knop en het
fit-gedrag tegen een Figma-referentie leggen (geen board-frame in Figma).
Mogelijke verfijning: snap-to-grid bij drag; fit dat de tight bounds centreert
i.p.v. de symmetrische board-canvas.

Spike → feature: toon meerdere portretten naast elkaar op de canvas (gallery/board), pan/zoom over
de hele set; klik een portret om het te editen. Architectuur eerst (scene-graph van portret-nodes +
de camera uit 27.1); leg de aanpak vast in de Result vóór de volledige bouw.

**Spike-result (geverifieerd):** `BoardView` (`Avatar2/Features/Board/`) toont de hele portret-set —
dezelfde `@Query(sort:\Portrait2.updatedAt)` als de sidebar — als een scene-graph van kaart-nodes
(cutout geclipt tot `frameShape` + naam/rol) op één board, met de camera uit E27.1 (`scale`+`offset`,
`CanvasInteractionCatcher` + pinch + ⌘±/⌘0) eroverheen. Pan/zoom over de héle set werkt; klik een
node → `model.select` + terug naar de editor. Geïsoleerd achter de DEBUG-haak `--board`
(`ShellModel.showBoardSpike`), productie-editor-flow ongemoeid. Smoke: board op 1× (/tmp/board_fit.png)
en volledig in beeld na ⌘− (/tmp/board_zoomout.png — 18 nodes, mix circle/square). Beide targets +
tests groen. **Conclusie: de "nodes + camera"-aanpak klopt en is bouwrijp.**

### Vastgelegde architectuur (fase 2)

**Model — scene-graph van nodes.** Eén `Portrait2` = één node. Board-positie + z-volgorde als
nieuwe lichtgewicht velden op `Portrait2` (defaults → migratie-vrij, net als 24.16/24.31):
`boardX: Double = .nan`, `boardY: Double = .nan` (`.nan` = "nog niet geplaatst" → auto-layout vult
bij eerste board-open), `boardOrder: Int = 0`. Géén aparte board-entiteit: de set ís de scene-graph,
de sidebar-`@Query` is de single source of truth. (Alternatief — een `Board`-entiteit met node-refs —
afgewogen en verworpen: overkill voor één impliciete board; voegt join + migratie toe zonder
meerdere-boards-eis.)

**Camera = E27.1, ongewijzigd hergebruikt.** Dezelfde `CanvasCamera` + `CanvasInteractionCatcher`
+ pinch + ⌘-sneltoetsen + (27.2) `DSZoomHUD`. Eén verschil met de editor: de board moet kunnen
**uitzoomen tot < min** of een echte **fit-to-content** doen → camera-`minScale` voor de board lager
of een `fitToContent(bounds:)`-helper op `CanvasCamera` (rekent scale+offset zodat alle nodes passen;
gebruikt door ⌘0/"Fit" op de board i.p.v. `reset()` naar 1×).

**Interactie.** Pan/zoom = camera (klaar). Node-drag = een `DragGesture` per node die `boardX/Y`
schrijft (delta ÷ `camera.scale` → board-space), met snap-to-grid + `TransformUndo`-achtige undo
(nieuw `BoardMoveUndo`). Klik (zonder drag) = focus: anim de camera naar de node (`fitToContent` op
diens rect) en open de editor-overlay, of — fase 2b — **inline editen** zonder de board te verlaten
(de editor-chrome zweeft over de gefocuste node). Selectie/multi-select kan de sidebar-`selectedForBulk`
hergebruiken.

**Compositie in de Shell.** `ShellView.canvas` schakelt tussen `editorCanvas` (huidig) en `BoardView`
op een echte modus-toggle (app-bar-knop, niet de DEBUG-haak) — bv. `ShellModel.canvasMode: .editor |
.board`. De board is een aparte top-level view → geen regressie-druk op de editor. De zoom-HUD +
sneltoetsen zijn al modus-agnostisch (camera-gebaseerd).

**Fasering (fase 2).**
1. Model-velden + `fitToContent` op `CanvasCamera` + board-open op echte fit. (laag risico)
2. Node-drag + snap + undo + persistente posities. (kern)
3. Echte modus-toggle in de app-bar (board ⇆ editor) + DS-styling van de node-kaart (Figma).
4. Klik-naar-focus/inline-edit (de editor-chrome op de gefocuste node) — de zwaarste; apart te scopen.

**Risico's / open.** (a) Veel nodes × grote cutouts = geheugen → thumbnails cachen (gedeelde
thumbnail-renderer met de sidebar). (b) Node-drag mag de camera-pan (spatie-drag/scroll, screen-space
in `CanvasInteractionCatcher`) niet stelen — node-`DragGesture` op de kaart, camera-pan op lege
board-ruimte (zelfde arbitrage als 24.32 subject vs. canvas). (c) Inline-edit-architectuur (de editor
op één node binnen de board-camera) raakt 27.3-overlays → apart ontwerp. **Figma-TODO:** er is geen
board-frame in Figma — node-kaart, spacing, lege-staat, modus-toggle en fit-gedrag tegen een
Figma-referentie leggen vóór fase 3.
