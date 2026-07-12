# E41 — Boost Resolution: beste model + lokale optie

Team: **INFRA** (cloud-model + endpoint-params) · **FEAT** (lokale on-device-route + wiring)

Voortgekomen uit een audit (Thierry, 2026-06-26): "gebruiken we het beste AI-model om een portret
te upscalen/verscherpen?" Bevinding: `/v1/upscale` draaide **Real-ESRGAN met `face_enhance:
false`** — een generieke upscaler met de gezicht-specifieke stap UIT, suboptimaal voor portretten.
Besluit: check Replicate, zet de winnaar als default, én bied een **lokale optie** voor wie online
modellen niet toestaat (`AIPrivacyMode2.localOnly`).

Replicate-research (2026-06-26): **philz1337x/crystal-upscaler** is portret-geoptimaliseerd —
behoudt huidtextuur + gezichtsidentiteit zonder "plastic look", tot 10K, snel (~1.2s @1K),
~$0.016/beeld. Wint voor een avatar-app (identiteit = het product; anti-AI-slop). Alternatieven:
sczhou/codeformer (goedkoop ~$0.0065, face-restore + fidelity-knop), topazlabs/image-upscale
(premium/veelzijdig), Real-ESRGAN+`face_enhance:true` (bijna gratis fallback). Bronnen in de
commit-/chat-historie.

---

## 41.1 — Cloud-default → crystal-upscaler + per-model input-adapter
- status: done (port-only; preview-verificatie + hash-pin open)
- owner: INFRA (2026-06-26)
- team: INFRA
- Result: `models.ts` `upscale.defaultModel` → `crystal-upscaler` (`philz1337x/crystal-upscaler`,
  portret-geoptimaliseerd), met `real-esrgan` als alternatief in de registry. `replicate.ts`:
  nieuwe `upscaleInputFor(ref, imageDataUrl)` (spiegelt `stylizeInputFor`) — crystal →
  `{ image, scale_factor: 2 }`, Real-ESRGAN/onbekend → `{ image, scale: 2, face_enhance: true }`
  (de audit-bevinding: face_enhance stond op false → nu aan voor de fallback). Swift-kant
  (`BackendClient.upscale`) ongewijzigd. **Open (alleen op deploy te doen):** crystal is een
  community-model → pin de versie-hash + verifieer `/v1/upscale` op een Vercel preview-deploy
  (`cd backend && vercel`); bij 404 hash herpinnen. Port-only → niet door build-v2.sh gedekt.

- `backend/lib/models.ts`: `upscale.defaultModel` → `crystal-upscaler`; voeg het model toe aan de
  registry (community-slug → **gepinde versie-hash vereist**, te bevestigen op de preview-deploy;
  net als birefnet/deoldify). Houd `real-esrgan` als alternatief in de registry, nu met
  `face_enhance: true`.
- `backend/lib/replicate.ts`: `upscale()` mag niet langer één vaste input-dict hardcoden — crystal
  gebruikt `{ image, scale_factor }`, Real-ESRGAN `{ image, scale, face_enhance }`. Introduceer
  `upscaleInputFor(modelRef, imageDataUrl)` (spiegelt `stylizeInputFor`).
- Port-only (niet door build-v2.sh gebouwd): verifieer endpoint + pin de crystal-versie-hash op
  een Vercel preview-deploy vóór productie.
- DoD: Swift-kant (BackendClient.upscale ongewijzigd) bouwt; backend port-only → preview-test;
  Result-regel.

## 41.2 — Lokale on-device Boost (localOnly, geen cloud/credits)
- status: done
- owner: FEAT (2026-06-26)
- team: FEAT
- Result: `LocalUpscale` (Core Image, gedeelde GPU-`CIContext`): Lanczos 2× + milde unsharp-mask op
  de cutout-PNG (Data→Data, behoudt alpha), off-main aanroepbaar. `EditorView.runBoostResolution`
  vertakt nu: `mode == .localOnly` → `runLocalBoost` (geen `allowCloudFeature`-gate, geen credit,
  undo'baar via `ImageEnhanceUndo`, off-main via `Task.detached`); anders het bestaande cloud-pad.
  Voorheen kreeg een localOnly-gebruiker de "enable online"-gate en kón niet boosten. `EditColorPanel`
  toont op "Boost" "Free" i.p.v. een credit-chip in localOnly. `LocalUpscaleTests` (2, groen): 2×
  maat + geldige PNG. DoD groen (build-v2.sh "alles groen"; 9/9 Avatar2-tests inc. shaders/render).

- `LocalUpscale` (Core Image): Lanczos 2× + unsharp-mask op de cutout-PNG (Data→Data, off-main).
  Geen model-download/app-bloat; eerlijk "scherper + groter" zonder AI-hallucinatie. Behoudt alpha.
- `EditorView.runBoostResolution`: bij `PrivacyPreferences2.shared.mode == .localOnly` → lokale
  route (geen `allowCloudFeature`-gate, geen credit, undo'baar); anders het bestaande cloud-pad.
- Credit-chip op "Boost" toont in localOnly "Free" i.p.v. een credit-kost.
- DoD: beide targets bouwen, een test die `LocalUpscale` een groter beeld oplevert, tests groen,
  Result-regel.
- Follow-up (Thierry 2026-06-26): expliciete keuze i.p.v. impliciet op de privacymodus — de
  Boost-chip is nu een **dropdown** (popover met onze `DSContextMenuPanel` + `DSMenuRow`, zelfde
  patroon als de DSColorPicker-popover): "On device · Free" vs "Online · Best · 1 credit"
  (in localOnly toont Online "Enable online" en loopt via de bestaande cloud-gate). `onBoost` werd
  `(BoostMode) -> Void`; `runBoostResolution(_:)` vertakt op de gekozen modus i.p.v. op de
  privacymodus. De chip onthoudt de laatste keuze. Geen auto-spend: de gebruiker kiest per keer.
  DoD groen.

## 41.3 — Crystal-upscaler versie-hash pinnen
- status: in_progress (heropend 2026-07-02 22:xx)
- team: INFRA
- blockedBy: —

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevinding D8).
**Wat:** `backend/lib/models.ts:143-146` heeft `philz1337x/crystal-upscaler` als
cloud-default staan **zonder** gepinde versie-hash — tegen de eigen
41.1-waarschuwing in ("community-model → unversioned slug kan 404'en; PIN de
versie-hash vóór productie"). BiRefNet/DeOldify/Real-ESRGAN zijn wél gepind.
**Voorstel:** de huidige crystal-upscaler-versie opzoeken op Replicate en de hash
pinnen, net als de andere modellen in de registry; verifiëren op een Vercel
preview-deploy.
**DoD:** `/v1/upscale` met crystal-upscaler werkt op een preview-deploy met de
gepinde hash; Result-regel.

**Result:** `philz1337x/crystal-upscaler` gepind op versie-hash
`5d917b1444c89ed91055f3052d27e1ad433a1218599a36544510e1dfa9ac26c8` (huidige
latest op replicate.com/philz1337x/crystal-upscaler, 2026-07-02) in
`backend/lib/models.ts`; `upscaleInputFor` (lib/replicate.ts) matcht op het
slug-prefix, dus de `{ image, scale_factor }`-payload blijft intact.
`scripts/models-smoke.ts` (lokaal, geen netwerk) uitgebreid met een generieke
guard — élk community-model (niet-officiële owner) moet `slug:64-hex` gepind
zijn — plus een expliciete check op de Boost-default; smoke OK, `npx tsc
--noEmit` groen. Verificatie bewust statisch i.p.v. live (Replicate-ratelimit-
regel: geen echte inference-calls); runtime-verificatie lift mee op de
eerstvolgende preview/prod-deploy (E43-akkoord loopt).


**Heropening 41.3 (2026-07-02 ~22:00):** de gepinde crystal-hash faalt live met
422 "Invalid version or not permitted" → 500's op /v1/upscale (21:42). Hotfix
(andere sessie, gecommit + gedeployed door hoofdsessie): default terug naar
real-esrgan; crystal blijft geregistreerd. Vervolg: geldige hash ophalen via
replicate.com/philz1337x/crystal-upscaler/versions (login vereist — Thierry),
live testen op preview, dán default terugzetten.

**Update 2026-07-03 (onderzoek 41.4):** de login-route is overbodig én zinloos.
De gepinde hash `5d917b14…` IS de huidige latest version (te verifiëren zonder
login: `latest_version` staat in de HTML van de modelpagina, `curl -sL
replicate.com/philz1337x/crystal-upscaler`). 422 "Invalid version or not
permitted" betekent dus niet "verkeerde hash" maar "deze versie mag niet
versioned gedraaid worden" — crystal kan alleen unversioned (vereist een
uitzondering op de models-smoke-guard) of vervalt. Zie 41.4: crystal is als
default sowieso ingehaald. 41.3 gaat op in 41.4.

## 41.4 — "Perfect vrijstaand" upscale-pipeline + model-bakeoff
- status: done
- owner: INFRA (2026-07-03)
- team: INFRA
- blockedBy: —

Voortgekomen uit Thierry's kwaliteitsklacht (2026-07-03): Boost online maakt
huid glad, gumt details (sproeten, oorbellen, piercings) en verslechtert de
haar-cutout. Gewenste uitkomst expliciet: **top-notch upscale, en vrijstaand
blijft perfect vrijstaand.**

**Diagnose (drie onafhankelijke oorzaken, alle drie aan te pakken):**
1. Fallback-model real-esrgan draait met `face_enhance: true` (GFPGAN,
   sinds 41.1) — dat *reconstrueert* het gezicht generatief: huid geairbrusht,
   sproeten/sieraden weg. Voor een identiteitsproduct de verkeerde stand.
2. `flattenOnGrey` mengt halfdoorzichtige haarpixels met grijs vóór de
   upscale; `reapplyAlpha` hangt daarna de *oude* alpha bilineair terug →
   grijze halo in haarranden + masker dat niet spoort met hergetekend haar.
3. De beoogde default (crystal) staat uit door het 422-incident (zie update
   41.3 hierboven — geen hash-probleem maar version-not-permitted).

**Kandidatenveld (2026-07-03, schema's + prijzen uit modelpagina-HTML):**

| model | prijs | aard | input | output |
|---|---|---|---|---|
| `topazlabs/image-upscale` | ~$0.08/unit (unit-definitie op preview verifiëren!) | professioneel, fidelity-first (Gigapixel) | `enhance_model:"High Fidelity V2"`, `upscale_factor:"2x"`, `face_enhancement` (bool + creativity 0–1 + strength), `subject_detection:"Foreground"` | png |
| `google/upscaler` | $0.02/beeld | officieel Google (Imagen-familie), fidelity | `upscale_factor:"x2"/"x4"`, `compression_quality` (default 80 → **100 zetten**) | jpeg |
| `philz1337x/crystal-upscaler` | $0.05 (≤4MP, tiered daarboven) | H100-diffusie (Clarity), `creativity 0–10` | `scale_factor` | png |
| `recraft-ai/recraft-crisp-upscale` | $0.006 | web/crisp-gericht | alleen `image` | ? |
| `nightmareai/real-esrgan` (huidig) | ~$0.002 | generiek SR, "plastic" prior | `scale`, `face_enhance` | png |

Officiële modellen (topaz, google, recraft) draaien unversioned — geen
hash-pin-risico à la 41.3.

**Besluit — pipeline (modelonafhankelijk; dít is de "perfect vrijstaand"-fix):**
- a. **Edge-bleed vóór flatten** (`lib/image.ts`): kleuren van opake pixels
  uitsmeren in het transparante gebied (premultiply→blur→divide of iteratieve
  dilatie, raw-pixel-pass met sharp) zodat halfdoorzichtig haar met haarkleur
  mengt i.p.v. met grijs. Neutraliseert de halo bij de bron.
- b. Fidelity-upscale van de geflattende RGB (model hieronder).
- c. **Alpha apart mee-schalen met lanczos3, zácht houden** — geen harde
  threshold server-side (dat vernietigt haar-softness; de client hardent alleen
  in het mask-apply-pad). PNG-output vragen waar het kan; bij google q100.
- d. Opaque input (geen cutout) blijft gewoon werken: bleed/flatten zijn dan
  no-ops, reapplyAlpha hangt een opaque alpha terug.

**Besluit — model:** beoogde default **Topaz `High Fidelity V2`, 2×,
`face_enhancement: false`, png** (industriestandaard detail-behoud, geen
generatieve gezichtsreconstructie; arm mét `face_enhancement@creativity 0`
draait ter vergelijking mee). Tweede arm/goedkope fallback: **google/upscaler
x2 @ q100**. real-esrgan terug naar `face_enhance: false` (identiteit >
scherpte) en blijft nood-fallback. Crystal doet als unversioned arm mee in de
bakeoff maar is geen default-kandidaat meer (diffusie = textuur-resynthese).

**Verificatie (crystal-les: nooit een default flippen zonder live test):**
preview-deploy, `model_override`-armen op de E09-portretset (p1–p5, haar- en
identiteits-stress), contactsheets input|armen, beoordeling op identiteit
(sproeten/sieraden intact), haarranden op donkere én lichte achtergrond, en
Topaz' unit-billing in de Replicate-usage. Drivers globaal throttlen
(Replicate-ratelimit-regel).

**DoD:** bleed + alpha-reapply unit-tests op `lib/image.ts` (lokaal, sharp);
contactsheet-bakeoff op preview; default-flip naar de winnaar; `face_enhance`
fallback-fix; Result-regel met gekozen arm + geverifieerde Topaz-unitprijs.

**Result (deel 1, code — 2026-07-03):** pipeline + armen gebouwd en lokaal
groen (`npx tsc --noEmit`, `scripts/models-smoke.ts`, nieuw
`scripts/image-smoke.ts`; backend port-only, Swift ongewijzigd).
- `lib/image.ts` `bleedFlatten`: edge-bleed (premultiply→blur→unpremultiply,
  σ12) + composite over het bleed-veld; grijs-fallback buiten bereik. Smoke
  bewijst: zachte rand houdt objectkleur (naive flatten mengt daar ~50%
  grijs). Let op: alpha blurt als (a,a,a)-drieband door dezelfde 3-kanaals
  pijplijn — vips blurt 1-kanaals aantoonbaar anders en dat sloopte de ratio.
- **Bonus-bug gevonden en gefixt:** `reapplyAlpha` gebruikte `joinChannel`,
  en sharp 0.33.5 dropt dat kanaal stilletjes (3-kanaals output, geen error)
  wanneer de alpha uit `extractChannel` komt. /v1/upscale én /v1/colorize
  gaven dus al die tijd een opaque grijs-backdrop-beeld terug; de client zag
  geen cutout en liet ORMBG opnieuw uitknippen — dé verklaring voor "haar
  slechter uitgeknipt" (klacht 2026-07-03). Nu raw-interleave, bewijsbaar
  RGBA; smoke dekt de regressie (channels=4 + zachte randalpha).
- `models.ts`: armen `topaz` (topazlabs/image-upscale) en `google-upscaler`
  (google/upscaler) toegevoegd; crystal → unversioned (422-naschrift
  hierboven); default blijft real-esrgan tot de bakeoff. `replicate.ts`
  `upscaleInputFor`: topaz = High Fidelity V2/2x/face_enhancement uit/png;
  google = x2/q100; real-esrgan → `face_enhance: false` (de
  gladde-huid-oorzaak). `models-smoke`: stale crystal-default-assert gefixt,
  pin-guard met expliciete crystal-uitzondering, override-asserts nieuwe armen.
- Timing 2048²: bleedFlatten 150 ms, reapplyAlpha (4096²) 356 ms.
**Open:** preview-deploy → contactsheet-bakeoff (topaz/google/crystal/
real-esrgan, E09-portretset) → default-flip + Topaz-unitprijs verifiëren →
models-smoke-assert omzetten. NB: de reapplyAlpha-fix alleen al zou de
haarklacht grotendeels moeten verhelpen — óók op de huidige default.

**Result (deel 2, bakeoff + default — 2026-07-03):** bakeoff gedraaid met
`scripts/upscale-bakeoff.ts`: 4 armen × 5 E09-portretten, live Replicate-runs
door de échte pipeline (bleedFlatten → upscale → reapplyAlpha, directe
lib-calls met eigen token; het HTTP-endpoint zelf zit achter Vercel-
deployment-protection en is codepad-identiek). 20/20 geslaagd (1 google-
timeout, retry OK); throttle 11s conform de Replicate-regel. Sheets + 100%-
crops (donker/licht): **topaz wint** — scherpste mét natuurlijke huidtextuur
en intacte identiteit; google nipt tweede (hardere contrast-look, 1×
50s-timeout); crystal goed maar diffusie-look; real-esrgan óók zonder
face_enhance de gladde verliezer. Haarranden overal schoon op beide
achtergronden — bleed + alpha-fix bevestigd; crystal-unversioned live
bevestigd (41.3 definitief gesloten). Default → `topaz`
(topazlabs/image-upscale, unversioned officieel), models-smoke-assert
omgezet; tsc + beide smokes groen. Preview-deploy avatars-qgghat2yg (en
herdeployed na de flip). Sheets: scratchpad `e41-bakeoff/sheets/`.
**Follow-up Thierry:** Topaz-unitprijs verifiëren op
replicate.com/account/billing (~$0.08/beeld verwacht; 6 runs gedraaid).
**Prod-deploy:** uitgevoerd 2026-07-03 met expliciet akkoord Thierry
(avatars-ja3k8daeg, Ready; api.aaavatar.nl/v1/upscale live geverifieerd
401-zonder-auth) — Boost online draait nu Topaz met de anti-halo-pipeline.

## 41.5 — Twee upscale-tiers: Regular (1 credit) & High quality (3 credits) [INFRA+FEAT]
- status: in_progress
- owner: INFRA+FEAT (2026-07-12, branch v2/e41-41.5)
- team: INFRA+FEAT
- blockedBy: —

Besluit Thierry (2026-07-12, n.a.v. de billing-check in DECISIONS-PENDING): twee
opties i.p.v. één verlieslatende default — **Regular** = `google/upscaler` x2 q100
voor 1 credit ($0,02 kosten ≈ $0,021 opbrengst, break-even) en **High quality** =
`topazlabs/image-upscale` (High Fidelity V2) voor **3 credits** mét een server-side
input-cap van ~6 MP zodat de output ≤24 MP blijft en Topaz vast $0,05/run kost
(~$0,063 opbrengst → ~25% marge).
**Scope:** backend `/v1/upscale` krijgt `quality: "regular"|"high"` (default
regular; dev-`model_override` blijft voorgaan), per-tier credits + de 6 MP-cap
(alleen Topaz-pad, sharp-downscale vóór flatten); app: Boost-dropdown wordt
3 rijen (On device · Online Regular 1 cr · Online High 3 cr), `CreditMeter`
krijgt `upscaleHigh` (3), `BackendClient.upscale` geeft quality door;
StylizeQualityCoordinator-row = Regular.
**DoD:** backend `npx tsc --noEmit` + unit-tests (cap-functie) groen;
build-v2.sh volledig groen; Result-regel. Prod-deploy = expliciete go Thierry.
