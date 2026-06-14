# E24 — Canvas action-toolbar & IA-revisie (testfeedback)

Team: **FEAT**. Autonome shift 2026-06-14. **Herziet E22** (geen dubbele structuur).

Model: canvas-toolbar = scène/beeld (tekst+icoon, op het portret) · bottom-toolbar (midden) =
alleen de persoon (Effects/Face/Clothing/Hair) · top-right = app-chrome.

## 24.18 — Panel-fade weg (alle menu's) + frame-ademruimte
- status: done
- owner: FEAT (AI-agent, marathon 2)

**Result (A — panel-fade):** de `dsEdgeFade` (24.12) is uit `DSEditPanel` gehaald — die kapte
boven/onder content af op álle bottom-panelen. Centraal opgelost (DSEditPanel) → geldt voor
Effects/Face/Clothing/Hair tegelijk. Inhoud is nu overal volledig zichtbaar; bij overflow scrollt het
paneel (scrollbar + paneel-rand = de enige rand-affordance). (De `dsEdgeFade`-helper blijft ongebruikt
in DSPanelSurface — restpunt: opruimen bij rustige refactor.)

**Result (B — frame-ademruimte):** gedeelde `FramingConstants.frameFitPadding` (0.85).
`EditorCanvasView.fitTransform` ging van FILL (`max`, edge-to-edge) → padded FIT (`min × 0.85`),
gelijk aan `AutoFramer.fitTransform` (die de constante nu ook gebruikt). Het onderwerp houdt zo
standaard marge binnen het frame in circle én square. WYSIWYG meegenomen: de export-fallbacks voor
"geen transform" (`PortraitExporter.transparentSquare` + `BackgroundCompositor.resolvedPlacement`,
AvatarKit) gingen mee van FILL → padded FIT (`BackgroundCompositor.fitPadding = 0.85`, moet gelijk
blijven aan de app-constante). Geldt voor vers geïmporteerde portretten (scale 0); eerder
edge-to-edge-getransformeerde portretten houden hun stand tot reset/auto-frame.

**DoD/Verificatie:** beide targets + alle pakkettests groen (build-v2.sh; AutoFramer-noFace-test
blijft 0.85 → ongewijzigd). Screenshots: Face-paneel volledig zichtbaar zonder fade-clipping
(/tmp/panel_face_2418.png); circle-frame met onderwerp-marge + zichtbare hoek-handles
(/tmp/margin_circle_2418.png). Smoke-haak (#if DEBUG): `--reset-transform` (toont de padded
fit-fallback). Part A geldt centraal voor alle 4 de bottom-panelen; Part B is frame-agnostisch
(zelfde scale-math, circle + square).

**Figma-TODO:** exacte frame-ademruimte-marge (nu 0.85 / 15%) bevestigen tegen de referenties; bevestig
of een decoratieve buitenrand-fade gewenst is (nu volledig verwijderd).

## 24.17 — Canvas-audit (nieuwe indeling)
- status: ready (na 24.18) — visuele audit van de canvas na de E24-revisie (toolbar/panelen/frame/
  zoom/handles) in beide frame-vormen + beide themes; losse fixes loggen.

## 24.5 — Sidebar-toggle uiterst rechts in de app-bar
- status: done
**Result:** ShellTopBar-app-chrome rechts = Share → Settings → **Library (uiterst rechts)**. Smoke ✓.

## 24.6 — Counter op eigen rij ónder de traffic-lights (~12px van links)
- status: done (regressie t.o.v. 18.19 teruggedraaid op verzoek)
**Result:** ShellTopBar weer VStack: rij 1 = app-chrome (h52), rij 2 = counter+Upgrade met leading
gap-3 (~12px). Smoke ✓.

## 24.1–24.4 — Canvas action-toolbar + bottom-toolbar = persoon
- status: done
- owner: FEAT (AI-agent, marathon)
- DoD: beide targets bouwen + tests groen + smoke

**Result:** `CanvasActionToolbar` (glas-capsule, tekst+icoon) bovenaan het portret, vervangt de
E22.2-cluster: **24.1** Crop (stub)/Auto-frame/Fix angle (stub)/Flip/Restore body; **24.2** AI als
zichtbare dropdown (Improve lighting/Colorise/Boost, Pro-labels); **24.3** Adjust → popover met de
color-sliders (`EditColorPanel(showAutoEnhance: false)` = sliders + Reset); **24.4** Background →
popover in de canvas-toolbar. Bottom-toolbar gefilterd tot **Effects/Face/Clothing/Hair**
(Edit/Background/Images eruit). CanvasControlsCluster verwijderd. Smoke ✓ (toolbar bovenaan portret;
4 person-tools onderin).

**Restpunt:** de oude `.edit`/`.background` panel-branches in EditorView zijn nu dood (niet meer
selecteerbaar) maar onschadelijk — opgeruimd laten tot een rustige refactor.
**Figma-TODO:** canvas-toolbar tegen de referenties leggen (groepering, tekst+icoon-stijl, popover-
styling Adjust/Background/AI); iconen → DSIcon/Phosphor (E20/21).
## 24.7 — Name/Role: gecentreerd in rust, links bij typen, hercentreren bij commit
- status: done
- owner: FEAT (AI-agent, marathon)

**Result:** DSInlineEditLabel kreeg `onEditingChanged`; PortraitHeader schakelt de VStack- +
frame-uitlijning tussen `.center` (rust) en `.leading` (typen), geanimeerd. Bij commit/blur
(endEditing) hercentreert het. Build groen. (Edit-staat niet synthetisch te smoken; rust =
gecentreerd zichtbaar in alle smokes.)

## 24.9 — Canvas-toolbar verslanken (8 → 4 items)
- status: done
- owner: FEAT (AI-agent, marathon)
- DoD: beide targets bouwen + tests groen + smoke (beide canvas-staten)

**Plan:** Framing-acties bundelen onder "Frame ▾"; "Restore body" naar de AI ▾-dropdown; top-level
= Frame ▾ · Background · Adjust · AI ▾.

**Result:** `CanvasActionToolbar` herschreven naar 4 top-level items. **Frame ▾** = Auto-frame &
center (primair, eerst) / Crop (stub) / Fix camera angle (stub) / Flip horizontal — eigen DS-popover
met icoon-rijen + hover. **AI ▾** = Improve lighting / Colorise (Pro) / Boost (Pro) / **Restore body**
(Pro, verplaatst — generatief). Background + Adjust blijven directe popover-knoppen (geen chevron).
Alles via dezelfde DS-popover (geen native menu), met hover-highlight. Smoke ✓ (slanke 4-knoppen-
balk; Frame- en AI-dropdown).

**Zichtbaarheids-/expand-keuze (Result):** de toolbar wordt alléén gerenderd als er een portret op
de canvas staat (result-state = portret geselecteerd) en is dan de slanke, altijd-zichtbare
4-knoppenset — géén hover-only. De "expand" is puur de Frame/AI-dropdown (secundaire acties);
er is bewust geen aparte hover-expand-animatie (rust = de 4 knoppen, discoverability behouden).
In de empty/first-use-state (geen portret) is er geen toolbar.

**Figma-TODO:** Frame-icoon (nu "crop") + de dropdown-iconen → DSIcon/Phosphor; toolbar-groepering
tegen de referenties bevestigen.

## 24.10 — Background-swatch hover afgekapt
- status: done. scrollRow kreeg verticale + leading-padding zodat de hover-scale binnen de scroll-/
  mask-grens past. Build groen.

## 24.13 — Quota-badge uit Settings + counter-padding (diagnose + meting)
- status: done
- owner: FEAT (AI-agent, marathon)

**Diagnose (oorzaak):** de counter stond niet 12px van de VENSTERrand maar van een GECENTREERDE
kolom. Reden: `ShellTopBar` wordt geplaatst met `.overlay(alignment: .top)`, dat een *content-sized*
view centreert; de VStack vulde de breedte niet gegarandeerd, dus de `leading`-inset telde vanaf het
midden i.p.v. de vensterrand. (Niet de traffic-light-zone; de counter staat al op een eigen rij
eronder.)

**Fix:** `ShellTopBar`-VStack `.frame(maxWidth: .infinity, alignment: .leading)` → de leading-inset
(gap-3) telt nu vanaf de echte vensterrand. Quota-badge gegate op `!isSettingsActive` → verschijnt
niet meer in Settings.

**Meting (geverifieerd, niet "zou moeten"):** pixel-scan op de witte counter-tekst →
**leftmost = 13pt** van de vensterrand (target ~12 = gap-3). Settings-screenshot: geen quota-badge
linksboven (alleen de gear rechtsboven). Screenshots: /tmp/counter_fixed2.png + /tmp/settings_noquota.png.

## 24.7-revisie — Name/Role-veld blijft vast; alleen de tekst lijnt uit
- status: done
- owner: FEAT (AI-agent, marathon)

**Result:** Eerdere 24.7 verschoof het hele veld (fout). Nu: `DSInlineEditLabel(fixedWidth:)` →
het veld heeft een VASTE breedte (240) en blijft gecentreerd staan; het beweegt niet bij focus.
De tekst centreert in rust en lijnt **links** uit tijdens typen (frame-alignment center↔leading),
en centreert weer bij commit/blur. PortraitHeader: container-alignment-switch teruggedraaid, beide
velden vaste breedte. Smoke: rust = Name/Role gecentreerd ✓ (typen/commit = logisch geverifieerd
via de vaste-breedte-frame; klein veld niet synthetisch te focussen).

## 24.15 — Effects-hover + Face thumbnail-kaarten
- status: done
- owner: FEAT (AI-agent, marathon 2)

**Result:** nieuwe gedeelde **`DSThumbnailCard`** (AvatarUI) — vierkante preview-tile met optionele
top-leading Pro-badge (DSProChip), credit-kost onderin over een `LinearGradient(.clear→.black)`-
overlay, label eronder, selectie-ring en `dsHoverScale`. Icoon-agnostisch (generic `Icon`-view),
omdat Phosphor aan het app-target hangt, niet aan AvatarUI — Effects/Face leveren het icoon.
`EffectsPanel.styleCard` refactored ernaar (geen per-kaart credits/Pro; kost staat in de header).
`FaceActionsPanel` herschreven: secties **Retouch** (One click retouch, magicWand, lokaal/aan-uit)
en **Beauty** (Whiten teeth/Apply make-up/Reduce wrinkles — tooth/palette/smiley, Pro-badge +
"4 credits"), elk een horizontaal scrollbare rij kaarten. Scroll-rijen kregen padding zodat de
hover-scale + Pro-badge niet tegen de grens clippen (24.10-patroon).

**DoD/Verificatie:** beide targets bouwen + alle pakkettests groen (build-v2.sh, incl. AvatarUI-
package-compile van de nieuwe component). Smoke: Face-paneel (`--open-panel face`) toont de kaarten
exact volgens spec — Retouch-kaart (icoon+label, geen badge/credits) + 3 Beauty-kaarten met
phosphor-icoon, groene Pro-badge bovenin, "4 credits" onderin over de gradient, label eronder,
horizontaal scrollbaar (/tmp/face_2415.png). Effects gebruikt dezelfde `DSThumbnailCard` (build-
geverifieerd; dedicated Effects-screenshot werd geblokkeerd door een fullscreen-video op het scherm
ten tijde van capture — niet-codegerelateerd).

**Restpunt:** `EditorActionList`/`EditorAction` (Avatar2/Features/Editor) zijn nu ongebruikt (Face was
de laatste gebruiker) — onschadelijk; opruimen bij een rustige refactor.
**Figma-TODO:** kaart-maten/tinten + de gekozen Phosphor-glyphs per Face-actie (tooth/palette/smiley/
magicWand) tegen de referenties leggen; echte Effects-thumbnails komen later (ASSETS.md).

## 24.16 — Frame-vorm: Circle (default) / Square
- status: done
- owner: FEAT (AI-agent, marathon 2)

**Result:** `Portrait2.frameShapeRaw` (default `ExportShape.circle.rawValue`) + computed
`frameShape`-accessor. Frame ▾ kreeg een **Shape**-sectie (Circle/Square, checkmark op de actieve);
`CanvasActionToolbar` neemt `frameShape` + `onSetFrameShape`. Canvas clipt achtergrond + cutout via
`EditorView.frameClipShape` (`AnyShape(Circle())`/`Rectangle()`) → cirkel = transparante hoeken die
het kaart-/dot-grid tonen, matcht de export-mask. Export: `ExportSheet` defaultt nu naar
`portrait.frameShape`; de quick-export-haak geeft `shape: portrait.frameShape` mee; `makePNG`'s
cirkel-mask bestond al (E19.1). Watermerk: bij cirkel gecentreerd + ~10% van onder binnen de
zichtbare vorm (i.p.v. de hoek die buiten de cirkel viel). `setFrameShape` persisteert + `touch()`,
geanimeerd; geen undo (lichte toggle).

**DoD/Verificatie (geverifieerd):** beide targets bouwen + alle pakkettests groen (build-v2.sh).
Export-pixelscan: cirkel-PNG → 4 hoeken alpha=0 (transparant), rand-middens + centrum alpha=255
(ingeschreven cirkel); vierkant-PNG → alle hoeken alpha=255 (vol). Canvas-screenshots: cirkel =
portret rond geclipt + Frame ▾ Shape-sectie met Circle gecheckt (/tmp/canvas_circle_2416.png);
vierkant = vol vierkant (/tmp/canvas_square_2416.png). Smoke-haken (#if DEBUG): `--frame-circle`/
`--frame-square`. Dev-store na afloop teruggezet op circle (default).

**WACHT-OP-THIERRY (niet-blokkerend):** cirkel is nu de DEFAULT-merkvorm (ook voor bestaande rijen
via de migratie-default) — bevestigen. Zie DECISIONS-PENDING.
**Figma-TODO:** Shape-iconen (Phosphor `.circle`/`.square`) + de Shape-sectie-styling tegen de
referenties leggen; cirkel-watermerk-positie (10%-van-onder) visueel finetunen.

## 24.14 — Adjust-waarden persistent (non-destructief)
- status: done
- owner: FEAT (AI-agent, marathon 2)

**Result:** `Portrait2` kreeg `adjustBrightness/Contrast/Saturation/Temperature` (defaults
0/1/1/0) + waarde-object `PortraitAdjust` (+ `adjust`-accessor). De Adjust-laag is ORTHOGONAAL:
`cutoutData` blijft rauw; destructieve ops (Effects/Clothing/Hair/Flip/Retouch/Boost) werken op
`rawCutout`; de params zijn altijd de bovenste niet-destructieve filterlaag. Canvas
(`ShellModel.select/applyEffectResult/commitAdjust/refreshCanvasFromSelection` → `adjustedImage`)
én export (`PortraitExporter.makePNG` past `colorAdjust` toe vóór compositing) = WYSIWYG.
`EditColorPanel` neemt nu de rauwe `source` + `initial`-params (heropenen toont de stand) en commit
param-delta's; nieuwe `AdjustUndo` registreert before→after param-snapshots (Cmd-Z/redo). Twee
undo-stacks blijven onafhankelijk → geen dubbeltelling.

**DoD/Verificatie (geverifieerd, niet "zou moeten"):** build-v2.sh groen — beide targets bouwen +
alle pakkettests (27 AvatarUI + AvatarKit + Avatar2). Smoke (`--seed-adjust`/`--reset-adjust`/
`--show-adjust-popover`, allemaal #if DEBUG): (1) Adjust-popover toont 4 sliders + Reset; (2)
seeded stand niet-destructief op canvas + persisteert: export-meanRGB ging van baseline
(164.6,84.2,48.6) → warm (183.0,101.2,67.8), en een PLAIN relaunch zónder seed exporteerde
identiek (183.0,101.2,67.8) = params overleefden de SwiftData-store; (3) heropenen toont de stand
(sliders niet-neutraal in screenshot warm vs. neutraal+Reset-disabled na reset); (4) Reset zet terug
naar de rauwe basis (raw cutout intact). Screenshots: /tmp/canvas_adjust_2414.png (warm) +
/tmp/canvas_reset_2414.png (neutraal). Dev-store na afloop teruggezet op neutraal.

**Figma-TODO:** (a) Adjust-popover gebruikt nog de systeem-`.popover` mét caret → 24.12. (b) geen
DS-slider-component; SwiftUI `Slider` met DS-tint (bestaande TODO in EditColorPanel-header).
- **Plan (gekozen aanpak):** Adjust-laag is ORTHOGONAAL aan de cutout. `cutoutData` blijft de RAUWE
  cutout; destructieve ops (Effects/Flip/Retouch/Boost/Clothing/Hair) bewerken de rauwe cutout;
  de Adjust-params (`adjust*` op Portrait2) zijn altijd de bovenste niet-destructieve filterlaag.
  Canvas + export = `colorAdjust(rawCutout, params)`. Twee undo-stacks blijven onafhankelijk (de één
  swapt cutoutData, de ander de params) → geen dubbeltelling. Per-pixel color-adjust commuteert met
  flip; voor cloud-ops is adjust een top-filter (Photoshop-adjustment-layer-model).
- **(oorspr. plan)** brightness/contrast/saturation/temperature op
  `Portrait2` (defaults 0/1/1/0); EditColorPanel bindt de sliders eraan (heropenen toont de stand);
  pas de params NIET-destructief toe op het canvas + in de export (WYSIWYG) i.p.v. bakken in
  cutoutData; meenemen in undo/redo en bij portret-wissel. Raakt canvas-rendering + export +
  EditColorPanel → dedicated story (regressie-risico).

## 24.12 — Eén DS-popover/paneel-stijl (caret weg + bottom-panelen gelijk)
- status: done
- owner: FEAT (AI-agent, marathon 2)

**Result:** nieuw gedeeld oppervlak **`dsPanelSurface(cornerRadius:)`** (AvatarUI): in-window-blur +
donkere card-tint + dunne divider-rand + radius + schaduw. Plus **`dsEdgeFade()`** (zachte verticale
rand-fade voor scrollbare inhoud). `DSEditPanel` gebruikt nu `dsPanelSurface(xl4)` + `dsEdgeFade()`
op de scroll (kreeg dus de rand + fade). `CanvasActionToolbar` vervangt de vier systeem-`.popover`s
(altijd-caret) door caret-loze, zwevende DS-kaarten: per-knop `.overlay(alignment:.top)` met
`.offset(y:44)` onder de capsule, `dsPanelSurface(xl)` — exact hetzelfde oppervlak als de bottom-
panelen. De open-staat is gelift naar `EditorView.canvasMenu` (`CanvasToolbarMenu?`-binding) zodat de
bestaande canvas-tap-dismiss de dropdown óók sluit (outside-click); een tweede klik op de knop of een
menukeuze sluit 'm ook. Animatie: fade+scale vanaf de top.

**DoD/Verificatie (geverifieerd):** beide targets bouwen + alle pakkettests groen (build-v2.sh).
Screenshots: Frame-dropdown nu caret-LOOS (vgl. de 24.16-cirkel-shot mét systeem-caret) — zwevende
kaart met rand + glas, Shape-sectie intact (/tmp/dd_frame_2412.png); Face bottom-paneel heeft nu
dezelfde rand + top-edge-fade (/tmp/dd_facepanel_2412.png) → top en bottom identiek. Outside-click-
dismiss = logisch geverifieerd (canvas-tap nuleert `canvasMenu`, gedeeld met de paneel-dismiss).

**Figma-TODO:** dropdown-radius (xl) vs. paneel-radius (xl4) — bevestigen of ze écht gelijk moeten;
exacte fade-lengte + rand-opaciteit tegen de referenties leggen.

## 24.8 — Zoom: scroll/pinch = canvas-zoom; afbeelding schalen via selectie-handles
- status: done (default; open keuzes blijven bij Thierry — DECISIONS-PENDING)
- owner: FEAT (AI-agent, marathon 2)

**Result:** view-zoom losgekoppeld van subject-schaal. **VIEW-zoom** (efemeer, niet persistent,
1×–4×) zit nu op pinch/scroll/dubbelklik én op een nieuwe **zoom-HUD** (−/slider/+/fit) onderaan het
canvas — `viewZoom` leeft in `EditorView` (binding) zodat de HUD búiten de frame-clip (24.16) rendert;
`EditorCanvasView` past 'm toe via `scaleEffect(anchor:.center)`. **SUBJECT-schaal** gaat nu via
**selectie-handles**: 4 hoek-dots + selectiekader op het onderwerp; drag = aspect-locked schalen om
het onderwerp-midden, op `Portrait2.scale`, geclampt aan de fill-fit-band (E06.4), undo'baar ("Scale").
De handles renderen BUITEN de frame-clip (het beeld clipt EditorCanvasView intern) zodat ze ook bij
een cirkel-frame zichtbaar/bruikbaar zijn. Pan/snap/haptics (E06.4 drag) ongewijzigd → geen regressie.

**Default-keuzes gemaakt (open voor Thierry, zie DECISIONS-PENDING):** (a) 4 HOEK-handles (geen
zijkanten), (b) aspect-lock AAN, (c) schaal op de bestaande `Portrait2.scale` (geen aparte
selectie-transform), (d) één laag/onderwerp.

**DoD/Verificatie:** beide targets + alle pakkettests groen (build-v2.sh). Screenshots: default =
selectiekader + hoek-handles op het onderwerp + zoom-HUD onderaan (/tmp/zoom_default_248.png);
`--seed-viewzoom 2.2` = onderwerp ingezoomd-gecropt in de cirkel, HUD-slider op ~2.2×
(/tmp/zoom_2x_248.png). Handle-drag = logisch geverifieerd (gesture gewired; niet synthetisch te
slepen). Smoke-haak (#if DEBUG): `--seed-viewzoom <n>`.

**Figma-TODO:** handle-stijl (dot-grootte/kleur), HUD-stijl + fit-icoon, en of de view-zoom ook moet
kunnen pannen wanneer ingezoomd — tegen de referenties leggen zodra die er zijn.
