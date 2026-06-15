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
| 27.4 | Board-view: meerdere portretten (later) | FEAT | in_progress (spike) | `v2/E27-27.4` |

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
- status: in_progress (spike — architectuur + read-only proof)
- owner: FEAT (AI-agent)
- blockedBy: 27.1 (done)

Spike → feature: toon meerdere portretten naast elkaar op de canvas (gallery/board), pan/zoom over
de hele set; klik een portret om het te editen. Architectuur eerst (scene-graph van portret-nodes +
de camera uit 27.1); leg de aanpak vast in de Result vóór de volledige bouw.
