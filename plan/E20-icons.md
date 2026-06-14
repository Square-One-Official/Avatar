# E20 — Iconen (Phosphor + DSIcon)

Team: **DS** (AvatarUI). Autonome shift 2026-06-14.

## 20.1 — Phosphor-package + DSIcon-laag
- status: done (DSIcon-laag; Phosphor-backing geparkeerd — zie blocker)
- owner: FEAT (AI-agent, marathon)
- DoD: beide targets bouwen + tests groen

**Plan:** Phosphor-SPM toevoegen aan AvatarUI + een semantische `DSIcon`-laag erover
(betekenis → icoon; grootte/gewicht/kleur uit tokens) zodat de rest van de app op betekenis
tekent en een icoon-wissel centraal is.

**Result:** `DSIcon` toegevoegd (AvatarUI/Components/DSIcon.swift): semantische `Symbol`-enum
(tools: edit/effects/face/clothing/hair/background/images; chrome: share/settings/undo/redo/add/
close; canvas: crop/autoFrame/fixAngle/flip/restoreBody; check/sparkle/colorize/boost), `Weight`
(light/regular/bold), `size`. Kleur via `.foregroundStyle` (template-images), default primary.

**INTERFACE (DSIcon-API):**
```swift
DSIcon(.edit)                          // 20pt, regular, primary
DSIcon(.face, size: 24, weight: .bold)
DSIcon(.share).foregroundStyle(DSColor.Action.primary)
```

**BLOCKER (Phosphor-backing) → wacht-op-Thierry / DECISIONS-PENDING:** de Phosphor-SPM-package
`phosphor-icons/swift` (2.1.0) levert een **asset-catalog**; CLI `swift build`/`swift test`
(zonder `actool`) kan die niet compileren → `type 'Bundle?' has no member 'module'`. De DoD draait
`swift test --package-path AvatarUI` (CLI) → breekt. Daarom backt DSIcon **interim op SF Symbols**,
met de bedoelde Phosphor-naam per case in commentaar. Terug naar Phosphor zodra de build-route is
opgelost (AvatarUI-tests via xcodebuild i.p.v. `swift test`, óf een font-gebaseerde Phosphor-bron).

**Figma-TODO:** Hair-icoon = scissors (Phosphor heeft geen kam); fix-camera-angle = perspective;
restore-body = arrowsOutCardinal — bevestigen tegen definitieve Figma-keuze.

## 20.4 — Phosphor-blocker OPGELOST (split app-target vs AvatarUI)
- status: done (besluit Thierry: SF voor bottom/app-bar, Phosphor voor menu-iconen)

**Result:** De Phosphor-SPM is toegevoegd aan het **Avatar2-app-target** (project.yml), NIET aan
AvatarUI. Het app-target bouwt via xcodebuild (heeft actool → asset-catalog → `Bundle.module` werkt);
`swift test --package-path AvatarUI` ziet Phosphor niet → blijft groen. Volle DoD groen.
**Toegepast:** de canvas-menu-iconen (Frame/Background/Adjust/AI + alle dropdown-rijen) zijn nu
Phosphor (Ph.frameCorners/image/slidersHorizontal/sparkle; cornersOut/crop/perspective/flipHorizontal;
sun/palette/arrowsOut/userRectangle). De bottom-toolbar (Effects/Face/Clothing/Hair) en app-bar
(Share/Settings/Library) blijven **SF Symbols**. Smoke ✓ (Phosphor-iconen in de toolbar).
**Figma-TODO:** exacte Phosphor-iconkeuze per actie bevestigen (Frame=frameCorners, restore-body=
userRectangle, fix-angle=perspective).

## 20.2 / 21.3 — Leading Phosphor-icoon per actie (Edit + Face-paneel)
- status: deels — menu/dropdown-iconen done (20.4). Edit = sliders (geen actie-rijen meer); Face-
  paneel-rijen krijgen iconen in 24.15 (thumbnail-kaarten). De Phosphor-route is nu vrij.
  (oorspronkelijke parkeer-noot:) De visuele
  deliverable is Phosphor; SF-interim zou alleen gokwerk zijn voor teeth/make-up/wrinkles.
  EditorActionList heeft al een leading-icoon-slot (`EditorAction.icon: DSIcon.Symbol`) klaar.
  Edit-paneel is bovendien naar sliders gegaan (E22.3) → leading-iconen gelden nu vooral het
  Face-paneel. Oppakken zodra Phosphor werkt + de Figma-iconkeuze bekend is.

## 20.3 / 21.2-iconen — Tools/app-bar/undo-redo/add naar DSIcon/Phosphor
- status: GEPARKEERD — geblokkeerd op Phosphor. DSIcon-mapping + `EditorTool.dsSymbol` staan klaar;
  de toolbar/app-bar/cluster gebruiken nu SF Symbols die 1-op-1 op de DSIcon-namen mappen, dus de
  swap is één plek (DSIcon-backing) zodra Phosphor bouwt. Toolbar-fit (6 tools) gevalideerd in de
  E22.1-smoke. Edit-icoon = kleur-glyph (paintpalette) gezet in E22.3.
