# Go/no-go — Aaavatar 2.0 GTM-cut (E13.3)

Status per **2026-08-16**. ✅ = geverifieerd · ⬜ = open (Thierry-gated) ·
**—** = buiten GTM-scope (feature-flag).

**Regel:** alles wat ⬜ staat is een bewust besluit — óf doen, óf expliciet
accepteren als launch-risico. Feature-flagged werk blokkeert de launch niet.

GTM-cut (`Avatar2/AppFeatureFlags.swift`): Face, custom Create, AI Generate
Background, Boost Online (Topaz) en Banners staan UIT. Effects blijft AAN.
Social Preview mag nog de matched portrait-background cover exporteren.

## 1. Build & tests — ⬜ Mac

- ✅ GTM-flags fail-closed + toolbar verbergt Face (`EditorToolTests`).
- ✅ `scripts/release-v2.sh --check` (versielijnen + appcast lockstep).
- ⬜ `scripts/build-v2.sh` op een Mac (deze cloud-agent heeft geen Xcode).

## 2. Flows compleet — ⬜ Mac-oogtest

Code-paden voor onboarding, shell, editor (Enhance / Effects / Hair /
Clothing / Background), paywall en settings staan op v2-main. Live pass op
een **signed Release-build**:

- Splash → email OTP → Home; wrong/expired OTP; continue without account.
- Import; Free 4e import → paywall; Home Recent/Earlier.
- Toolbar: Enhance · Effects · Hair · Clothing — **geen Face**.
- Effects (9 live CMS-stijlen), Clothing (alleen kleding wijzigt), Hair.
- Background: color/gradient/gallery/upload — geen Generate-tab.
- Boost: 1-credit cloud-upscale op deze tree (geen Topaz-dropdown).
- Export: Free watermark / Pro schoon; Share-picker blijft.
- Flag hygiene: geen Face, Create, Generate Background, Banners, Boost Online.

## 3. Bakeoff / flagged features — **buiten GTM**

- **—** E32.0 face-bakeoff (Face is flagged off).
- **—** Custom effects Create, AI Generate Background, Boost Online, Banners.

## 4. Update-kanaal (13.1) — ✅ API / ⬜ eerste signed beta

- ✅ Prod `GET https://api.aaavatar.nl/appcast-v2.xml` → **200**, leeg `<channel>` (2026-08-16).
- ✅ Prod `GET https://api.aaavatar.nl/appcast.xml` → **200**, v1 1.2.1/18.
- ✅ Website `releases/latest/download/Aaavatar.dmg` → 302 naar **v1.2.1** (niet Aaavatar-2).
- ✅ Avatar2 SUFeedURL = appcast-v2; versielijn 2.0.0 / build 100; `release-v2.sh` publiceert als **prerelease**.
- ⬜ Eerste beta: `./scripts/release-v2.sh 2.0.0 101` op de Mac (signing/notarisatie), appcast committen, backend-deploy, daarna 102 + Sparkle-e2e. v1-feed ongemoeid.

Bron van appcast-v2 stond niet in GitHub `main` terwijl prod hem al serveerde — deze branch zet de files in git zodat een volgende Vercel-deploy het kanaal niet laat vallen.

## 5. Migratiepad (13.2) — ⬜

v1-zip-import (`V1LibraryImporter`) staat nog niet op deze GitHub-v2-main.
Live e2e met een echte v1-bibliotheek blijft gated.

## 6. Stripe-identiteit & betalen — ✅ API-gates / ⬜ live Checkout

API (2026-08-16, geen Checkout-sessies aangemaakt):

- ✅ `POST /v1/checkout/subscribe` zonder auth → 401
- ✅ `POST /v1/checkout/topup` zonder auth → 401
- ✅ `POST /v1/checkout/subscribe-anonymous` zonder fingerprint → 400 `missing_device_fingerprint`
- ✅ `POST /v1/auth/send-recovery-email` invalid → 400 `invalid_email`; unknown well-formed → 200 `{sent:true}` (anti-enumeratie)
- ✅ `GET /v1/account` anoniem → free quota, `free_imports_remaining: 3`

⬜ Live (Thierry, Stripe Dashboard + echte test-inbox):

| # | Path | Expect |
|---|---|---|
| P1 | Free, signed out → Yearly Checkout | `subscribe-anonymous`; `aaavatar://stripe-return` → Pro, 200 credits |
| P2 | Monthly | €4,99/mo |
| P3 | Cancel | `aaavatar://stripe-cancel`; blijft Free |
| P4 | Signed-in Free → Upgrade | `/v1/checkout/subscribe`; geen tweede Stripe-customer |
| P5 | Pro 402 | top-up paywall, niet subscribe |
| P6 | Top-up 50/200/750 | saldo + webhook |
| P7 | Manage subscription | Customer Portal + return URL |
| P8 | Non-Stripe email vs Stripe email | Free vs `tier: pro` |
| P9 | Webhook delivery-log | zero failures |
| P10 | URL-scheme | 2.0 is de `aaavatar://`-handler op de test-Mac |

## 7. Backend & productie-surface — ✅

`scripts/prod-gtm-smoke.sh` 2026-08-16:

- ✅ `/v1/effects` → 9 stijlen (balloon…urban-chic, orders 10–18); oude clay/wood/3d/scribble niet live
- ✅ `/v1/feature-flags` 200 (CMS `face_enabled: true` is OK: compile-time flag houdt Face weg)
- ✅ stylize / colorize / fill-body / upscale zonder auth → 401
- ✅ import-claim zonder fingerprint → 400
- ✅ aaavatar.nl 200; admin `/admin` 307 (login)

**—** custom-effects / generate-background / face_preset: endpoints mogen 401 zijn; UI is hidden.

## 8. Feature-flags & vangnetten — ✅ code

- ✅ `AppFeatureFlags` fail-closed in Release; DEBUG launch-args only.
- ✅ Face-capsule gefilterd in editor + board toolbar.

## 9. Assets — ✅ geaccepteerd risico

Ship de beta **met de vijf geregistreerde placeholders** ([ASSETS.md](ASSETS.md)).
Geen stille promotie tot definitief; batch later. Newsletter double-opt-in
(E17.6) blijft geparkeerd tot de eerste marketing-dispatch.

## Kort: wat nog ⬜ is vóór "go"

1. Port appcast-v2-bron naar `main` + Vercel (prod serveert hem al; git moet meekomen).
2. `release-v2.sh 2.0.0 101` daarna 102 + Sparkle-e2e (Mac).
3. Signed-build flow-pass (3a) + Stripe live matrix (3b) + edge cases (3c).
4. v1-zip import wanneer 13.2 op deze tree landt — of accepteren als launch-risico.
