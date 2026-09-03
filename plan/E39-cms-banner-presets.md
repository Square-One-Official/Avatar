# E39 — CMS banner-presets

Team: **INFRA** (Payload-collectie + endpoint + AvatarKit-model/-client) · **FEAT** (consumptie in
empty-state/home/Studio)

Voortgekomen uit feedback (Thierry, 2026-06-26): de Banners-empty-state toont "een aantal presets
die we zelf via het CMS invullen". Volgt exact het bestaande CMS-patroon (Payload-collectie →
genormaliseerd `/v1/*`-endpoint → getypeerd AvatarKit-model → soft-fail-fallback), net als
`Effects`/`RemoteEffect`.

---

## 39.1 — Payload-collectie + endpoint + AvatarKit-model/-client
- status: done
- owner: INFRA (2026-06-26)
- team: INFRA
- Result: CMS-pad voor banner-presets compleet, exact gespiegeld op `Effects`/`RemoteEffect`.
  Backend (port-only, niet door build-v2.sh gebouwd — preview-verificatie volgt): nieuwe
  Payload-collectie `admin/src/collections/BannerPresets.ts` (slug `banner-presets`; velden
  key·label·category(select)·thumbnail(upload→media)·config(textarea)·order·active; `auditHooks`;
  read voor user/bearer, mutatie admin-only) + geregistreerd in `admin/src/payload.config.ts`
  (import + collections-array). `backend/lib/payload.ts`: `PayloadBannerPreset`-type +
  `fetchActiveBannerPresets()` (60s-cache, `where[active]=true`, `sort=order`, `depth=1` voor
  thumbnail-url) + `normalizeBannerPreset()` (skip zonder key+config). `backend/api/v1/banner-presets.ts`:
  GET-handler, 405 op andere methods, snake_case-map (`thumbnail_url`), soft-fail →
  `{banner_presets:[]}`. Route loopt via de bestaande `/v1/(.*)`-wildcard-rewrite (geen
  vercel.json-functions-entry nodig — net als `effects`). AvatarKit: `RemoteBannerPreset`
  (Decodable/Sendable, custom init met thumbnailUrl-String→URL + lege-config→nil-guards) +
  `BackendClient.bannerPresets()` via `requestAllowingAnonymous`; envelope-key `banner_presets`
  → `bannerPresets` onder `.convertFromSnakeCase`. DoD groen: beide targets bouwen, alle
  AvatarKit/AvatarUI-tests groen (build-v2.sh exit 0).
- Result (afronding 2026-07-02, branch `v2/e39-1-e40-1`): de uitgestelde preview-/prod-verificatie
  is gedaan: `GET https://api.aaavatar.nl/v1/banner-presets` → 200 `{"banner_presets":[]}` —
  geldige envelope; lijst is leeg totdat Thierry presets seedt (hetzelfde Payload-fetchpad
  serveert `/v1/effects` mét content, dus de CMS-koppeling werkt). Ontbrekende testdekking
  aangevuld: 3 fixture-decode-tests in
  [BackendClientDecodeTests](../AvatarKit/Tests/AvatarKitTests/BackendClientDecodeTests.swift)
  (E47.1-patroon, door de echte request-pijplijn): backend-vorm 1:1 uit `banner-presets.ts`,
  lenient defaults (label←key, lege category→"default", lege thumbnail/config→nil, order→0) en
  het lege-lijst-soft-fail-pad. `npx tsc --noEmit` groen in `backend/` én `admin/` (geen
  TS-wijzigingen nodig); AvatarKit-suite groen. Geen deploy gedaan — endpoint draait al op prod.

Backend (`admin/` + `backend/`):
- `admin/src/collections/BannerPresets.ts` (slug `banner-presets`): velden `key` (uniek, =
  cache-key), `label`, `category` (select), `thumbnail` (upload→media), `config` (textarea =
  JSON-geserialiseerde `BannerDoc`-laagstack/preset-spec), `order`, `active`; admin-only mutatie,
  read voor bearer/API-key; `auditHooks` zoals `Effects`. Registreer in
  `admin/src/payload.config.ts`.
- `backend/lib/payload.ts`: `fetchActiveBannerPresets()` met 60s-cache +
  `normalizeBannerPreset()` (skip zonder `key`); `backend/api/v1/banner-presets.ts` GET-handler
  (soft-fail → `{presets:[]}`); registreer route in `vercel.json`.
- AvatarKit: `RemoteBannerPreset` (Decodable/Sendable: key/label/category/thumbnailUrl/config/
  order) + `BackendClient.bannerPresets()` (`requestAllowingAnonymous("/v1/banner-presets")`).
- DoD: beide targets bouwen, AvatarKit-tests groen, port-only backend → preview-test van het
  endpoint, Result-regel.

## 39.2 — Consumptie: empty-state + home + "start from preset"
- status: done
- owner: FEAT (2026-06-26)
- team: FEAT
- blockedBy: 39.1, 37.2
- Result: CMS-presets nu live in de empty-state én op home, gespiegeld op
  `EffectsModel.loadEffects()`. Nieuw `BannerPresetsModel` (@Observable): sessie-cache (gedeeld,
  statisch) + lokale `BannerPresetItem.fallback` (6 mesh/solid-presets met labels) zodat de UI
  nooit leeg/kapot is; `load()` haalt `backend.bannerPresets()`, decodeert elke opake
  `config`-JSON → `BannerLayers` (per-preset skip i.p.v. hele-lijst-fail bij corrupte config),
  soft-fail behoudt fallback; thumbnail-prefetch via gedeelde `NSCache` + `thumbnailVersion`-bump
  (achtergrond-`URLSession`, off-main). `BannersGalleryView` krijgt `entitlement` + bouwt het
  model in `init`, `.task { load() }`, en `BannersEmptyState` toont nu CMS/fallback-presets
  (thumbnail als gecachet, anders fill-preview) met label; klik → `makeBanner(from:)` opent de
  Studio voorgeladen. `HomeView` idem: model in `init`, `.task` op de overview, en de lege
  Banners-sectie toont nu een maak-tegel + horizontale preset-rij (`homePresetCard`) i.p.v. enkel
  de dashed-knop; klik maakt een `BannerDoc` en opent de Studio. `ShellView` reikt `entitlement`
  door aan de gallery. DoD groen: Avatar2 + AvatarKit/AvatarUI-tests groen (build-v2.sh "alles
  groen"; enkel benign CoreData NSXPCConnection-testruis). Eerdere clean-build ving een
  `thumbnailURL`↔`thumbnailUrl`-casing-typo die incrementeel was gemist — gefixt.

- Banners-empty-state (E36.2) + home-presetrij (E36.3) laden `bannerPresets()` (session-cache +
  lokale fallback, spiegelt `EffectsModel.loadEffects()` + thumbnail-prefetch).
- Klik op een preset → opent de **Banner Studio** (E37.2) met de preset-`config` ingeladen als
  start-`BannerDoc` (lagen/fill/tekst/shaders). Bewerken vanaf daar is gewoon de editor.
- Soft-fail: CMS down → fallback-presets, geen lege/kapotte UI.
- DoD: beide targets bouwen, tests groen, Result-regel.
