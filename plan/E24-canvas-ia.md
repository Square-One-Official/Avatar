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
- status: todo
## 24.8 — Zoom: scroll/pinch = canvas-zoom; afbeelding schalen via selectie-handles
- status: todo
