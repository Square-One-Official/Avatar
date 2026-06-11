# E02 — Vision-engine minimaal

Team: **AI**

De 2.0-cutout van ~200 regels (zie pipeline-audit-2.0.md).

## 2.1 — VisionCutoutEngine
- status: ready
- owner: —
- blockedBy: E01.2
- DoD: beide targets bouwen, tests groen

Adaptieve input → fg-mask + gated person-seg-union → guided filter → clamp → composite, linear-sRGB.
Unit-test op fixtures.

**Result:** _(invullen bij done)_

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
- status: backlog
- owner: —
- blockedBy: E01.5
- DoD: beide targets bouwen, tests groen

Op bestaande /v1/cutout via AvatarKit BackendClient.

**Result:** _(invullen bij done)_

