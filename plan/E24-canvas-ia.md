# E24 — Canvas action-toolbar & IA-revisie (testfeedback)

Team: **FEAT**. Autonome shift 2026-06-14. **Herziet E22** (geen dubbele structuur).

Model: canvas-toolbar = scène/beeld (tekst+icoon, op het portret) · bottom-toolbar (midden) =
alleen de persoon (Effects/Face/Clothing/Hair) · top-right = app-chrome.

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
- status: DEELS — Effects-thumbnail-hover **done** (dsHoverScale). REST GEPARKEERD: Face-acties als
  thumbnail-kaarten (phosphor-icoon + label, Pro-badge bovenin, credits onderin met gradient-overlay,
  per sectie horizontaal scrollbaar) + één **gedeelde DS-thumbnail-kaart** (Effects+Face, klaar voor
  Clothing/Hair). **Plan:** maak `DSThumbnailCard` (AvatarUI of Avatar2): vierkante preview-tile
  (84–96) met optionele top-leading Pro-badge (DSProChip) + bottom credits over een
  `LinearGradient(.clear→.black)`-overlay, label eronder, selectie-ring, hover (dsHoverScale).
  Refactor EffectsPanel + FaceActionsPanel ernaar (Face: secties Retouch/Beauty, elk een
  horizontale scrollRow van kaarten). Phosphor-iconen per actie.

## 24.16 — Frame-vorm: Circle (default) / Square
- status: GEPARKEERD. **Plan:** `Portrait2.frameShape` (default `.circle`); Frame ▾ krijgt een
  Circle/Square-keuze. Canvas clipt het portret tot de vorm; `PortraitExporter` heeft de
  cirkel-mask al (E19.1 ExportShape) → koppel de persisted vorm aan export + compositing (E07.2),
  watermerk binnen de zichtbare vorm. Smoke: Square↔Circle op canvas + transparante hoeken in de
  cirkel-PNG. (Besef: dit maakt de cirkel de DEFAULT-merkvorm — bevestigen.)

## 24.14 — Adjust-waarden persistent (non-destructief)
- status: GEPARKEERD (grotere refactor). **Plan:** brightness/contrast/saturation/temperature op
  `Portrait2` (defaults 0/1/1/0); EditColorPanel bindt de sliders eraan (heropenen toont de stand);
  pas de params NIET-destructief toe op het canvas + in de export (WYSIWYG) i.p.v. bakken in
  cutoutData; meenemen in undo/redo en bij portret-wissel. Raakt canvas-rendering + export +
  EditColorPanel → dedicated story (regressie-risico).

## 24.12 — Eén DS-popover/paneel-stijl (caret weg + bottom-panelen gelijk)
- status: GEPARKEERD. **Plan:** systeem-`.popover` heeft altijd een caret → vervang door een eigen
  zwevende DS-kaart (overlay + outside-click-dismiss) zónder pijltje; maak er één gedeelde
  modifier/component van (border + radius + blur/material + rand-fade) die ZOWEL de toolbar-dropdowns
  ALS de bottom-panelen (DSEditPanel) gebruiken, zodat top en bottom identiek zijn. Grotere
  cross-cutting UI-refactor → dedicated.

## 24.8 — Zoom: scroll/pinch = canvas-zoom; afbeelding schalen via selectie-handles
- status: GEPARKEERD — grote, op zichzelf staande interactie-story. Vereist een echte selectie-/
  handle-laag op EditorCanvasView (resize-handles + drag-scale) los van de view-zoom (scroll/pinch),
  plus de referentie-interacties. Beter dedicated te bouwen + visueel te itereren dan binnen deze
  marathon af te raffelen. **Voorstel/keuze in DECISIONS-PENDING.** Huidige canvas houdt pan/zoom
  (E06.4) — geen regressie; alleen de handle-based scaling rest.
