# E02 — Vision-engine minimaal

Team: **AI**

De 2.0-cutout van ~200 regels (zie pipeline-audit-2.0.md).

## 2.1 — VisionCutoutEngine
- status: done
- owner: AI
- blockedBy: E01.2
- DoD: beide targets bouwen, tests groen

Adaptieve input → fg-mask + gated person-seg-union → guided filter → clamp → composite, linear-sRGB.
Unit-test op fixtures.

**Plan:**
1. `VisionCutoutEngine` (struct) in `AvatarKit/Sources/AvatarKit/Engines/` achter het bestaande `CutoutEngine`-protocol, met eigen linear-sRGB CIContext (RGBAh-werkruimte, sRGB-out) — zelfde kleurdiscipline als v1-stage 12.
2. Pipeline = exact de keep-list uit pipeline-audit-2.0.md: adaptieve Vision-input (1500–4096 long edge) → gepinde revisions, fg-mask + 16-bit person-seg → gated union (dilate-gate r=8) → CIGuidedFilter (r=8, ε=1e-4) → CIColorClamp → CIMaskToAlpha + CIBlendWithMask. Stages 5–11 komen er niet in; geen face-detectie (de hair zone bestaat niet meer).
3. Fixture-foto's zitten bewust niet in git; unit-tests draaien op synthetische fixtures (hoofd+schouders-silhouet — Vision-detectie hiervan vooraf geverifieerd) + no-subject-pad op vlak beeld; dimensie/alpha/rand-asserties.
4. `AvatarKitTests`-testtarget toegevoegd aan Package.swift omdat de DoD tests eist; E01.4 (INFRA) kan hierop voortbouwen voor het buildscript.
5. Beide targets bouwen (xcodegen + xcodebuild), tests groen, merge naar v2-main.

**Result:** `VisionCutoutEngine` (struct, `CutoutEngine`-conform) in `AvatarKit/Sources/AvatarKit/Engines/VisionCutoutEngine.swift` — adaptieve input (1500–4096) → gepinde fg-mask + 16-bit person-seg gated union (r=8) → CIGuidedFilter (r=8, ε=1e-4) → clamp → MaskToAlpha/BlendWithMask, linear-sRGB/RGBAh, ~180 regels, geen stages 5–11; fouten via `VisionCutoutEngine.Failure` (.noSubjectFound/.renderFailed); `AvatarKitTests`-testtarget toegevoegd (5 tests op synthetische fixtures, groen); Avatar + Avatar2 bouwen Debug groen.

## 2.2 — EdgeBenchmark 5e arm + beslisrun
- status: backlog
- owner: —
- blockedBy: 2.1
- DoD: beide targets bouwen, tests groen

Nieuwe engine als arm 'v2.0-minimal' aan EdgeBenchmark; run op fixtures incl. moeilijke gevallen;
vastleggen welke oude stages (5–11) terugplaatsing verdienen. Alleen met bewijs.

**Result:** _(invullen bij done)_

## 2.3 — OrmbgEngine
- status: backlog
- owner: —
- blockedBy: 2.1
- DoD: beide targets bouwen, tests groen

Bestaand 3-staps ORMBG-pad overnemen achter CutoutEngine-protocol; downloadlogica versimpeld uit
ModelManager.

**Result:** _(invullen bij done)_

## 2.4 — CloudCutoutEngine
- status: ready
- owner: —
- blockedBy: E01.5
- DoD: beide targets bouwen, tests groen

Op bestaande /v1/cutout via AvatarKit BackendClient.

**Result:** _(invullen bij done)_

