# E19 — Share & sidebar

Team: **FEAT**. Autonome shift 2026-06-14.

## 19.1 — Share/export-popup (DS)
- status: done
- owner: FEAT (AI-agent, marathon)
- DoD: beide targets bouwen + tests groen + smoke

**Result:** `ExportSheet` (DS) met vorm (Square/Circle) + maat (512/1024/2048), live preview,
free-tier-watermerk-notitie, Save… (NSSavePanel) + Share (NSSharingServicePicker). `PortraitExporter.
makePNG` uitgebreid met `side` + `shape` (circle-masker); BackgroundCompositor-WYSIWYG + watermerk
(E08.2/E07.2) behouden. Share-knop opent nu de popup (ShellModel.isShowingExport) i.p.v. direct het
macOS-sheet. Smoke ✓ (`--show-export`).

**Figma-TODO:** export-popup tegen de Figma-share-flow leggen (vormen/maten/segmented-stijl).

## 19.3 — Rename-modal (DSTextField/DSMessageSheet)
- status: todo

## 19.2 — Sidebar context-menu (Rename/Delete-confirm/Export)
- status: todo

## 19.4 — Multi-select + bulk-export (rechtermuis)
- status: todo

## 19.5 — Align set / Match lighting → voortgangs-toast (DSToast)
- status: todo

## 19.6 — Sidebar hover-performance onderzoeken + fixen
- status: todo (meting voor/na in Result)
