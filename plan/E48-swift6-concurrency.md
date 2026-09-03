# E48 — Swift 6-concurrency-pad

Team: **INFRA**

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevinding D3).
Backlog-epic, geen haast: eerst de packages op gelijke voet met de app-target
brengen, dan pas per module optrekken naar `complete`/Swift 6. SwiftData
`@Transient`-caches (`Portrait2`, `BannerDoc`) worden vermoedelijk het meeste werk.

---

## 48.1 — Strict concurrency ook op de SPM-packages
- status: backlog
- team: INFRA
- blockedBy: —

**Wat:** `SWIFT_STRICT_CONCURRENCY: targeted` staat alleen in `project.yml` (geldt
dus voor `Avatar2`/`Avatar`), niet in `AvatarKit/Package.swift` of
`AvatarUI/Package.swift`. Juist AvatarKit (actors, engines, Sendable-oppervlak)
compileert zonder deze checks.
**Voorstel:** `swiftSettings: [.enableExperimentalFeature/.unsafeFlags(["-strict-
concurrency=targeted"])]` toevoegen per package-target.
**DoD:** beide packages bouwen met `targeted` aan, eventuele nieuwe warnings
opgelost of expliciet onderdrukt met motivatie; Result-regel.

## 48.2 — Per module naar "complete" (AvatarUI → AvatarKit → Avatar2)
- status: backlog
- team: INFRA
- blockedBy: 48.1

**Wat:** volgende stap richting Swift 6: `targeted` → `complete` per module, in
volgorde van kleinste blast radius naar grootste.
**Voorstel:** AvatarUI eerst (kleinste, minste state), dan AvatarKit (actors +
SwiftData-aanraking), dan Avatar2 (grootste, UI-zwaar). Elke stap een aparte story/
commit zodat regressies isoleerbaar zijn.
**DoD:** per module: bouwt onder `complete`, tests groen, Result-regel met de
concrete `Sendable`/isolatie-fixes die nodig waren.

## 48.3 — SWIFT_VERSION 6.0
- status: backlog
- team: INFRA
- blockedBy: 48.2

**Wat:** `project.yml:31` staat op Swift 5.10.
**Voorstel:** pas omzetten zodra alle drie modules onder `complete` bouwen (48.2
klaar). v1 (`Avatar/`) hoeft niet mee — die is bevroren en mag op 5.10 blijven staan
als dat de eenvoudigste weg is.
**DoD:** `xcodebuild` voor Avatar2 + de packages bouwt onder Swift 6; alle
testsuites groen; Result-regel.
