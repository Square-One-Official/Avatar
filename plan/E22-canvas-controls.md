# E22 — Canvas-controls + top-right app-bar (IA)

Team: **FEAT**. Autonome shift 2026-06-14.

## 22.1 — Top-right app-bar
- status: done
- owner: FEAT (AI-agent, marathon)
- DoD: beide targets bouwen + tests groen + smoke

**Plan:** Sidebar/Images-toggle uit de bottom-toolbar halen naar een app-bar rechtsboven (naast
Share/Settings); bottom-toolbar wordt puur subject-edits (Edit/Effects/Face/Clothing/Hair/Background).

**Result:** ShellTopBar kreeg een Library/sidebar-toggle (`sidebar.right`, isActive=sidebar open)
vóór Share/Settings; gevoed vanuit ShellView (`model.toggleSidebar`, zichtbaar zodra er een portret
is). `EditorView.toolbarItems` filtert `.images` eruit → 6 tools. Sidebar en open paneel sluiten
elkaar uit (`onChange(isSidebarVisible)` → activeTool=nil; de toolSelection deed al het omgekeerde).
Smoke ✓ (app-bar 3 knoppen; toolbar 6 tools, geen Images).

**Figma-TODO:** app-bar-iconen naar DSIcon/Phosphor (20.3); naam/rol-plaatsing in de app-bar
bevestigen (nu gecentreerd gelaten).

## 22.2 — Canvas-floating cluster (crop/auto-frame/fix-angle/flip/restore-body)
- status: done
- owner: FEAT (AI-agent, marathon)
- DoD: beide targets bouwen + tests groen + smoke

**Plan:** Frame/positionering-acties uit het Edit-paneel halen naar een persistente cluster
rechtsboven óp het portret; glas-knoppen met tooltips.

**Result:** `CanvasControlsCluster` (glas-DSToolButtons, verticaal, topTrailing op de canvas-kaart,
boven de tap-dismiss zodat klikbaar). Crop + fix-camera-angle = stubs (dimmed, toekomstige stories);
**auto-frame** (AutoFramer) en **flip horizontal** (nieuw, undo'baar via onApplyResult) werken;
**restore-body** via de Pro-gate. Edit-paneel verloor de "Position and alignment"-sectie + Restore
body → houdt Optimise (Colorise/Boost) + Adjust (Improve lighting). Smoke ✓ (cluster op portret;
geslankt Edit-paneel).

**Figma-TODO:** "kleine DS-popover per knop" — nu hover-tooltips; bevestig of er een echte popover
(met opties, bv. crop-ratio's) moet komen. Cluster-iconen naar DSIcon (20.3). Crop + fix-camera-
angle = nog te bouwen (eigen stories).

## 22.3 — Edit-paneel = live color-sliders + AI-dropdown
- status: todo
