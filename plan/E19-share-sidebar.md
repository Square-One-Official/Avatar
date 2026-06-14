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

## 19.3 — Rename-modal (DSTextField)
- status: done
- owner: FEAT (AI-agent, marathon)

**Result:** `RenameSheet` (DS): DSTextField op `portrait.name`, Save/Cancel, kruis. Getriggerd vanuit
het context-menu (19.2). SwiftData-autosave persisteert. Build groen. (Modal niet synthetisch te
smoken — zelfde sheet-patroon als de ge-smokete ExportSheet.)

## 19.2 — Sidebar context-menu (Rename/Export/Delete-confirm)
- status: done
- owner: FEAT (AI-agent, marathon)

**Result:** `.contextMenu` op elke DSSidebarRow → Rename (RenameSheet), Export… (shell selecteert +
opent de export-popup via `onExport`), Delete (destructive → `confirmationDialog` "This can't be
undone" → `modelContext.delete`). Build groen. (Rechtermuis/modal niet synthetisch te smoken.)
**Figma-TODO:** context-menu-styling + delete-confirm tegen Figma bevestigen.

## 19.4 — Multi-select + bulk-export (rechtermuis)
- status: todo

## 19.5 — Align set / Match lighting → voortgangs-toast (DSToast)
- status: done
- owner: FEAT (AI-agent, marathon)

**Result:** SidebarView meldt set-brede voortgang via `onSetBusy(String?)`; ShellView toont een
DSToast rechtsonderin ("Aligning set…" / "Matching lighting…") met slide-in/out, en wist 'm bij
afronding (defer). De inline knop-labels blijven als secundaire indicatie. Build groen. (Vereist
een set ≥2 + klik → niet synthetisch ge-smoket; zelfde DSToast-patroon als elders.)

## 19.6 — Sidebar hover-performance onderzoeken + fixen
- status: done
- owner: FEAT (AI-agent, marathon)

**Result:** Oorzaak gevonden: `thumbnail(for:)` deed `NSImage(data: portrait.cutoutData)` — een
full-res PNG-decode — bij ÉLKE rij-render. DSSidebarRow her-rendert op hover (opacity-state), dus
elke muisbeweging over de lijst decodeerde meerdere full-res PNG's → hover-lag. Fix:
`SidebarThumbnailCache` (NSCache) decodeert + downscalet één keer per (portret, `updatedAt`) naar
96px en hergebruikt die. Build groen. **Meting:** geen Instruments in deze omgeving — kwalitatief:
vóór = N full-res decodes per hover-render; ná = 0 (cache-hit, kleine bitmap). Verse thumb bij edit
via de updatedAt-key.
