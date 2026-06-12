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
- status: ready
- owner: —
- blockedBy: E01.8
- DoD: beide targets bouwen, tests groen

Nieuwe engine als arm 'v2.0-minimal' aan EdgeBenchmark; run op fixtures incl. moeilijke gevallen;
vastleggen welke oude stages (5–11) terugplaatsing verdienen. Alleen met bewijs.

Notities (AI, bij oplevering 2.1):
- Blocker 2.1 is done; nieuwe blocker E01.8 (Avatar-target moet AvatarKit linken om de engine
  als arm aan te kunnen roepen — project.yml is INFRA-grens).
- De 4-arms-harness uit pipeline-audit-2.0.md (raw/ORMBG-armen + `subjectLiftRaw`) bestaat
  alleen als **niet-gecommitte wijzigingen** in de hoofd-checkout op de v1-branch
  (`fix/newsletter-cohorts-revoke-public`): EdgeBenchmark.swift +40, ImageProcessor.swift +30.
  Bij deze story porten/committen, anders benchmark je tegen de 2-arms-versie.
- De beslisrun vereist privé fixture-foto's (Avatar/Debug/Fixtures is leeg in git én op deze
  machine) — run + beoordeling samen met Thierry inplannen.

**Result:** _(invullen bij done)_

## 2.3 — OrmbgEngine
- status: done
- owner: AI
- blockedBy: 2.1
- DoD: beide targets bouwen, tests groen

Bestaand 3-staps ORMBG-pad overnemen achter CutoutEngine-protocol; downloadlogica versimpeld uit
ModelManager.

**Plan:**
1. `OrmbgEngine` (struct, `CutoutEngine`-conform) + `OrmbgModelStore` (actor) in `AvatarKit/Sources/AvatarKit/Engines/`. Het 3-staps inferentiepad 1-op-1 uit `subjectLiftDownloaded`: 1024² input (×/255 zit in het model) → matte → guided filter (r=2, ε=0.01) → composite, linear-sRGB; bewust géén V2-refinement erop (gedocumenteerd schadelijk: halo's).
2. Downloadlogica versimpeld: zelfde manifest (GitHub release-zip, SHA-256-gate), maar versie in de installatiemap-naam (`ormbg/v1/`) i.p.v. sidecar-bestand, en een enkele async `download()` i.p.v. de Observation-state-machine — UI-state is een zorg van de 2.0-settings-story, niet van de engine.
3. Gedeelde linear-sRGB CIContext naar `EngineRendering.swift` (intern, Engines/); VisionCutoutEngine gebruikt hem ook.
4. ZIPFoundation als AvatarKit-dependency (zelfde versie als project.yml, 0.9.20) voor de zip-extractie — genoteerd voor INFRA-review.
5. Tests zonder model/netwerk: matte-extractie uit synthetische MLMultiArray (float32 + float16-decode), isAvailable=false zonder installatie, SHA-256-helper op tempbestand; build via scripts/build-v2.sh.

**Result:** `OrmbgEngine` + `OrmbgModelStore` (actor: installedModelURL/download/removeInstalled/model-cache, SHA-256-gate, versie-in-mapnaam onder Application Support/AvatarKit/Models/ormbg/) in `AvatarKit/Engines/`; 3-staps pad 1-op-1 uit `subjectLiftDownloaded` (1024² → matte → guided r=2 ε=0.01 → composite, linear-sRGB); gedeelde contexten naar `EngineRendering.swift` (VisionCutoutEngine gerefactord); ZIPFoundation 0.9.20 als AvatarKit-dependency (INFRA-review gevraagd); 8 nieuwe tests, totaal 18 groen; beide targets bouwen Debug groen via build-v2.sh.

## 2.4 — CloudCutoutEngine
- status: backlog
- owner: —
- blockedBy: E01.5
- DoD: beide targets bouwen, tests groen

Op bestaande /v1/cutout via AvatarKit BackendClient.

**Result:** _(invullen bij done)_

