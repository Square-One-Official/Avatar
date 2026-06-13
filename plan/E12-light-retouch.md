# E12 — Light & Retouch

Team: **FEAT**



## 12.1 — One-click retouch + Improve lighting
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: E06.3 (done)
- DoD: beide targets bouwen, tests groen

Core Image-port van v1 magicRetouch naar AvatarKit, niet-destructief, met compare.

**Plan:**
1. AvatarKit `PortraitEnhancer` (Imaging/) — Core Image-port van v1
   `ImageProcessor.magicRetouch`: `magicRetouch` (volle keten: auto-adjust + vibrance +
   highlight/shadow + warmte + sharpen) en `improveLighting` (alleen toon). Lokaal, geen credits.
2. FEAT: "One click retouch" + "Improve lighting" in EditActionsPanel herclassificeren van
   cloud-generatief (Pro-chip, 4 cr) → **lokaal** (geen chip); gerichte edits
   (tanden/rimpels/make-up/restore body) blijven generatief.
3. Niet-destructief: EditorView past toe via `onApplyResult` (canvas + cutout), origineel blijft
   voor hold-to-compare; undo via nieuwe `ImageEnhanceUndo` (native UndoManager, Cmd+Z werkt).

**Result:** Lokale one-click retouch + improve lighting end-to-end. **AvatarKit:**
`PortraitEnhancer` (Sources/AvatarKit/Imaging/) — `magicRetouch` (volle v1-keten) +
`improveLighting` (tonale subset), beide Core Image, on-device, instant, geen credits. 3 tests
(beide niveaus behouden afmetingen; retouch wijzigt pixels aantoonbaar). **FEAT:** de twee acties
in EditActionsPanel zijn nu lokaal (geen Pro-chip), wired in EditorView via `applyLocalEnhance`
→ `ShellModel.applyEffectResult` (canvas + cutout); niet-destructief (origineel blijft voor
hold-to-compare E06.2) en undo'baar via nieuwe `ImageEnhanceUndo` (recursieve before→after-
registratie op de native UndoManager). Tanden/rimpels/make-up/restore-body blijven generatieve
stubs. Smoke (`--open-panel edit`): Retouch-sectie toont "One click retouch" + "Improve lighting"
als actieve lokale rijen zonder credit-chip, de cloud-edits gedimd-gegated. Beide targets bouwen
groen, alle suites groen.

## 12.2 — Set-brede lighting-normalisatie
- status: backlog
- owner: —
- blockedBy: 12.1, E05.4
- DoD: beide targets bouwen, tests groen

Cross-photo match als set-actie in de sidebar (bekende v1-beperking).

**Result:** _(invullen bij done)_

