# E05 — Main app shell

Team: **FEAT**

Figma: App / First use, Dropzone, Image added, Isolating animation, Sidebar images.

## 5.1 — First use-empty-state
- status: done
- owner: FEAT
- blockedBy: E03.2
- DoD: beide targets bouwen, tests groen

Memoji-cirkel, gefixte copy, quota pas tonen ná eerste cutout.

Notities (FEAT, bij oplevering):
- Memoji-cirkel is een gedocumenteerde placeholder (cirkel + glyph): het echte memoji-beeld
  is een Figma-asset; exporteren zodra het "Aaavatar"-bestand in de Figma desktop-app open
  staat (MCP had nu een ander bestand voor zich).
- Quota-gating: EntitlementModel.hasCompletedFirstCutout (UserDefaults shell.firstCutoutDone);
  de status-strip verbergt de quota-badge tot markFirstCutoutCompleted() — aanroepen vanuit
  de import-flow (E05.2/5.3).
- Choose file… is een bewuste no-op tot E05.2 (import → PipelineRouter); INFRA-placeholder
  ContentPlaceholderView is vervangen door ShellView (waar 5.2–5.5 in haken).

**Result:** First-use-empty-state in Avatar2/Features/Shell/ (FirstUseEmptyState + ShellView-wortel): memoji-cirkel-placeholder, review-copy ("Drop a portrait — yours or a colleague's — or choose a file"), Choose file…-knop (no-op tot E05.2), quota-badge pas ná eerste cutout via EntitlementModel; beide targets bouwen groen, packagetests groen, smoke-run OK.

## 5.2 — Import
- status: done
- owner: FEAT
- blockedBy: E02.1, E03.3
- DoD: beide targets bouwen, tests groen

Drag-drop (heel venster als target) + bestandskiezer → PipelineRouter.

Notities (FEAT, bij oplevering):
- Router heeft alleen VisionCutoutEngine geregistreerd; ORMBG (download, E08.1) en cloud
  (entitlement) haken aan via hun eigen stories.
- Review-fix toegepast: heel venster is droptarget, dashed vensterrand-glow bij hover i.p.v.
  omlijnd vierkant. Bestandskiezer via NSOpenPanel (entitlement user-selected.read-write
  stond al goed).
- Processing-staat is minimaal ("Isolating…", origineel op halve opacity) — E05.3 levert de
  echte fade-out, statuscopy en klaar/faalstaat-polish. Faalstaat (geen persoon) bestaat al
  barebones met retry-knop.
- Geslaagde cutout roept EntitlementModel.markFirstCutoutCompleted() aan → quota-badge wordt
  zichtbaar (E05.1-besluit). Geen server-side claimImport in deze story (quota-handhaving
  hoort bij de echte free-tier-flow; noteren bij E13/release-hardening).
- End-to-end drop/kiezer handmatig testen kan pas met een echte foto-sessie; engine zelf is
  unit-getest in AvatarKit (E02.1).

**Result:** Import in Avatar2/Features/Shell/ (ShellModel + uitgebreide ShellView): drag-drop over het hele venster (fileURL- én image-providers, dashed rand-glow) en NSOpenPanel-bestandskiezer → PipelineRouter(Vision) → canvasstates empty/processing/result/failed; eerste cutout flipt de quota-gating; beide targets bouwen groen, packagetests groen, smoke-run OK.

## 5.3 — Isolating-animatie
- status: backlog
- owner: —
- blockedBy: 5.2
- DoD: beide targets bouwen, tests groen

Achtergrond fade-out tijdens cutout + status op canvas ('Cutting out hair…'), incl. klaar- en
faalstaat.

**Result:** _(invullen bij done)_

## 5.4 — Sidebar (set)
- status: backlog
- owner: —
- blockedBy: E03.5
- DoD: beide targets bouwen, tests groen

Bewerkte thumbnails (Figma-foto's zijn placeholders), naam/rol, zoek, add-knop (button-component).
Canvas-overgang zonder layoutshift. SwiftData-model Portrait2, los van v1-store.

**Result:** _(invullen bij done)_

## 5.5 — Name/Role-header
- status: ready
- owner: —
- blockedBy: E03.2
- DoD: beide targets bouwen, tests groen

Met inline edit.

**Result:** _(invullen bij done)_

