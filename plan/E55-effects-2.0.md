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

**Amendement (besluit Thierry, 2026-08-02 avond): gpt-image-2 i.p.v. 1.5.**
`openai/gpt-image-2` bleek live op Replicate — ruimere ratio-set (1:1/3:2/2:3/
4:3/3:4/16:9/9:16 → het pad/crop-contract padt dun tot nul), quality-tiers
low/medium/high/auto en per tier iets goedkoper ($0.012/$0.047/$0.128 vs
1.5's $0.013/$0.05/$0.136; nano $0.039 — medium ≈ nano-pariteit). 2.0 is nu
overal de user-facing OpenAI-engine (stylize-default, Settings-key
`gpt-image-2`, generate_background-keuze); **1.5 blijft registry-only** als
55.7-identity-vergelijkingsarm en env-fallback, want 2.0 dropte de expliciete
`input_fidelity`-parameter — identiteitsbehoud is het punt dat de bakeoff
moet bewijzen (`--model openai/gpt-image-1.5` in de driver voor de A/B).
Een oude dev-voorkeur "gpt-image-1.5" in UserDefaults degradeert bewust naar
de server-default (niets geshipt; test dekt het).

**Edge-case-sweep (2026-08-02, na de 2.0-swap) — gevonden & gefixt:**
1. *Edit-intents migreerden ongevraagd mee met de default-flip*: /v1/stylize
   dient óók hair/clothes/face (E10/E11/E32), en die deelden de registry-
   default. E09.1 koos nano juist dáár op "alleen het doel wijzigt". Nu
   intent-scoped: Effects-intents → gpt-image-2, edit-intents → nano-banana;
   expliciete Settings-keuze en dev-override winnen overal (ongewijzigd).
2. *AI-achtergrond "OpenAI" was stil kapot na de swap*:
   BackgroundGenerationCatalog stuurde hardcoded "gpt-image-1.5" (niet meer
   user-selectable → server degradeerde stil naar nano) → key nu "gpt-image-2".
3. *Dev-model-picker miste 2.0*: DevModelOverrides-whitelists aangevuld.
4. *Crop-back bij ratio-ongehoorzaamheid*: negeert het model de gevraagde
   ratio, dan pakte de proportionele terugsnede de verkeerde regio →
   weigering-guard (>2% afwijking = crop overslaan + luid loggen; client
   herkadert dan zelf). Smoke-assertion toegevoegd.

**Gebruikersperspectief-sweep (2026-08-02, tweede pas) — gevonden & gefixt:**
5. *Safety-weigering toonde de generieke "probeer opnieuw"-toast*: de server
   stuurde sinds 55.1 een getypte 422 `generation_refused`, maar de app
   kende 'm niet — een gebruiker met een geweigerde foto bleef kansloze
   retries van 30–60s doen. Nu: `BackendError.generationRefused` + eigen
   copy ("try a different photo — no credits were charged") in Effects-,
   Clothes-, Hair- én FaceActions-paneel.
6. *Settings-copy loog na de intent-scoped defaults*: "Default — best style
   match" bij OpenAI klopte niet meer voor hair/kleding → copy benoemt nu
   per model wáár het de default is.

**Open UX-punten (besluit/bakeoff, geen code nu):**
- *Latency zonder cancel*: → **besloten en gebouwd, zie 55.9** (Thierry
  2026-08-03: kwaliteit blijft high; wachttijd draaglijk via feedback +
  cancel-als-detach, niet via een lager kwaliteitstier — de medium-armen in
  55.7 zijn daarmee informatief, niet beslissend).
- *App sluiten tijdens een lange generatie*: rondt de server af ná het
  wegklikken, dan zijn 4 credits betaald zonder ontvangen beeld (smal
  venster, groter naarmate generaties langer duren). Accepteren of ooit
  server-side result-cache — noteren bij het tariefbesluit.
- *Wees-selectie na deactivatie*: een portret met een oud effect (clay etc.)
  actief toont na de seed géén geselecteerde kaart meer (key-cache werkt,
  kaart is weg; terugkeren naar het effect kan alleen via cache/undo).
  Nul echte gebruikers vandaag — alleen relevant als stijlen ooit ná launch
  gedeactiveerd worden; dan een "ghost-kaart voor actieve onbekende key".
- *CreateEffectSheet mist een hint* dat referenties met herkenbare gezichten
  identity-bleed geven (de curatie-regel die het CMS-veld wél documenteert)
  — één regel helper-copy, kan mee met een volgende FEAT-story.

**Bekende rest-randgevallen (bewust open, met eigenaar):**
- *Fallback-keys-venster*: een app-build mét de nieuwe 6 fallback-keys vóór de
  prod-seed → offline-fallback-generatie geeft 400 op de nieuwe keys (alleen
  als de lijst-fetch faalt maar stylize werkt — zeldzaam; disk-cache dempt).
  → 55.8-volgorde: seed vóór de app-release (staat in de checklist).
- *Custom-effects-disk-cache is account-agnostisch* (E55.6): na account-wissel
  op dezelfde Mac tonen custom-kaarten van het vorige account tot de refresh
  ze vervangt. Single-user-risico laag; nette fix = cache per user-id of
  wissen bij logout — follow-up-story als accountwissel realistisch wordt.
- *Importer --force* uploadt verse media zonder de oude te wissen (idempotent
  op het effect-doc, media-rijen stapelen) — opruimen kan via de admin-UI.
- *Zeer brede banner-achtergronden* (>16:9) snappen bij gpt-image-2 naar 16:9
  — pre-existing E42-gedrag (was op 1.5 erger: 3:2), geen regressie.

Context uit onderzoek (2026-08-02): E09.1 wees gpt-image af als default om een
*fixbare* reden — het herkadert structureel (1.5-schema her-geverifieerd
2026-08-02: alleen 1:1|3:2|2:3) — plus 4–5× kosten/latency. E54.2's negatieve
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
- status: done
- owner: DS+FEAT (2026-08-02)
- team: DS + FEAT
- blockedBy: —
- Result: `DSEditPanel` heeft een generiek `headerAccessory`-slot (trailing in
  de titelrij, na de credits-chip; EmptyView-convenience voor back-compat —
  bestaande call sites ongewijzigd). EffectsPanel: createCard weg uit de rail,
  compacte `DSGhostButton("Create", +, .small)` + `DSProChip` (niet-Pro) in de
  header met identieke gating/mailbox. Rail = None → custom → built-ins.
  Figma-afwijking gedocumenteerd (besluit Thierry 2026-08-02). Branch
  `v2/e55-55.4`, merge 04dba26; AvatarUI 55/55; build-v2.sh groen (exit 0).

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
- status: done
- owner: INFRA+FEAT (2026-08-02)
- team: INFRA + FEAT
- Result: koude paneel-open hangt niet meer aan de lijst-round-trip (branch
  `v2/e55-55.6`, merge 039c504). `EffectsListCache` (Caches/CMSLists)
  persisteert beide lijsten; hydratie sessie → disk → fallback + SWR-refresh;
  fetches parallel (custom blokkeert built-ins nooit); launch-prewarm
  `EffectsModel.prewarm` in Avatar2App (= E52.2-effects, status daar
  bijgewerkt); modellen Codable; fallback → de 6 nieuwe keys; backend geeft
  custom-thumbs de 320px-variant; ThumbnailCache LRU-cap 100 MB (mtime-touch
  op disk-hit). Meting: disk-hydratie ~ms (test-assert <100 ms) waar eerst een
  ~200–500 ms netwerk-round-trip elke thumbnail blokkeerde; her-opens waren al
  instant (E52.1) en blijven dat. AvatarKit 123/123, tsc groen, build-v2.sh
  groen (exit 0).
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

## 55.7 — Validatie-bakeoff: gpt-image (2.0) + refs + aspect-contract op de 6 nieuwe stijlen
- status: done (runs 2026-08-03, autorisatie Thierry; besluitpunten hieronder)
- owner: AI (2026-08-02/03)
- team: AI
- Result: **36-run-matrix gedraaid** (6 stijlen × p1/p3 × {high-refs,
  high-norefs, medium-refs}, gpt-image-2, volledige prod-pipeline incl.
  pad/crop; token uit v1-`backend/.env.local` — de Vercel-env is Sensitive en
  pull't leeg). Beeldmateriaal + contactsheet:
  `~/Documents/Claude/Projects/Aaavatar/e55-bakeoff/` (34/36 OK).
  **Bevindingen:**
  - **Identiteit: behouden in álle 34 runs** — beide portretten herkenbaar in
    elke stijl/arm, zónder input_fidelity. Het 2.0-identity-risico is van
    tafel. ✅ GO.
  - **Stijltrouw: uitstekend**; refs verhogen de commitment (balloon: alleen
    refs-arm levert het volledige zwevende-ballonhoofd; windy: extremere
    g-force; hairy: matte-render-look van de ref). Sticker/3d-head: alle
    armen sterk, refs sturen vooral de smaak. → **refs AAN per default**.
  - **Aspect-contract: 34/34** ratio-OK; kleine inputs (612/740px) kwamen
    als 1024–1536 terug (gratis res-winst).
  - **Latency (de hoofdvondst): high p50 169s / p95 214s / max 236s —
    2,5× trager dan medium (p50 65s / p95 75s, één 149s-uitschieter) en ver
    voorbij elk 90s-budget; p95+overhead schuurt tegen Vercels 300s-plafond.**
    Het 55.9-besluit ("high blijft") is genomen op de aanname 40–70s;
    de meting zegt ~3 min per effect.
  - **Moderation: flowers-refs → 2/2 geweigerd op p3** (E005; norefs-arm
    slaagde — de gerbera-over-gezicht-REFS zijn de trigger, niet portret of
    prompt). Flowers-resultaten zónder refs zijn magazine-waardig.
  - **Kosten:** high $0.128 / medium $0.047 per beeld (nano $0.039);
    matrix + smoke ≈ $4.
  **Besluitpunten Thierry (55.8-gate):**
  1. **Kwaliteitstier**: aanbeveling = **medium als default** (visueel ≈ high
     op kaartformaat in 5/6 stijlen; ~1 min past bij de nieuwe toast en
     medium ≈ nano-kostenpariteit) — high evt. later als premium-arm (E14.3-
     precedent 7cr, "Best quality — takes ~3 min"). Alternatief: high houden →
     maxDuration 300 + STYLIZE_TIMEOUT_MS ~250s + toast-verwachting 180s.
  2. **Tarief**: bij medium kan vlak 4cr blijven (marge ≈ nano).
  3. **Flowers**: prompt-only seeden (refs weglaten) of nieuwe refs cureren.
  4. Budget-/toastwaarden bij de deploy: medium-pad → STYLIZE_TIMEOUT_MS
     160s, maxDuration 180, `expectedGenerationSeconds` 90.
  Harness-extra's: `--timeout`-meethendel (stylizeEdit `timeoutMs`, prod
  ongewijzigd) + eerlijke timeout-errormessage; results.json draagt het model.
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

**Harness done (2026-08-02):** `backend/scripts/effects-bakeoff.ts` — de
volledige matrix door de échte pipeline als lib-calls (capLongEdge →
flattenOnGrey → padToAspect → stylizeEdit met nieuwe `gptQuality`-hendel →
cropBackFromPad), prompt 1-op-1 (seed-prompt + STYLE_REFERENCE_CLAUSE bij refs
+ FRAMING_CLAUSE — clausules verhuisd naar side-effect-vrij
`lib/stylizePrompts.ts`, gedeeld met /v1/stylize), refs zoals de importer ze
seedt (curatiemap → kit-fallback, ≤1024px, cap 3 — droog geverifieerd voor
alle 6 stijlen), strikt sequentieel met 11s spacing (Replicate-throttle-regel),
output: PNG's + `results.json` (latency p50/p95, ratio-contract-check per run)
+ `index.html`-contactsheet. **Run (Thierry, of een AI-sessie mét token):**

    cd backend
    REPLICATE_API_TOKEN=… npx tsx scripts/effects-bakeoff.ts \
      ~/Documents/Claude/Projects/Aaavatar/e09-bakeoff/inputs \
      ~/Documents/Claude/Projects/Aaavatar/e55-bakeoff \
      --arms high-refs,high-norefs,medium-refs

    # kleine validatierun eerst (1 stijl × 2 portretten × 3 armen ≈ 6 calls):
    #   … --styles balloon

Standaardmatrix = 6 stijlen × 2 E09-portretten (p1/p3, zoals E54.2) × 3 armen
= 36 runs (~7 min door de spacing). Kosten per tier: modelpagina-HTML
(replicate-metadata-memory). Geen lokale token gevonden (2026-08-02) en de
prod-env is bewust niet autonoom getrokken — zie de statusregel hierboven.

## 55.9 — Generatie-feedback + cancel-als-detach (besluit Thierry 2026-08-03)
- status: done
- owner: FEAT (2026-08-03)
- team: FEAT
- blockedBy: —

Besluit: kwaliteit blijft **high**; de 40–70s-wachttijd wordt draaglijk via
betere feedback en een cancel — niet via het medium-tier. Gebouwd:
- **WorkingToast**: verstreken tijd (mm:ss, TimelineView), dunne voortgangs-
  balk richting de verwachte duur (cap 92% — nooit "vol" beloven), hint
  "usually ~1 min" die voorbij de verwachting eerlijk "still working…" wordt;
  `WorkingContext` + `presentWorking` uitgebreid (startedAt/expectedSeconds/
  onCancel — bestaande call sites ongewijzigd via defaults).
- **Cancel = detachen** (EffectsModel): de server rekent pas af ná succes en
  de call loopt door, dus "echt" annuleren = betalen zonder resultaat.
  Cancel geeft de editor meteen terug; het resultaat landt stil in de
  kaart-cache + `portrait.effectCache` (persist). Opnieuw tikken op die
  kaart tijdens de run = re-attach van de toast (verstreken tijd telt door,
  géén dubbele generatie/credits); fouten na detach zijn stil (niets
  afgeschreven). Verwachting nu 75s — 55.7 herijkt met echte p50/p95.
- **"Klaar"-stip** op gegenereerde-maar-niet-actieve kaarten (checkmark,
  topTrailing) — maakt de gratis instant-cache zichtbaar én is de
  landingsplek van een gedetachte generatie.
- **CreateEffectSheet**: gezichts-hint ("faces in the reference can bleed
  into your result") — zelfde curatie-regel als het CMS-veld.
- Tests: `WorkingToastLabelTests` (mm:ss, minuut-afronding, still-working-
  grens); build-v2.sh groen.

## 55.8 — Prod-uitrol (voorbereid door INFRA, uitgevoerd door Thierry)
- status: ready — **alle stappen gated op Thierry**; code op v2-main staat klaar
- team: INFRA
- blockedBy: 55.7-go (55.3/55.4/55.6 liften mee op de volgende app-build,
  onafhankelijk van backend-deploy)

**Voorwerk Thierry vóór de seed-run (uit het 55.5-dry-run-rapport):**
- Balloon: thumbnail in `Balloon/Thumbnail/` zetten.
- Flowers + Hairy: thumbnail toevoegen én de losse refs in de map-root naar
  `References/` verplaatsen (Flowers: de celebrity-ref er NIET in — de kit
  sloot 'm bewust uit; Hairy: GIF's worden eerste-frame-PNG, check even).
- Sticker: 2 losse refs in de map-root → `References/` (of kit-fallback laten).
- Windy/3D: >4 refs — de importer capt op 4 en meldt welke hij dropt; volgorde
  sturen = bestandsnamen hernummeren.

Checklist (volgorde is bindend):
1. **Bakeoff eerst** (55.7): `effects-bakeoff.ts` draaien (commando daar),
   contactsheet beoordelen → go/no-go + quality-tier + refs-per-stijl +
   tariefbesluit.
2. `sql/015` (custom effects) op prod-Supabase; afstemmen met openstaande
   `sql/018` (E14.9) — numerieke volgorde, smoke na elk.
3. Backend-deploy (avatars-api, vanaf repo-root — vercel-cli-memory): brengt
   aspect-contract, gpt-image-default (laat `STYLIZE_DEFAULT_MODEL` ongezet),
   custom-thumb-variant, fail-loud thumbnailVariant, 422-refusal-mapping.
4. Admin-deploy (avatar-admin, `.vercelignore`-swap) mét de 837498f-port;
   probe vóór seeden zit in de importer (--apply doet 'm automatisch).
5. Seed-run: `bash backend/scripts/run-import-effects.sh` (env-pull + dry-run
   + bevestiging + optionele deactivatie van clay/wood/3d/scribble).
   **Vóór elke app-release met deze E55-build**: de app-fallback kent nu de
   zes nieuwe keys — seed dus eerst, anders geeft offline-fallback-generatie
   in het venster ertussen een 400 op die keys (edge-sweep-notitie).
6. Verifiëren: `/v1/effects` → 6 actieve stijlen, allemaal 320px
   `/render/image/`-URLs, volgorde 10–15; app-smoke: koude-start-thumbs
   (eerste open uit disk/prewarm), 2 generaties op een verplaatst/geschaald
   portret (plaatsing blijft staan), 1 custom effect end-to-end (post-sql/015).
7. Rollback-hendels: `STYLIZE_DEFAULT_MODEL=nano-banana` + redeploy (vloot,
   niet-kiezers — NB: pas effectief voor app-builds mét 55.2; oudere builds
   sturen hun eigen default mee), oude stijlen her-activeren via admin,
   per-user Settings-toggle blijft. (Bestaande gebruikers van oude stijlen
   zijn veilig: selectie is key-gebaseerd en cache-hydratatie werkt zonder
   lijst-entry; alleen regenereren van een gedeactiveerde stijl vervalt —
   server houdt STYLE_PROMPTS-fallback voor de oude 4 keys, dus ook dat werkt.)

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
