# E49 — Opruimronde 2026-07

Team: **FEAT + AI + DS**

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevindingen D4-D7).
Spiegelt het patroon van `plan/AUDIT-2026-06-23-cleanup.md`: kleine, laag-risico
opruim-items per team, gebundeld zodat ze in één keer opgepakt kunnen worden zonder
een aparte story per regel te hoeven claimen.

---

## 49.1 — Dode code opruimen [FEAT]
- status: ready
- team: FEAT
- blockedBy: —

**Wat (alle geverifieerd nul-call-sites, tenzij anders vermeld):**
- `Avatar2/Features/Shell/PortraitHeader.swift` — vervangen door CanvasFrameChip +
  RenameSheet, alleen nog in comments genoemd.
- `EditorTool.dsSymbol` — de E20.1/21.2-omschakeling naar DSIcon is nooit afgemaakt.
- `EditorTool.pendingStory` + bijbehorende stub-copy — toont eindgebruikers
  story-nummers ("tools land here (E09.2)") in de entitlement==nil-fallback; de
  stories zijn allang done.
- `EditorView`'s onbereikbare `canvasPanel(.background)`-tak — `.background` zit niet
  in `toolbarItems`; Background opent via de `CanvasActionToolbar`-dropdown.
- Stale comment `EditorView.swift:641-642` (verwijst naar verborgen ⌘=-knoppen die
  niet meer bestaan).
- `Folder2.order` / `Folder2.colorHex` — nergens gerenderd/gesorteerd op; alleen
  `SmokeSeed` schrijft `colorHex`.
- `ImagePlaygroundEntryButton` — 0 call sites buiten de eigen file.
- `OnboardingModel.finishSignedIn()` — 0 call sites (zie ook E04.8, die lost het
  gebruik ván op; deze story ruimt 'm op als hij na E04.8 alsnog overbodig blijkt).
- `ThumbnailStore.invalidate()` — gedocumenteerde no-op.
**Voorstel:** verwijderen resp. corrigeren per punt.
**DoD:** beide targets bouwen, tests groen, Result-regel met de lijst afgevinkt.

## 49.2 — Kleine UX-consistentie [FEAT]
- status: ready
- team: FEAT
- blockedBy: —

**Wat:**
- `ExportSheet.swift:182,193` — export-/share-bestandsnaam hardcoded
  "Aaavatar-portrait.png" i.p.v. `portrait.name`.
- `PortraitSetActions.swift:82-100` — bulk-export op de main thread
  (`makePNGAsync` bestaat al, wordt niet gebruikt) + stille naamcollisies
  (overschrijft zonder melding) — dedupliceer bestandsnamen (`-2`, `-3`).
- Privacy-policy-URL inconsistent: `SettingsAboutPage.swift:88` linkt `/privacy`,
  `OnboardingEmailView.swift:88`/`PaywallSheet.swift:314` linken `/privacy-policy` —
  één op één constante trekken.
- ⌘U (Upload portrait) is view-scoped aan de Home-knop
  (`HomeView.swift:347`) — registreer als app-brede `CommandGroup` (File-menu) naast
  het bestaande `CanvasZoomCommands`-patroon; Home-knop mag het ⌘U-badge houden.
- `GenerateBackgroundSwatch.openSheet` mist een `return` in de `.onDevice`-tak
  (`GenerateBackgroundSheet.swift:618-633`) → elevation-modal én sheet tegelijk;
  `ManageBackgroundsSheet.openGenerate` doet het wél goed — zelfde gedrag toepassen.
- Onboarding-fouten (`auth.lastError`) renderen in dezelfde subtiele stijl als een
  succesbevestiging (`OnboardingOTPView.swift:36-44`, `OnboardingEmailView.swift:40-44`)
  — naar `DSColor.Signal.error` + `DSValidationState.error`, in lijn met SignInSheet.
**DoD:** beide targets bouwen, tests groen, Result-regel per punt.

## 49.3 — Perf-restjes [AI]
- status: ready
- team: AI
- blockedBy: —

**Wat:**
- `OrmbgModelStore.swift:164-186` — downloadprogress itereert per byte over ~45MB
  (`for try await byte in bytes`); naar `download(from:)` + delegate/KVO-progress of
  chunked `AsyncBytes`-reads.
- `ShellModel.swift:570` (`applyAlphaMask`) — ad-hoc verse `CIContext` per aanroep op
  het face-edit-hot-path, terwijl engines al gedeelde contexts gebruiken
  (`EngineRendering`); hergebruik een gedeelde context.
- Undo-history onbegrensd: `levelsOfUndo` wordt nergens gezet op de window-
  `UndoManager`, terwijl `CutoutDataUndo` volledige PNG-`Data` in de closures houdt —
  zet een redelijke cap (bv. 20).
- `Portrait2.effectCache` is een base64-JSON-`Data`-blob (+33% opslag, hele blob
  herschreven per nieuwe entry) — overweeg losse `externalStorage`-velden per entry
  via een kind-entiteit, of minimaal binaire plist i.p.v. JSON.
**DoD:** beide targets bouwen, tests groen, Result-regel per punt.

## 49.4 — Phosphor vs. SF Symbols-besluit afronden [DS]
- status: in_progress
- owner: DS (2026-07-12)
- team: DS
- blockedBy: —

**Wat:** `plan/DECISIONS-PENDING.md` heeft een open item sinds 2026-06-14:
PhosphorSwift's asset-catalog breekt `swift test --package-path AvatarUI` (geen
`actool` in de CLI-toolchain). Interim: `DSIcon` draait op SF Symbols met de
bedoelde Phosphor-naam in commentaar. Vandaag blijkt PhosphorSwift wél gelinkt aan
het Avatar2-target, maar in exact 2 files gebruikt
(`CanvasActionToolbar.swift:29`, `FaceActionsPanel.swift:15`) — twee icoonsystemen
door elkaar.
**Voorstel:** kies één van de drie opties uit DECISIONS-PENDING.md (AvatarUI-tests via
xcodebuild i.p.v. `swift test`; font-gebaseerde Phosphor-bron; Phosphor-SVG's als
eigen resources zonder asset-catalog) en voer 'm door, of besluit bewust bij
SF Symbols te blijven en verwijder de PhosphorSwift-dependency + de 2 losse
call-sites.
**DoD:** `swift test --package-path AvatarUI` blijft groen; DECISIONS-PENDING.md
bijgewerkt naar "Beslist"; Result-regel.
