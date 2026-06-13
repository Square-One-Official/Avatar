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
- status: done
- owner: FEAT (AI-agent, marathon 2026-06-13)
- blockedBy: 6.1
- DoD: beide targets bouwen, tests groen

Beide staan in het design (10 jun); bouwen conform Figma, op canvas-niveau.

**Plan:**
1. Frame App / Edit (4008:7340): undo/redo zijn twee extra cirkels ín de bottom-toolbar;
   integratie in DSBottomToolbar = AvatarUI (verboden terrein deze sessie) → DS-story E03.19
   aangemaakt; tot die landt staan ze als losse DSToolButtons direct naast de toolbar
   (zelfde glass-idioom), gedocumenteerde tijdelijke plaatsing.
2. Undo-mechaniek: native NSUndoManager (environment) — EditorCanvasView registreert per
   afgerond gebaar (drag/zoom) een before-snapshot van de Portrait2-transform; AutoFramer
   registreert vóór het schrijven. Cmd+Z/Shift-Cmd+Z en het Edit-menu werken gratis mee.
3. Hold-to-compare: portret-thumb rechtsboven (Frame 27) — ingedrukt houden toont de
   ORIGINELE importfoto op het canvas. Daarvoor Portrait2.originalData (externalStorage,
   optional; migratie default nil) gevuld bij import; zonder origineel (bestaande rijen)
   blijft de knop verborgen.
4. Smoke (wachtrij): toolbar met undo/redo-cirkels, compare-thumb zichtbaar, undo na
   auto-frame herstelt de vorige transform.

**Result:** Undo/redo via native NSUndoManager (TransformUndo: canonieke recursieve before→after-registratie per afgerond gebaar in EditorCanvasView en per auto-frame); knoppen als glass-cirkels rechtsonder (tijdelijke plaatsing, DS-integratie = E03.19), enable-state via NSUndoManager-change-notificaties (UndoManager is niet observable). Hold-to-compare: Portrait2.originalData (externalStorage optional, gevuld bij import; migratie nil → knop verborgen) toont tijdens indrukken de originele foto. Smoke-run (ontgrendeld): drag verschuift het portret, Cmd+Z reverteert aantoonbaar (undo-mechaniek bevestigd; de knoppen delen exact dezelfde undoManager-aanroep en enable/disablen correct), compare-knop correct verborgen voor de gemigreerde testrij zonder origineel. Beide targets bouwen groen, suite groen.

## 6.3 — Edit-paneel
- status: done
- owner: FEAT (AI-agent, marathon 2026-06-13)
- blockedBy: 6.1, E03.4
- DoD: beide targets bouwen, tests groen

Actielijst (zakelijke acties boven beauty-acties), elke actie via ProChip. Acties mogen stubs zijn.
Let op: paneel krijgt later nog een design-iteratie — vervangbaar bouwen.

**Plan:** EditActionsPanel (Features/Editor/) — secties Position → Optimise → Retouch (zakelijk
boven beauty, spec); rijen uit het frame App / Edit (4014:10761) als pill-rijen in een
2-koloms-grid; cloud/generatieve acties krijgen de DSProChip-gating-indicator (exacte
credit-labels uit CreditMeter E14.3 later), lokale acties niet. Eén actie live: "Auto-crop &
center" → AutoFramer (E06.5); rest stubs (gedimd, disabled). Vervangbaar opgezet voor de
latere design-iteratie.

**Result:** EditActionsPanel in het Edit-paneel: secties Position and alignment → Optimise → Retouch (zakelijk boven beauty, gedocumenteerde herordening t.o.v. de frame-volgorde), pill-rijen in een 2-koloms-grid uit frame 4014:10761; cloud/generatieve acties met DSProChip-gating (credit-labels later uit CreditMeter E14.3), lokale acties zonder. "Auto-crop & center" live op AutoFramer (E06.5); overige acties stubs (gedimd/disabled), vervangbaar voor de latere design-iteratie. Smoke-run (ontgrendeld): alle drie de secties renderen met chips en active/disabled-states. Beide targets bouwen groen, suite groen.


## 6.4 — Canvas-transform: pan/zoom/snap
- status: done
- owner: AI (autonome sessie 2026-06-13)
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

**Plan:**
1. Portrait2 + `offsetX/offsetY/scale` (Double, default 0; scale 0 = "nog geen transform" →
   canvas toont berekende fill-fit; lichtgewicht migratie). Gestures schrijven echte waarden
   + touch().
2. `EditorCanvasView` in Features/Editor/: 1024-units canvasruimte (v1-conventie, maakt de
   AutoAligner-port in 6.5 1-op-1), drag = pan met shift-as-constraint, snap met hysterese
   (enter 12 / exit 24 canvas-units) + NSHapticFeedbackManager (.alignment bij snap,
   .generic per 24 units), pinch = zoom en scroll = zoom (NSEvent-monitor onder hover),
   0,5×–3× om het canvasmidden, dubbelklik = reset naar fill-fit (6.5 vervangt dit door
   echt auto-frame).
3. Snapdoelen: canvas-midden-X (v1-port). Y: zonder oog-metadata (komt met 6.5/
   ProcessedSubject) snapt het beeldmidden op canvas-midden-Y zoals v1; de guide toont wél
   de standaard-ooglijn (0.37, v1-doelwaarde — de ~44% uit de spec is de benadering) zodat
   handmatig uitlijnen op de lijn kan. 6.5 verlegt de Y-snap naar de ooglijn zodra
   eyeCenter bekend is — genoteerd in 6.5.
4. Guide-overlay: v1 AlignmentGuideOverlay geport naar DS-stijl (action-lime i.p.v. cyaan,
   zelfde geometrie: ooglijn + oogmarkers + hoofd-ovaal op 0.12-interoog), fade-in bij
   dragstart, fade-out bij loslaten (0,15 s).
5. FramingConstants (0.12 / 0.37 / 0.50, editCanvas 1024) als gedeelde port in
   Features/Editor/ — 6.5 hergebruikt ze voor de AutoAligner.
6. DoD incl. visuele smoke-run via de --show-settings-achtige route (launch + rendercheck
   met transform).

**Result:** EditorCanvasView (Features/Editor/) vervangt de statische fill in de canvaskaart: drag-pan met shift-as-constraint en v1-snapmechanics (hysterese 12/24, .alignment-tick bij snap, .generic per 24 units), pinch- én scroll-zoom 0,5×–3× om het canvasmidden (NSEvent-monitor onder hover), dubbelklik = fill-fit-reset (E06.5 maakt er echt auto-frame van), guide-overlay in DS-lime (midden-X, standaard-ooglijn 0.37, oogmarkers, hoofd-ovaal) met 0,15s-fade tijdens drag; transform persistent op Portrait2.offsetX/offsetY/scale (scale 0 = fill-fit, lichtgewicht migratie) met touch() per afgerond gebaar; FramingConstants = 1-op-1 v1-port. Beide targets bouwen groen, packagetests groen, rendercheck gedaan (canvas + dot-grid + transform).

## 6.5 — Automatic framing-actie
- status: done
- owner: FEAT (AI-agent, marathon 2026-06-13)
- blockedBy: 6.4
- DoD: beide targets bouwen, tests groen
- Context: besluit Thierry 2026-06-13. GEEN Figma-afhankelijkheid (zelfde spec-bron als 6.4). v1 AutoAligner is de referentie: neem de getunede doelwaarden over — niet opnieuw raden. ProcessedSubject (eyeCenter/interEyeDistance/bodyBottomY) zit in AvatarKit.

Spec (Thierry): "Automatic framing"-actie in het Edit-paneel — ogen op de standaard-ooglijn
(~44% van boven), horizontaal centreren op eyeCenter, schalen op interEyeDistance als vast
percentage van de canvasbreedte; geanimeerde overgang.

**Plan:**
1. Correctie board-context: ProcessedSubject leeft in v1 Avatar/Services, níét in AvatarKit —
   de detectie wordt als FEAT-helper geport (Features/Editor/AutoFramer.swift) met Vision
   direct (VNDetectFaceLandmarksRequest pupil-centroids, VNDetectHumanBodyPoseRequest +
   alpha-scan-fallback voor bodyBottomY).
2. AutoFramer.computeTransform = 1-op-1 v1 AutoAligner-math (eye-based: ooglijn 0.37,
   interoog 0.12; face-rect-fallback 0.38/0.42; body-overshoot 0.03 als minimum-scale);
   doelwaarden uit FramingConstants (uitgebreid met de fallback-constanten).
3. Actie schrijft het transform op Portrait2 binnen withAnimation — het E06.4-canvas
   observeert het model en animeert vanzelf. Dubbelklik (E06.4) gaat van fill-fit-reset
   naar echt auto-frame; knop "Automatic framing" komt alvast in de Edit-paneel-stub
   (E06.3 neemt hem op in de echte actielijst).
4. Unit-tests op de pure transform-math in het Avatar2-testtarget (eye-based, fallback,
   body-overshoot, no-face → fit).

**Result:** AutoFramer (Features/Editor/) — v1 AutoAligner-math 1-op-1 (eye-based ooglijn 0.37 / interoog 0.12, face-rect-fallback 0.38/0.42, body-overshoot 0.03) + Vision-detectie (pupil-centroids, body-pose, alpha-scan-fallback). "Automatic framing"-knop in het Edit-paneel én dubbelklik op het canvas (E06.4) roepen hem aan; geanimeerde overgang via withAnimation op de Portrait2-transform; undo-stap geregistreerd. 4 unit-tests op de pure math (groen). Smoke-run (ontgrendeld): knop aanwezig in Edit-paneel, transform animeert. Beide targets bouwen groen, volledige suite groen (de keychain-testfaal was scherm-lock, nu groen).
