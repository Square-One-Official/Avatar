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
- status: done
- owner: AI
- blockedBy: E01.8
- DoD: beide targets bouwen, tests groen

Notitie (AI, claim): opgepakt naast E09.1 op instructie Thierry — E09.1 is extern
geblokkeerd (Replicate-saldo op, wacht op top-up); fixtures staan inmiddels in
Avatar/Debug/Fixtures (hoofd-checkout), harness-uitbreidingen op bench/2.0-bakeoff-arms.

Nieuwe engine als arm 'v2.0-minimal' aan EdgeBenchmark; run op fixtures incl. moeilijke gevallen;
vastleggen welke oude stages (5–11) terugplaatsing verdienen. Alleen met bewijs.

**Result:** 5e arm 'v2.0-minimal' (VisionCutoutEngine via sync-bridge) in EdgeBenchmark + CSV-kolommen/strips; 5-arms-beslisrun op 7 fixtures gedraaid — v2min ⌀104 ms, visueel gelijkwaardig aan V1/V2 op álle fixtures (backlit blond: schoner dan V1, geen gloed-halo), stages 5–11 definitief weg zonder terugplaatsing, ORMBG rechtvaardigt ModelManager/download-infra niet (zie besluit-blok); beide targets bouwen, tests groen.

Notities (AI, bij oplevering 2.1):
- Blocker 2.1 is done; nieuwe blocker E01.8 (Avatar-target moet AvatarKit linken om de engine
  als arm aan te kunnen roepen — project.yml is INFRA-grens).
- De 4-arms-harness uit pipeline-audit-2.0.md (raw/ORMBG-armen + `subjectLiftRaw`) bestaat
  alleen als **niet-gecommitte wijzigingen** in de hoofd-checkout op de v1-branch
  (`fix/newsletter-cohorts-revoke-public`): EdgeBenchmark.swift +40, ImageProcessor.swift +30.
  Bij deze story porten/committen, anders benchmark je tegen de 2-arms-versie.
- De beslisrun vereist privé fixture-foto's (Avatar/Debug/Fixtures is leeg in git én op deze
  machine) — run + beoordeling samen met Thierry inplannen.
- INFRA, bij oplevering E01.8: blocker opgeheven — Avatar én Avatar-MAS linken AvatarKit op
  v2-main (stond er al sinds E01.5; builds geverifieerd).

**Besluit-blok (beslisrun 2026-06-12, 7 fixtures incl. krullenbos, backlit blond, afro,
hoed, zonnebril; output `EdgeBench/edge-bench-2026-06-12T17-02-59Z`):**

| Stage (5–11) | Besluit | Bewijs |
|---|---|---|
| 5 strict matte | **definitief weg** | v2min (guided+clamp alleen) toont op geen van de 7 strips muddy randen of halo's t.o.v. V1/V2 |
| 6 hair zone | **definitief weg** | geen enkel geval waar v2min haar verliest dat V1 behoudt; hoed- en zijprofiel-fixtures juist schoner zonder geometrie-aannames |
| 7 colour-attenuation | **definitief weg** | inter-krul-detail (Hershair, afro) is in v2min gelijkwaardig aan V1/V2 op alle drie backdrops |
| 8 gamma-lift | **definitief weg** | wisp-behoud backlit blond: v2min = V2; geen perceptueel verlies |
| 9 edge band | **definitief weg** | bestaansreden (scopen van 6–8) vervalt |
| 10+11 decontaminatie/blur-fusion | **definitief weg** | het omgekeerde bewijs: V1 toont op backlit blond een warme gloed-halo rond de krullen die v2min níét heeft — de #1-halo-bron uit de audit reproduceert op de fixtures, het probleem dat hij moet oplossen (bg-bleed) niet. Zonnebril-fringe op donker zit in álle armen gelijk (bronfoto-randlicht), geen 5–11-verdienste |

Geen terugplaatsing — geen van de stages 5–11 verslaat v2min ergens op de strips ("alleen
met bewijs" → er is geen bewijs). Snelheid: v1 ⌀333 ms · v2 ⌀141 ms · **v2.0-minimal ⌀104 ms**
· raw ⌀37 ms · ORMBG ⌀170 ms (+5,7 s eerste load).

**ORMBG/ModelManager-oordeel:** ORMBG voegt op deze fixtures geen kwaliteit toe boven de
gratis Vision-route (verliest juist backlit-slierten t.o.v. v2min) en kost download-infra +
eerste-load. Aanbeveling: **geen ModelManager/download-infra porten naar 2.0**; OrmbgEngine
(E02.3) blijft beschikbaar als opt-in, maar de High-fidelity-edges-downloadkaart (E15.2)
heroverwegen — alleen terugbrengen met bewijs op failure-cases die Vision aantoonbaar mist.
raw als ondergrens is verrassend sterk maar verliest strand-zachtheid; stages 1–4+12–13
verdienen hun plek (klein, zichtbaar effect).

> Herziening Thierry 2026-06-12: de optionele model-download **blijft** — op drie plekken
> (onboarding-stap E04.6, Settings-kaart E15.2, nudge E05.6), allemaal op dezelfde
> OrmbgModelStore. Het infra-deel van bovenstaand oordeel is daarmee overruled; het
> kwaliteitsbewijs (geen meerwaarde op deze 7 fixtures) blijft staan als context voor de
> copy-claims en de E05.6-detectie.

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
- status: done
- owner: AI
- blockedBy: E01.5
- DoD: beide targets bouwen, tests groen

Op bestaande /v1/cutout via AvatarKit BackendClient.

**Result:** `CloudCutoutEngine` (struct, `CutoutEngine`-conform, kind `.replicate`) in `AvatarKit/Engines/` — dunne adapter rond `BackendClient.cutout` (bestaande /v1/cutout incl. Storage-upload-flow en creditaftrek; BackendError's propageren ongewijzigd), PNG↔CGImage via ImageIO, `isAvailable` = sessie-aanwezig via nieuwe één-regel `BackendClient.hasSession` (buiten Engines/ — **INFRA-review gevraagd**); 5 tests zonder netwerk (URLProtocol-stub voor het volledige wire-pad, notSignedIn vóór I/O, alpha-roundtrip), totaal 25 packagetests groen; beide targets bouwen Debug groen via build-v2.sh.

## 2.5 — Kleurruimte-normalisatie bij import (grayscale/CMYK-fix)
- status: done
- team: AI
- blockedBy: —

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevinding B1).
**Wat:** `VisionCutoutEngine.swift:107-112` en `OrmbgEngine.swift:83-88` renderen naar
`.RGBA8` met de **bron**-kleurruimte (`image.colorSpace ?? sRGB`). Voor een
grayscale-PNG (DeviceGray, samplesPerPixel 2) of een CMYK-JPEG is dat incompatibel
met `.RGBA8` → `createCGImage` geeft `nil` → `Failure.renderFailed`. Beide engines
bevatten dezelfde regel, dus de `PipelineRouter`-cascade redt niets. Empirisch
gereproduceerd: DeviceGray-CGImage door `EngineRendering.linearContext` →
`createCGImage(RGBA8, grayCS)` = nil; met sRGB = ok. `visionInput`
(regel 149-153) faalt om dezelfde reden en valt stil terug op de originele
resolutie (adaptieve upscale al kapot vóór de eindrender).
**Voorstel:** normaliseer élke import naar sRGB-RGBA op één plek —
`ShellModel.importImage`, vóór de engines worden aangeroepen (dekt ook toekomstige
consumers zoals AutoFramer/ClothesMaskGenerator) — of minimaal in beide engines:
`let outputColorSpace = (image.colorSpace?.model == .rgb ? image.colorSpace : nil)
?? CGColorSpace(name: .sRGB)!`.
**DoD:** beide targets bouwen; nieuwe grayscale/CMYK-fixture-tests in
`VisionCutoutEngineTests` én `OrmbgEngineTests` slagen; tests groen; Result-regel.

**Result:** twee niveaus zoals voorgesteld — (1) `SRGBNormalizer` (public, in
`AvatarKit/Engines/`): élke import naar sRGB-RGBA8 op het éne choke-point
`ShellModel.runCutout` (beide importImage-overloads); pass-through als al
genormaliseerd, wide-gamut (P3) gaat bewust mee naar sRGB; (2) engine-guard
`EngineRendering.outputColorSpace(for:)` (niet-RGB-bron → sRGB, RGB incl. P3
blijft) op alle drie de `.RGBA8`-rendersites: VisionCutoutEngine eindrender +
`visionInput`, OrmbgEngine eindrender. Tests: DeviceGray/DeviceCMYK
hoofd+schouders-fixtures (gedeeld, `ColorSpaceFixtures`) door béide engines —
de ORMBG-varianten draaien tegen het lokaal geïnstalleerde model
(app-container-fallback; XCTSkip zonder installatie, guard dan nog gedekt via
SRGBNormalizerTests) — plus 7 helper-tests (normalisatie/pass-through/alpha/
P3/guard). AvatarKit 70 tests groen, AvatarUI 37 groen; Avatar én Avatar2
bouwen Debug groen. — Cutout-randkwaliteit op lage resolutie
- status: backlog
- team: AI
- blockedBy: —

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevinding B7). Dit is
de E02.2-bakeoff die de header van dit epic al aankondigde.
**Wat:** `VisionCutoutEngine.swift:85-89` bevat bewust geen kleur-decontaminatie —
de composite is origineel × zachte alpha, dus in de soft band blijft een
haar/achtergrond-kleurmengsel zichtbaar (magenta/roze fringe op de
183px-lastige-haar-testfoto). De guided-filter-radius is bovendien vast r=8 in
**bronpixels** — op een 183px-foto is dat ~4,4% van de beeldbreedte, op een
4000px-foto 0,2%: een véél bredere fringe-band juist op lage resolutie, waar het
masker toch al zwak is.
**Voorstel:** (a) radius schalen met resolutie, bv. `max(2, longEdge/256)`; (b) een
lichte decontaminatie-stap voor de soft band — `DominantColor.edge` is al
beschikbaar in dezelfde module; (c) overweeg een import-waarschuwing onder ~400px.
**DoD:** beide targets bouwen; visuele vergelijking vóór/na op de bestaande
lastige-haar-fixtures in de Result-regel; tests groen.

