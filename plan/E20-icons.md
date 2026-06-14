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

## 20.2 / 21.3 — Leading Phosphor-icoon per actie (Edit + Face-paneel)
- status: todo (na 21.1/21.2)

## 20.3 — Overige knoppen naar Phosphor/DSIcon (app-bar, undo/redo, add)
- status: todo (na E22)
