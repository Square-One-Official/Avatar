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
- status: backlog
- owner: —
- team: FEAT
- blockedBy: 39.1, 37.2

- Banners-empty-state (E36.2) + home-presetrij (E36.3) laden `bannerPresets()` (session-cache +
  lokale fallback, spiegelt `EffectsModel.loadEffects()` + thumbnail-prefetch).
- Klik op een preset → opent de **Banner Studio** (E37.2) met de preset-`config` ingeladen als
  start-`BannerDoc` (lagen/fill/tekst/shaders). Bewerken vanaf daar is gewoon de editor.
- Soft-fail: CMS down → fallback-presets, geen lege/kapotte UI.
- DoD: beide targets bouwen, tests groen, Result-regel.
