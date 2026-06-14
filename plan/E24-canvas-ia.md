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

## 24.1 — Canvas action-toolbar (Crop/Auto-frame/Fix angle/Flip/Restore body), tekst+icoon
- status: todo (vervangt de E22.2-cluster)
## 24.2 — AI-edits als zichtbare dropdown-knop (Colorise/Boost/generatief)
- status: todo
## 24.3 — "Adjust"-knop → popover met color-sliders
- status: todo
## 24.4 — Background → canvas-toolbar; bottom = Effects/Face/Clothing/Hair
- status: todo
## 24.7 — Name/Role: gecentreerd in rust, links bij typen, hercentreren bij commit
- status: todo
## 24.8 — Zoom: scroll/pinch = canvas-zoom; afbeelding schalen via selectie-handles
- status: todo
