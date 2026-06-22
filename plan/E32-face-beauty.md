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
