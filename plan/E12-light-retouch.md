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
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: 12.1 (done), E05.4 (done)
- DoD: beide targets bouwen, tests groen

Cross-photo match als set-actie in de sidebar (bekende v1-beperking).

**Plan:**
1. AvatarKit `SetLightingNormalizer` (Imaging/): `referenceStats(of:)` (grijs-geflattende
   gemiddelde kleur, alpha-stabiel) + `match(_:to:)` (per-kanaal gain via CIColorMatrix, geklemd
   0.6–1.6, alpha behouden). Lokaal, geen credits.
2. FEAT: "Match lighting"-set-actie in de sidebar (zelfde patroon als "Align set", zichtbaar bij
   ≥2 portretten), referentie = geselecteerd portret; één set-brede undo-groep via nieuwe
   `CutoutDataUndo`.
3. v1 had geen echte cross-photo-match (alleen een fill-body-flavor-string) → dit is nieuw, met
   de bekende beperking: globale gemiddelde-match, geen lokale relighting.

**Result:** Set-brede lichtnormalisatie als sidebar-actie. **AvatarKit:** `SetLightingNormalizer`
(Sources/AvatarKit/Imaging/) — `referenceStats` (gemiddelde kleur op een grijs-geflattende kopie,
zodat transparante randen het gemiddelde niet vertekenen) + `match` (per-kanaal gain via
CIColorMatrix, geklemd 0.6–1.6, alpha behouden), lokaal/geen credits. 2 tests (donker→referentie
schuift omhoog zonder voorbij te schieten; afmetingen behouden). **FEAT:** "Match lighting"-knop
in SidebarView (DSNeutralButton + sun.max, naast "Align set", alléén bij ≥2 portretten); trekt
alle portretten naar het geselecteerde (of meest recente) portret als referentie in één
undo-groep via nieuwe `CutoutDataUndo` (recursieve before→after-registratie). Referentie zelf
blijft ongemoeid (gain ≈ 1 → geen wijziging → geen undo-stap). **Bekende beperking** (gedocumenteerd
in de code): globale gemiddelde-kleur-match, geen lokale relighting/contrast — sterk afwijkende
opnames trekken niet perfect gelijk (v1 had dit überhaupt niet). Smoke (`--seed-set`): de knop
verschijnt onder "Align set" in de set-sidebar. Beide targets bouwen groen, alle suites groen.

