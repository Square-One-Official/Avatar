# E55 — Effects 2.0 (kwaliteit, plaatsing, CMS-stijlen, instant thumbnails)

Team: **INFRA** (lead) + **FEAT** + **DS** + **AI**

Aanleiding (Thierry, 2026-08-02): vijf zorgen over Effects — (1) stijlkwaliteit
("recreëer het portret écht in de beloofde stijl"; zijn ChatGPT-workflow met
referentiebeelden werkt aantoonbaar goed), (2) plaatsing van een verplaatst/
geschaald portret moet stabiel blijven na een effect, (3) de "Create"-kaart
staat als tweede in de rail (slechte plek), (4) stijlen met thumbnail +
referenties beheerbaar via het CMS en dan end-to-end werkend, (5) thumbnails
moeten instant laden.

**Besluiten Thierry (2026-08-02):**
- OpenAI **gpt-image-1.5 wordt de default-engine voor alle effecten**; de
  bestaande Settings-toggle (E15.6) blijft als override.
- Create-knop verhuist naar de **paneelheader** (gedocumenteerde
  Figma-afwijking: Figma toont geen custom-effects-UI).
- De **6 nieuwe stijlen** (Balloon, Windy, Sticker, Flowers, 3D-head, Hairy)
  **vervangen** de huidige 4 (clay/wood/3d/scribble → `active=false`, nooit
  verwijderen). Curatiebron: `~/Documents/Aaavatar_ChatGPT Images 2.0
  Edit_2026-05-03_08-35-45/Effects/<Naam>/{References/,Thumbnail/}` +
  `_aaavatar-seed/effects-seed.json` (prompts/keys/orders).

Context uit onderzoek (2026-08-02): E09.1 wees gpt-image af als default om een
*fixbare* reden — het herkadert structureel (schema her-geverifieerd 2026-08-02:
nog steeds alleen 1:1|3:2|2:3) — plus 4–5× kosten/latency. E54.2's negatieve
referentie-verdict gold **alleen nano-banana**; gpt-image + referenties (exact
Thierry's werkende ChatGPT-flow) is nooit getest. Relatie met bestaande stories:
E54.3 (tekst-distillatie) en E54.4 (model per effect) blijven optioneel backlog —
de globale OpenAI-default vervangt de behoefte aan 54.4 grotendeels. 55.6 neemt
de effects-scope van E52.2 (prewarm) over.

---

## 55.1 — Backend: engine-agnostische aspect-contract (pad → generate → crop)
- status: done
- owner: INFRA (2026-08-02)
- team: INFRA
- blockedBy: —
- Result: pad→generate→crop live in `/v1/stylize` (branch `v2/e55-55.1`, merge
  9797d46). `image.ts`: `nearestFixedAspect`/`padToAspect`/`cropBackFromPad`/
  `capLongEdge` (input-cap 2048); `models.ts`: `matchesInputAspect`-capability
  (gpt-image false) + `modelMatchesInputAspect(ref)`; `stylize.ts`: pad vóór,
  proportionele crop-back ná de call, `model_ms`/`pad`/`refs` in de
  stylize_dims-log, getypte 422 `generation_refused`; `replicate.ts` deelt de
  ratio-keuze. Schema-hercheck 2026-08-02: gpt-image-1.5 nog steeds alleen
  1:1|3:2|2:3 → volledige route nodig. image-smoke: 6 nieuwe assertion-blokken
  (canvas-ratio, grijs-pad, no-op-paden, crop-back ±1% over alle drie ratio's,
  oneven maten, cap). tsc groen, `build-v2.sh` alles groen.

Sluitsteen: fixt zorg 2 (plaatsing) én de gpt-image-herkadering uit zorg 1.
**Contract: response-aspect == request-aspect voor élke engine (±1px).**

Scope:
- Stap 0 ✅ (2026-08-02): Replicate-schema `openai/gpt-image-1.5` opnieuw
  gecheckt — `aspect_ratio` enum is nog steeds `["1:1","3:2","2:3"]` → volledige
  pad/crop nodig.
- `backend/lib/image.ts`: sharp-helpers `padToAspect` (gecentreerde letterbox op
  hetzelfde grijs als `flattenOnGrey`) + `cropToAspect` (gecentreerde extract);
  input-cap lange zijde 2048 in de flatten-stap.
- `backend/lib/models.ts`: declaratieve capability `matchesInputAspect` per
  stylize-model (nano-banana/seedream/flux-2 wél, gpt-image niet).
- `backend/api/v1/stylize.ts`: zonder `matchesInputAspect` → pad naar
  dichtstbijzijnde ondersteunde ratio vóór de call, crop terug naar de exacte
  input-ratio erna (op basis van de al meegestuurde `cutout_w/h`). Plus:
  timing-log per model-call en getypte `generation_refused`-fout (credits
  veilig: `logCredit` draait pas ná succes).
- Géén `ShellModel.storeEffectResult`-wijziging — de stabiele takken + centroid-
  compensatie dekken nu elke engine; de ≥2%-reset-tak wordt de uitzondering.
- DoD: aspect-in==uit-assertions (3 gpt-ratio's, oneven maten), `npx tsc
  --noEmit` groen, beide app-targets bouwen, Result-regel.

## 55.2 — Default-flip: server-governed default, client stuurt alleen expliciete keuze
- status: done
- owner: INFRA (2026-08-02)
- team: INFRA
- blockedBy: 55.1 (done)
- Result: OpenAI (gpt-image-1.5) is de stylize-default (branch `v2/e55-55.2`,
  merge a966c78). Backend: `defaultModel: "gpt-image-1.5"` + env-hendel
  `STYLIZE_DEFAULT_MODEL` (pure `resolveStylizeDefaultModel`, whitelist-
  gevalideerd, luide fallback) — vloot-rollback = env + redeploy;
  generate_background blijft nano. Client: `GenerationModelStore.explicit`
  (nil zonder keuze); alle drie de stylize/background-bodies sturen
  `generation_model` alléén bij expliciete keuze (StylizeBody intern voor de
  omissie-test); Settings-copy + case-volgorde geflipt. StylizeQuality:
  `cappedForUpload` (2048, alpha behouden) op beide effects-bronpaden.
  NB: oudere app-builds sturen altijd hun default mee ("nano-banana") — de
  vlootbrede flip landt met de eerstvolgende app-update; server-default dekt
  nieuwe clients direct. Tests: AvatarKit 114/114 (store + omissie),
  Avatar2-suite met 3 nieuwe cap-tests, models-smoke uitgebreid; `build-v2.sh`
  alles groen.

De client stuurt vandaag ALTIJD `generation_model` (code-default `.nanoBanana`),
dus een backend-flip alleen doet niets. Herontwerp voor terugrolbaarheid:
- `AvatarKit/.../GenerationModel.swift`: `explicit: GenerationModel?` (nil
  zonder UserDefaults-key); Settings toont default `.openAI`; copy wisselt
  (OpenAI = default/"best style match", Nano Banana = sneller/identity-lock —
  exacte tekst ter review Thierry). Wie eerder koos, houdt zijn keuze.
- `BackendClient.stylize`: `generation_model` alleen meesturen bij expliciete
  keuze.
- `backend/lib/models.ts`: stylize-default uit `STYLIZE_DEFAULT_MODEL`-env
  (whitelist-gevalideerd), fallback `gpt-image-1.5` → **vloot-rollback = één
  env-var + redeploy**.
- `StylizeQuality.swift`: client-side upload-cap lange zijde 2048 (alpha
  behouden; compatibel met de "kleiner→Lanczos terug"-tak).
- DoD: AvatarKit `swift test` (store-semantiek, veld-omissie), tsc, beide
  targets, Result-regel. Bekend cosmetisch restpunt: tijdens een nood-env-revert
  toont Settings bij niet-kiezers OpenAI terwijl nano draait — geaccepteerd.

## 55.3 — Style-stacking-bug: stylize-bron moet de effect-basis zijn
- status: done
- owner: FEAT (2026-08-02)
- team: FEAT
- blockedBy: —
- Result: gefixt in `EffectsModel.init` (branch `v2/e55-55.3`, merge 92c266a) —
  bij een actief effect volgen `base` én de stylize-bron nu samen
  `effectBaseData`; het `.original`-pad had de bug niet.
  `stylizeSource(choice:)` intern voor de test; `EffectsModelSourceTests`
  (3 tests: actief→basis, inactief→cutout, original ongemoeid). Eerste
  build-run faalde op een ontbrekende `import AvatarKit` in de test —
  gefixt; `build-v2.sh` daarna volledig groen (exit 0, volle log).

`EffectsModel.init`: `base` valt al terug op `portrait.effectBaseData` bij een
actief effect, maar `cutoutImage` (de stylize-bron voor het `.cutout`-pad)
blijft de huidige — al gestylede — cutout. Repro: effect A toepassen → tool
wisselen (paneel-identiteit weg) → Effects heropenen → ongecachet effect B
genereren ⇒ styleert A's output i.p.v. het basisportret. Fix: bij actief effect
ook de stylize-bron uit `effectBaseData` afleiden; `.original`-pad checken op
hetzelfde lek. DoD: unit test op de repro, beide targets, tests groen.

## 55.4 — Create-knop naar de paneelheader
- status: in_progress
- owner: DS+FEAT (2026-08-02)
- team: DS + FEAT
- blockedBy: —

- DS: `AvatarUI/.../DSEditPanel.swift` — `headerAccessory`-ViewBuilder-slot in
  de titelrij (bestaat nog niet); backward-compat via `Accessory == EmptyView`-
  convenience-init (zelfde patroon als `DSEditPanelContainer`).
- FEAT: `EffectsPanel.swift` — createCard uit de rail; compacte ghost
  "+ Create"-headerknop met exact dezelfde Pro-gating en
  `presentation?.createEffectSheetOpen`-mailbox. Rail wordt None → custom →
  built-ins. Let op botsing met de credits-chip bij smalle breedtes.
- Gedocumenteerde Figma-afwijking (besluit Thierry 2026-08-02).
- DoD: AvatarUI-instantiatietest voor de accessory-init, beide targets, visuele
  pass, Result-regel.

## 55.5 — Styles 2.0-content: importer + media-URL-hardening + runbook
- status: done (bouw + dry-run) — **echte run gated op Thierry, zie 55.8**
- owner: INFRA (2026-08-02)
- team: INFRA (bouw + dry-run); echte run **gated op Thierry**
- Result: `backend/scripts/import-effects.mjs` + `run-import-effects.sh` +
  `admin/RUNBOOK-effects.md` (branch `v2/e55-55.5`, merge 484b598). Importer:
  curatiemap + effects-seed.json, normalisatie (refs ≤1024/thumbs ≤800/GIF→
  PNG-frame), idempotente upsert, dry-run default, kit-refs-fallback,
  URL-probe, `--deactivate`. Hardening: 837498f-port (generateFileURL) in de
  v2-main-admin + fail-loud `thumbnailVariant`. **Dry-run-rapport (2026-08-02):
  windy/sticker/3d-head seedbaar (sticker/3d via kit-refs-fallback resp.
  ref-cap); balloon/flowers/hairy geblokkeerd — thumbnails ontbreken
  (Balloon/Flowers/Hairy) en Flowers/Hairy-refs staan los in de map-root
  (Flowers bevat bewust uitgesloten celebrity-ref — NIET blind overnemen).**
  tsc backend groen; admin-tsc: 4 pre-existing fouten los van deze change
  (stash-geverifieerd; aparte fix-taak aangemaakt). build-v2.sh groen.
- blockedBy: — (dry-run meteen: het gap-rapport geeft Thierry doorlooptijd voor
  mapjes fixen)

- Nieuw geversioneerd `backend/scripts/import-effects.mjs` (basis: seed-kit's
  `seed-effects.mjs`, minus nano-banana-thumbnailgeneratie — Thierry cureert nu
  zelf `Thumbnail/`-PNG's). Joint mapassets met `effects-seed.json`; normaliseert
  refs (downscale 1024, GIF→eerste frame + flag, losse bestanden gerapporteerd);
  `--dry-run` default met per-map gap-rapport (bekend: Balloon-thumbnail
  ontbreekt; Sticker/Flowers/Hairy refs niet in de mapconventie); echte run
  upsert-per-key via Payload REST (idempotent → prompt-tweaks uit 55.7 zijn
  her-runbaar), koppelt `styleReferences`; **aparte stap**: oude 4 →
  `active=false`.
- **Media-URL-hardening (vóór elke seed-run):** port `837498f` (directe
  Supabase-`generateFileURL`) van `main` naar de v2-main-admin-config; en
  `thumbnailVariant` (`backend/lib/payload.ts`) logt luid bij regex-mismatch
  i.p.v. stil full-size doorlaten.
- `admin/RUNBOOK-effects.md`: toekomstige stijl toevoegen via de admin-UI
  (thumbnail-specs, goede-referentie-richtlijnen, verifiëren dat `/v1/effects`
  een `/render/image/`-URL geeft).
- DoD: tsc groen backend + admin, dry-run-rapport in de story, Result-regel.
  Echte run + verificatie horen bij 55.8.

## 55.6 — Instant thumbnails
- status: backlog
- team: INFRA + FEAT
- blockedBy: — (zachte dep op 55.5 voor de fallback-keys; die liggen al vast in
  effects-seed.json)

- Nieuwe `EffectsListCache` (AvatarKit, broertje van ThumbnailCache):
  disk-persistentie van de effects- + custom-lijst-JSON; `EffectsModel`
  hydrateert synchroon (sessionCache → disk → fallback) en `loadEffects()` wordt
  stale-while-revalidate → warme opens schilderen instant uit disk-lijst +
  disk-thumbnails.
- De twee lijst-fetches parallel (`async let` i.p.v. sequentieel); custom-lijst-
  falen blokkeert nooit de built-ins (belangrijk zolang sql/015 nog niet op prod
  staat).
- Launch-prewarm (= E52.2-scope voor effects; status daar bijwerken):
  fire-and-forget lijst-fetch + `ThumbnailCache.prefetch` bij app-start.
- Backend: custom-effect-thumbnails door `thumbnailVariant(url, 320)` in
  `backend/lib/customEffects.ts`.
- `RemoteEffect.fallback` → de 6 nieuwe keys/labels. ThumbnailCache-hygiëne:
  LRU-byte-cap (~100 MB) op Caches/CMSThumbnails.
- DoD: `swift test` voor EffectsListCache (round-trip, corrupt bestand, SWR-
  volgorde), tsc, beide targets, koude-start-timing vóór/na in de Result-regel.

## 55.7 — Validatie-bakeoff: gpt-image-1.5 + refs + aspect-contract op de 6 nieuwe stijlen
- status: backlog
- team: AI
- blockedBy: 55.1 (pad/crop in de callshape) + 55.5-dry-run-assets (prompts +
  genormaliseerde refs; prod-seed NIET nodig — harness raakt Replicate direct,
  callshape 1-op-1 incl. IDENTITY_CLAUSE/STYLE_REFERENCE_CLAUSE/flattenOnGrey/
  pad/crop; e09-1/e54-precedent, drivers globaal throttlen)

Matrix: 6 stijlen × 2–3 E09-portretten × {quality high, medium} × {refs aan,
uit}. Meet: identiteit, stijltrouw t.o.v. Thierry's gecureerde outputs, framing
(houdt het ratio-contract? schildert het model in de letterbox → content weg
bij crop-back?), latency p50/p95 t.o.v. de 80s-timeout, kosten per beeld
(Replicate-prijspagina). Levert: quality-tier-default, per-stijl refs-verdict,
**krediettarief-aanbeveling voor Thierry** (nu vlak 4; E14.3-precedent 4/7),
prompt-tweaks → idempotente 55.5-her-run, expliciete go/no-go voor de prod-flip.
Rapportage in de e54-bakeoff-conventie (buiten repo), samenvatting hier.

## 55.8 — Prod-uitrol (voorbereid door INFRA, uitgevoerd door Thierry)
- status: backlog
- team: INFRA
- blockedBy: 55.1, 55.2, 55.5, 55.7-go (55.3/55.4/55.6 liften mee op de
  volgende app-build, onafhankelijk van backend-deploy)

Checklist (volgorde is bindend):
1. `sql/015` (custom effects) op prod-Supabase; afstemmen met openstaande
   `sql/018` (E14.9) — numerieke volgorde, smoke na elk.
2. Backend-deploy (avatars-api): aspect-contract, env-default (laat
   `STYLIZE_DEFAULT_MODEL` ongezet → gpt-image-1.5), custom-thumb-variant,
   fail-loud thumbnailVariant.
3. Admin-deploy (avatar-admin) mét de 837498f-port; probe vóór seeden: wegwerp-
   media uploaden, URL-vorm = directe Supabase, weer verwijderen.
4. `import-effects.mjs` echt draaien (Thierry, creds via vercel env); daarna
   oude 4 op `active=false`.
5. Verifiëren: `/v1/effects` → 6 actieve stijlen, allemaal 320px
   `/render/image/`-URLs, volgorde klopt; app-smoke: koude-start-thumbs, 2
   generaties, plaatsing met verplaatst/geschaald portret, 1 custom effect
   end-to-end.
6. Rollback-hendels op papier: `STYLIZE_DEFAULT_MODEL=nano-banana` + redeploy
   (vloot, niet-kiezers), oude stijlen her-activeren, per-user toggle blijft.
   (Bestaande gebruikers van oude stijlen zijn veilig: selectie is key-gebaseerd
   en cache-hydratatie werkt zonder lijst-entry; alleen regenereren van een
   gedeactiveerde stijl vervalt.)

---

## Risico's
- **Latency**: gpt-image quality=high geregeld >50s; 80s-timeout / 90s
  Vercel-cap — timing-logs (55.1) + p95 (55.7) beslissen high vs medium.
- **Letterbox-artefacten**: model kan in het grijze pad schilderen → bakeoff
  checkt expliciet; fallback = lichte center-crop richting doelratio i.p.v. pad.
- **Moderation-weigeringen** op portretten → getypte fout + nette melding; geen
  credit-verlies (aftrek ná succes).
- **Kosten/marge**: 4–5× nano bij vlak 4 credits → tariefbesluit Thierry bij
  55.7/55.8.
- **Admin-media-URL-drift** (837498f alleen op `main`) → port + fail-loud +
  pre-seed-probe.
