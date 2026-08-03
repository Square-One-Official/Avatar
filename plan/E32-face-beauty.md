# E32 — Face beauty-acties (Whiten teeth · Apply make-up · Reduce wrinkles)

Team: **FEAT+INFRA+AI**. Gestart 2026-06-22 (klacht Thierry: "geen enkel face effect werkt").

Context: de drie Beauty-acties in het Face-paneel waren sinds E18.2 een *stub* — tik →
`EntitlementModel.allowCloudFeature()` (alleen de contextuele gate), geen echte edit. Voor een
Pro/dev-gebruiker returnde de gate `true` en gebeurde er niets → dode knop. E32 bouwt de
effecten echt, hergebruikt de bestaande `/v1/stylize` instruction-edit-route (zoals hair/clothes).

## 32.0 — Modelonderzoek / face-bakeoff
- status: ready (handmatig, owner AI + Thierry)
- DoD: `plan/e32-face-bakeoff.md` met aanbeveling-per-effect-tabel (identiteit + "change nothing
  else" + kwaliteit/kosten), analoog aan `plan/e09-1-bakeoff.md`.

**Plan:** armen `nano-banana` (baseline/E09.1-winnaar), `gpt-image-1.5`, `seedream`
(`bytedance/seedream-4`), optioneel `flux-2-pro`. Cases `edit-teeth`, `edit-makeup` (NIEUW),
`edit-wrinkles` op de 5 EdgeBench-portretten (p4 = zichtbare tanden). Driver = dev-only
`model_override` op een Vercel-preview-deploy, contactsheets in `~/Documents/Claude/Projects/Aaavatar/`.
Let op Replicate-saldo (<$5 = 6/min throttle, $0 = 402). Infra staat klaar: `seedream` in
`MODEL_REGISTRY.stylize` + adapter in `stylizeInputFor` (Seedream-schema verifiëren vóór de eerste
call — `image_input`/`size`/`aspect_ratio`); `face_preset` callable op `/v1/stylize`.

**Uitkomst → 32.1:** bevestigt nano per effect → niets te wijzigen; anders het default-model per
`face_preset` aanpassen (per-preset-mapping in `stylize.ts` of de feature-default).

## 32.1 — Face-intent end-to-end (backend + client + UI)
- status: in_progress
- owner: FEAT+INFRA (AI-agent)
- DoD: beide targets bouwen + tests groen + Result-regel

**Plan:** face-intent op `/v1/stylize` (server-gemapte prompts, harde "change nothing else"-clausule);
`editFace()` in BackendClient; `FaceEffectsModel` dat de drie Beauty-kaarten echt aanstuurt.

**Result:** Backend: `FACE_CLAUSE` + `FACE_PRESETS`
(`whiten-teeth`/`apply-makeup`/`reduce-wrinkles`, incl. de E09.1 "houd de mond dicht"-fix) +
`face_preset`-tak in de intent-ladder van [stylize.ts](../backend/api/v1/stylize.ts)
(`unknown_face_preset` → 400). Tarief = generativeStandard (4 cr). Smoke
([models-smoke.ts](../backend/scripts/models-smoke.ts)) uitgebreid met de Seedream-arm-assert ✓,
`tsc --noEmit` ✓. Client: nieuw `FaceEdit`-enum + `BackendClient.editFace(imagePNG:preset:)`
(spiegelt `editHair`/`editClothes`, body `face_preset` + generation_model + model_override). UI:
`FaceEffectsModel` (gate → working-toast → `editFace` → onApply → saldo-refresh; 402 →
`handleOutOfCredits`) drijft de Beauty-kaarten in [FaceActionsPanel.swift](../Avatar2/Features/Editor/FaceActionsPanel.swift);
`onProFeature`-stub vervangen door echte per-kaart-handlers. Gewired in EditorView (`.face`, let
entitlement; `onApply: undoableApply("Face edit")`) én BoardView single-edit
(`undoableApplyToNode`). Beide targets bouwen ✓; Avatar2Tests 19/19 groen ✓.

**Nog te doen vóór live:** (1) backend deployen naar productie (api.aaavatar.nl) — de app draait
lokaal tegen productie, dus zonder deploy blijft `face_preset` een 400; (2) 32.0-bakeoff draaien
en het default-model/prompts bevestigen vóór de productie-deploy.

**Aandachtspunten:** geen result-cache (anders dan Effects) — een face-edit is een eenmalige,
undo'bare bewerking op het huidige beeld. Default-model volgt 32.0; nu nano-banana als baseline.

## 32.2 — TeethWhitener: on-device tandenbleek-engine
- status: done
- owner: AI (Claude, 2026-08-03)
- DoD: beide targets bouwen + tests groen + Result-regel

Aanleiding (klacht Thierry 2026-08-03): de cloud-arm van Whiten teeth maakte het hele beeld
lichter, veranderde het formaat en bleekte nauwelijks. Oorzaken: (1) volledige her-render zonder
mask — de prompt zei bovendien letterlijk "brighten"; (2) nano levert ~1 MP terug en face was de
enige edit-intent zónder `preserve_framing` → ratio-drift ≥2% reset de transform; (3) de
voorzichtige prompt bleekte te weinig. Besluit Thierry: twee armen — On device (gratis) + Cloud
(Pro, 4 cr) via een dropdown op de kaart (→ 32.3); cloud-fixes in 32.4.

**Result:** [TeethWhitener.swift](../AvatarKit/Sources/AvatarKit/Engines/TeethWhitener.swift)
(ClothesMaskGenerator-patroon): Vision-landmarks (rev3 gepind) → innerLips-polygon →
aperture-check (mond dicht = `.mouthNotVisible`, bewuste no-op) → polygon-masker + feather →
emaille-kleurpoort (CIColorCubeWithColorSpace, sRGB-getuned: luminantievloer adaptief op het
mondgemiddelde, sat ≤ 0.42, niet rood/blauw-dominant) → adaptieve sterkte uit de gemeten
tandkleur (desaturatie geklemd 0.20–0.65, gamma-lift richting luma 0.82, macht ≥ 0.75) →
`CIBlendWithMask`-composiet. Afmetingen + alpha per constructie identiek; alleen mond-RGB
verandert. Pure seams getest in
[TeethWhitenerTests.swift](../AvatarKit/Tests/AvatarKitTests/TeethWhitenerTests.swift) (9 tests);
`swift test` AvatarKit 133/133 groen ✓. Follow-up (backlog): face-parsing-CoreML-model voor echte
tandsegmentatie via het OrmbgModelStore-downloadpatroon.

## 32.3 — Whiten teeth-dropdown (On device / Cloud) + stale-base-fix
- status: done
- owner: FEAT (Claude, 2026-08-03)
- DoD: beide targets bouwen + tests groen + Result-regel

**Result:** [FaceActionsPanel.swift](../Avatar2/Features/Editor/FaceActionsPanel.swift): de
Whiten-kaart opent een DSContextMenuPanel-dropdown (EditColorPanel-overlaypatroon, zweeft óver de
kaart — onder/boven zou door DSEditPanels ScrollView geclipt worden): "On device · Free" →
`applyLocalTeethWhiten` (TeethWhitener, geen gate/credits; `.noFaceFound` → toast die naar Cloud
verwijst, `.mouthNotVisible` → vriendelijke no-op-toast) en "Cloud · Best · 4 credits (Pro)" → het
bestaande `editFace`-pad. Whiten-kaart zonder blanket Pro-badge (heeft een gratis arm) + chevron.
Stale-base-defect gefixt voor álle drie presets: `FaceEffectsModel` bevroor base/portrait bij
init; nu per tik van de view (ClothesModel-patroon) — een tweede edit bouwt op de eerste.
Apply-invariant gepind in ShellModelTests
(`testApplyEffectResultIdentiekeAfmetingenLaatTransformEnFormaatStaan`): identieke afmetingen +
bron-alpha → geen resize/transform-reset. Board-callsite ongewijzigd (optionele params).

## 32.4 — Cloud-arm-fixes: promptherschrijving + preserve_framing
- status: done (deploy naar prod blijft gated op Thierry, zie 32.1 "Nog te doen vóór live")
- owner: INFRA (Claude, 2026-08-03)
- DoD: beide targets bouwen + tests groen + Result-regel

**Result:** [stylize.ts](../backend/api/v1/stylize.ts): whiten-teeth-prompt herschreven op basis
van de E09.1-winnaar — "brighten" (globale attractor zonder mask) eruit, expliciet verbod op
skin/lips/lighting/background-wijzigingen + gesloten-mond-no-op; CMS-override-risico
gedocumenteerd bij `FACE_PRESETS` (geen `face-presets`-collectie in admin — hardcoded is wat
draait). [BackendClient.swift](../AvatarKit/Sources/AvatarKit/Backend/BackendClient.swift):
`editFace` stuurt nu `preserveFraming: true` (spiegel van hair/clothes) → server hangt de
FRAMING_CLAUSE aan; met ratio binnen 2% resize't de client terug naar de cutout-maat i.p.v. de
transform te resetten. Request-body gepind in BackendClientDecodeTests
(`testEditFaceSendsPreserveFramingAndPreset`). `tsc --noEmit` ✓.

## 32.5 — Mond-composiet van het cloud-resultaat (stretch)
- status: backlog
- Alleen oppakken als de toondrift na 32.4 in de praktijk blijft: hergebruik het
  TeethWhitener-masker om alléén de mondregio van het cloud-resultaat in het origineel te
  composieten (alignment-gate + full-frame-fallback; naadrisico eerlijk beoordelen).
