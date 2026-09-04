# E14 — Monetization 2.0

Team: **FEAT + INFRA**

Pro-model: Starter Free (3 afbeeldingen totaal, lokale features, watermark) vs Pro **€4,99/mnd of €49,90/jr** (onbeperkt, alle features, **200 credits/mnd**, top-up). Principe: on-device = 0 credits, cloud = kosten-proportionele credits (zie 14.3). **Besluit Thierry 2026-06-12: prijs en credits blijven gelijk aan v1 — de €12,99/100 uit het bouwplan §Pro-model was een voorbeeld en is vervallen.**

## 14.1 — Pro-modal conform Figma
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: E03.2, E01.5
- DoD: beide targets bouwen, tests groen
- Context: Figma node 4019:953 'Choose your plan'; v1 ProUpgradeSheet-logica via AvatarKit als basis.

Plan-kiezer met Starter/Pro-cards, Monthly/Yearly-toggle, Upgrade to pro-CTA. Bestaat als
design — pixel-volgen, maar met de werkelijke prijzen: **€4,99/mnd, €49,90/jr en 200 credits/mnd**
(besluit Thierry 2026-06-12). Jaarlabel: **"2 months free"** (klopt exact: €49,90 = 10 × €4,99) —
vervangt de "Save 20%"-tekst; Thierry past Figma hierop aan.

Let op: review-fix **14.6** (authed subscribe-flow i.p.v. subscribeAnonymous voor ingelogde
gebruikers) hoort hierbij — meenemen of eerst doen.

**Plan:**
1. PaywallSheet subscribe-tak herbouwen als de "Choose your plan"-kiezer (frame 4019:953):
   gecentreerde titel, Monthly/Yearly-segmented (Yearly = "2 months free"), twee kaarten
   Starter (Free, feature-list) + Pro (lime rand, "Upgrade"-chip, prijs per interval,
   feature-list, "Upgrade to pro"-CTA). Top-up-tak (actieve Pro) blijft ongewijzigd.
2. Echte prijzen uit ProTier (€4,99/mnd · €49,90/jr · 200 credits) — al correct in E14.4;
   prijs schakelt met het interval.
3. Lokale segmented-pill in de Paywall-feature (geen AvatarUI-wijziging).
4. 14.6 (authed subscribe) wordt apart in de keten gedaan; subscribe gebruikt nu nog de
   anonymous-flow (werkt voor iedereen).

**Result:** PaywallSheet subscribe-tak herbouwd als "Choose your plan"-kiezer (frame 4019:953, breedte 900): gecentreerde titel + ×, Monthly/Yearly-segmented pill (Yearly = "2 months free", lokale control — geen AvatarUI-wijziging), Starter-kaart (Free + 3 images total/Local processing/No bots/Export) en gehighlighte Pro-kaart (lime rand, "Upgrade"-chip, prijs per interval uit ProTier €4,99/mo · €49,90/yr, Unlimited images/All Starter features/All editing features/200 editing credits, "Upgrade to pro"-CTA). Top-up-tak (actieve Pro) ongewijzigd. Default-interval jaar (anker). 14.6 (authed subscribe) volgt apart in de keten; subscribe gebruikt nu de anonymous-flow. DEBUG-haak --show-paywall. Smoke-run (ontgrendeld): 1-op-1 het frame, interval-toggle schakelt de prijs. Beide targets bouwen groen, suite groen.

## 14.2 — Free-gate: 3 afbeeldingen totaal
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: 14.1 (done)
- DoD: beide targets bouwen, tests groen
- Context: v1 FreeTierGate + supabase free_cutouts_used; QuotaBadge uit E03.2.

Importgate op 3 lifetime-afbeeldingen voor Starter; teller zichtbaar in QuotaBadge ('x/3'); bij
overschrijding → pro-modal. Watermark op Starter-export.

**Plan:**
1. Importgate wiren: `ShellModel.runCutout` roept vóór elke import `entitlement.claimImport()`
   aan (atomic server-claim, `users.free_imports_used` + device-counter, source-agnostic — geldt
   óók voor lokale Vision-cutouts). Cap → paywall, import afgebroken.
2. `EntitlementModel.claimImport()`-wrapper: Pro short-circuit; niet-allowed/402 →
   `requestUpgrade()` + false; transportfout blokkeert niet (offline niet vastlopen) → true; bij
   succes `refresh()` zodat de teller klopt.
3. Teller + watermark waren er al: QuotaBadge toont "x/3 left" (ShellTopBar, FreeTier.maxPortraits
   = 3); PortraitExporter.applyWatermark draait al op `!isProActive` (E08.2).

**Result:** Free-gate compleet. Importgate gewired in `ShellModel.runCutout` via nieuwe
`EntitlementModel.claimImport()` (atomic server-claim vóór elke import, source-agnostic; cap →
paywall, geen canvas-wijziging; Pro short-circuit; transport-hik blokkeert niet; succes →
saldo/teller-refresh). QuotaBadge-teller ("x/3 left", FreeTier.maxPortraits = 3) en de
Starter-export-watermark (PortraitExporter.applyWatermark op `!isProActive`) waren al aanwezig
(E03.2/E08.2) en blijven werken. Smoke (plain launch): topbar toont "3/3 left" + Upgrade; happy
path intact. Beide targets bouwen groen, alle suites groen.

## 14.3 — Credit-metering per feature
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: E03.4, E01.5
- DoD: beide targets bouwen, tests groen
- Context: backend credits-administratie bestaat; ProChip uit E03.4. INTERFACE-STORY: CreditMeter-API documenteren in Result.

CreditMeter in AvatarKit: elke cloud-actie meldt z'n kosten in credits vóór uitvoering via ProChip,
trekt af via bestaande backend, toont op=op-state → top-up. On-device-acties tonen geen credits.
CreditMeter exposeert per actie ook **`requiresCloud`** (voer voor de cloud/AI-glyph uit E03.7).

**Credit-tarieven (besluit Thierry 2026-06-12, netto-correctie 2e iteratie: kosten-proportioneel, AI-kostenbescherming):**

| Actie | Model (huidig/bakeoff) | Kosten/call | Credits |
|---|---|---|---|
| Magic Cutout | BiRefNet (Replicate, community/per-seconde) | ~$0,002 | **1** |
| Colorize | DeOldify (Replicate) | ~$0,001 | **1** |
| Fill body | FLUX Fill pro (Replicate) | ~$0,05 | **2** |
| Generatieve stijl/kleding/haar — standaardmodel | Nano Banana 2 ($0,067) / GPT Image 2 medium ($0,053) / FLUX.2 edit (vanaf $0,045/MP) | ~$0,05–0,07 | **4** |
| Generatieve stijl/kleding/haar — premiummodel (alleen als E09.1-bakeoff het rechtvaardigt) | Nano Banana Pro | $0,134 (1K/2K) | **7** |

Rekensom op **netto-omzet** (besluit Thierry: €4,99 incl. 21% BTW en Stripe-fees → ≈ **€3,80
netto**/mnd; peildatum 12 jun 2026, koers ~€0,92/$): 1 credit levert netto €3,80/200 = **€0,019**
op. Worst cases bij 200 credits op één actiesoort:
- Premium-generatief (7 cr): ~28 × $0,134 = $3,75 ≈ **€3,45** ✓ (vandaar 7 i.p.v. 5 — bij 5 was
  het $5,36 ≈ €4,93, ruim boven netto).
- Standaard-generatief (4 cr): 50 × $0,067 = $3,35 ≈ **€3,08** ✓.
- Lichte calls (1 cr): 200 × $0,002 ≈ **€0,37** ✓.
- Fill body (2 cr): 100 × $0,05 = $5,00 ≈ **€4,60** — boven de €3,80 netto (wel onder bruto).
  All-fill is geen realistisch patroon (fill ≈ 1× per portret), dus tarief blijft 2 conform
  besluit; ALS dit knelt is 3 credits de fix — **open punt voor Thierry**.

Bij modelwissel of koersdaling de tabel herijken. Secundaire check: het 750-top-up-pack verkoopt
credits voor €0,020 bruto/stuk — duurste actie mag ook dáár niet structureel boven uitkomen.
GPT Image 2 op kwaliteit high ($0,211) past in geen enkel tarief — niet inzetten.

**Result (incl. CreditMeter-API):** `CreditMeter` (AvatarKit/Backend) is het client-contract voor kosten-display. API: `CreditMeter.Action` (magicCutout/colorize/fillBody/generativeStandard/generativePremium), `credits(for:) -> Int` (1/1/2/4/7, spiegelt de besluit-tabel), `requiresCloud(for:) -> Bool` (voer voor de E03.7-glyph; alle huidige acties cloud), `chipLabel(for:) -> String` ("1 credit"/"N credits"), `canAfford(_:creditsRemaining:)`. Werkelijke aftrek blijft server-side (MODEL_REGISTRY.credits per CloudFeature). EditActionsPanel toont nu echte credit-chips: Colorise 1, retouch-generatief 4, Restore body 2; lokale acties (uitlijnen) geen chip. Backend `MODEL_REGISTRY.fill_body.credits` 1→2 gezet (spiegelt CreditMeter.fillBody) — landt op productie bij de volgende E13.0-port, niet nu. Geparkeerd: "Boost resolution"-tarief (geen model/tarief vastgesteld → DECISIONS-PENDING; toont voorlopig generieke chip, aanbeveling 1). 4 unit-tests groen; models-smoke OK; beide targets bouwen groen; smoke-run: credit-chips in het Edit-paneel.

## 14.4 — Stripe-prijzen 2.0 [INFRA + actie Thierry]
- status: done
- owner: INFRA
- blockedBy: 14.1
- DoD: beide targets bouwen, tests groen
- Context: backend/lib/stripe.ts (PRICE_ID_PRO/_ANNUAL, creditsForTier).

Besluit Thierry 2026-06-12: de bestaande prijzen blijven — €4,99/mnd (`PRICE_ID_PRO`) en €49,90/jr
(`PRICE_ID_PRO_ANNUAL`); de €12,99 uit het bouwplan was een voorbeeld. Geen nieuwe Stripe-prijzen,
geen legacy-mapping, `CREDITS_PER_TIER.pro` blijft 200. Zie `plan/E14.4-stripe-prijzen-spec.md`.

**Result:** Geen dashboard- of backend-wijziging nodig: 2.0 hergebruikt de live v1-prijzen en env-vars één-op-één (checkout, webhook, credits ongewijzigd); spec-document herschreven naar dit besluit; geen codewijziging, dus DoD-builds n.v.t. (plan-only).

## 14.5 — Top-up-flow
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: 14.3, 14.4
- DoD: beide targets bouwen, tests groen
- Context: v1 ProUpgradeSheet top-up-variant + backend checkout/topup.ts.

Bestaande packs (50/200/750) bereikbaar vanuit op=op-state; alleen voor Pro.

**Result:** Top-up-flow compleet (grotendeels al gelegd in E08.3/E14.1, nu geverifieerd + afgerond): PaywallSheet topup-tak toont CreditPack 50 (€1,99) / 200 (€4,99) / 750 (€14,99, "Best value", default-selectie) + "Buy N credits" → EntitlementModel.startTopup() → BackendClient.topup (checkout/topup.ts); Pro-gating via `showsTopup = isProActive`; bereikbaar vanuit de op=op-state (handleOutOfCredits → OutOfCreditsToast → requestUpgrade → paywall toont de topup-variant voor Pro). DEBUG-haak --show-paywall-topup. Smoke-run (ontgrendeld): topup-paywall met de drie packs + Best-value + CTA. Beide targets bouwen groen, suite groen.

## 14.6 — Review-fix: authed subscribe-flow in PaywallSheet
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: —
- DoD: beide targets bouwen, tests groen
- Context: review DS 2026-06-12 op E08.3-code; hoort inhoudelijk bij 14.1 — wie 14.1 oppakt neemt dit mee of doet 14.6 eerst.

PaywallSheet/EntitlementModel start de checkout nu onvoorwaardelijk via
`BackendClient.subscribeAnonymous` (Avatar2/Features/Paywall/EntitlementModel.swift:91), ook
voor ingelogde gebruikers. In 2.0 (e-mail + OTP) is de gebruiker doorgaans ingelogd: anonieme
checkout maakt dan een tweede Stripe-customer op e-mail aan; de webhook reconcilieert dat, maar
dat is een vangnet, geen pad. Fix: bij een ingelogde gebruiker de authed subscribe-flow
(backend `/v1/checkout/subscribe`, gekoppeld aan Supabase user-id) gebruiken; anoniem alleen
voor niet-ingelogde gebruikers. Let op: BackendClient (AvatarKit = INFRA-grens) heeft nog géén
wrapper voor `/v1/checkout/subscribe` — ontbreekt die bij de bouw, dan per boardregel 4 een
INFRA-story toevoegen i.p.v. zelf in AvatarKit bouwen.

**Plan:**
1. De backend-endpoint `/v1/checkout/subscribe` (authed) bestaat al (subscribe.ts, zelfde
   body/response als de anonieme); alleen de client-wrapper ontbrak.
2. `BackendClient.subscribe(interval:)` toegevoegd (authed `request`, vereist token) naast
   `subscribeAnonymous` — kleine AvatarKit-toevoeging (cross-team conform marathonregel; geen
   AvatarUI/E01.11). INFRA-review genoteerd.
3. EntitlementModel.startSubscribe kiest nu: `auth.isSignedIn` → subscribe(); anders
   subscribeAnonymous(). Rest van de checkout-flow ongewijzigd.

**Result:** `BackendClient.subscribe(interval:)` toegevoegd (authed `request`, hit `/v1/checkout/subscribe` — endpoint bestond al in productie) naast `subscribeAnonymous`; EntitlementModel.startSubscribe routeert ingelogde gebruikers (`auth.isSignedIn`) naar de authed flow (gekoppeld aan Supabase user-id, hergebruikt de Stripe-customer → geen dubbele customer), anonieme gebruikers naar de e-mail-flow. Geen UI-wijziging (zelfde paywall) → geen visuele smoke nodig. Kleine AvatarKit-toevoeging (INFRA-review genoteerd); geen backend-deploy nodig. Beide targets bouwen groen, suite groen.

## 14.7 — Stripe-webhook verifiëren + refill-datum-guard
- status: done
- team: INFRA + FEAT
- blockedBy: —
- Result: Root cause gevonden en gefixt (branch v2/e14-15-audit-fixes). **Stripe-bevindingen:**
  het live webhook-endpoint (`we_1TRZdZ…` → avatars-api-five.vercel.app/api/stripe-webhook)
  staat op API-versie **2026-04-22.dahlia** terwijl de handler-code de acacia-shapes verwacht.
  Sinds basil (2025-03-31) zit `current_period_start/end` niet meer top-level op de
  Subscription (alleen op de items) → `new Date(undefined*1000).toISOString()` gooide een
  RangeError → 500 → **failed delivery**. Zo is het `customer.subscription.deleted`-event van
  4 jun (evt_1TeVNmAcH6vt33NABIJ88QlU, pending_webhooks=1 — enige gefaalde delivery) nooit
  geland: de Supabase-rij `sub_1TTGaPAcH6vt33NAFPl7bFgM` zegt nog `active` /
  period_end=2026-06-04 / cancel_at_period_end=false, terwijl Stripe zegt canceled
  (opgezegd 4 mei, geëindigd 4 jun). Vandaar "Refills on 4 Jun 2026". Er is geen betalende
  Pro die maandcredits mist (de enige sub is echt geëindigd), maar de ex-subscriber wordt
  nog als actieve Pro geserveerd. Tweede stille faalweg bevestigd: invoice-lines dragen in
  dahlia `pricing.price_details.price` i.p.v. `price` → tier-null → stille grant-skip.
  **Fixes:** `stripe-webhook.ts` leest nu beide payload-shapes (`subscriptionPeriod()`,
  `invoiceLinePriceId()`), gooit nooit meer op een ontbrekende periode (status-update
  overleeft), en tier-null logt een zoekbare `[ALERT]`-console.error op alle drie de paden.
  Client: `EntitlementModel.upcomingMonthlyResetAt` guard (verleden-datum → "Refills
  monthly with your plan") in SettingsAccountPage + PaywallSheet, en "200" vervangen door
  `model.monthlyQuota`. Tests: 2 nieuwe EntitlementModelTests (verleden/toekomst-datum);
  alles groen (AvatarKit 78, AvatarUI 37, Avatar2 suite, `tsc --noEmit`).
  **Follow-up:** webhook-fix mee in de eerstvolgende prod-deploy (E43-akkoord loopt);
  daarna het 4-jun-deleted-event resenden vanuit het Stripe-dashboard (30-dagen-retentie
  verloopt ±4 jul!) óf de subscriptions-rij handmatig op `canceled` zetten.

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevinding B8).
**Wat:** Settings→Account en de top-up-paywall toonden "Refills on 4 Jun 2026" — een
datum in het **verleden**. Bron: `backend/api/v1/account.ts` spiegelt
`subscriptions.current_period_end` 1-op-1; alleen de Stripe-webhook ververst die
kolom. Twee stille faalwegen gevonden in `stripe-webhook.ts`: (a) `resolvePriceLive`
→ `tier == null` → `upsertSubscription` returnt zonder update én `invoice.paid`
doet `if (!tier) break` → **geen periode-update én geen maandelijkse creditgrant**;
(b) mogelijk falende webhook-deliveries sinds begin juni (te checken in het
Stripe-dashboard). Client toont de datum bovendien ongeguard
(`SettingsAccountPage.swift:102`, `PaywallSheet.swift:114`) en hardcodet "200"
i.p.v. `EntitlementModel.monthlyQuota`.
**Voorstel:** (1) Stripe-delivery-log + de betreffende `subscriptions`-rij checken;
alert toevoegen op tier-null in de webhook; (2) client: datum in het verleden →
terugvallen op "Refills monthly with your plan"; "200" vervangen door
`model.monthlyQuota`.
**DoD:** geen datum in het verleden meer zichtbaar; webhook-tier-null triggert een
zichtbare log/alert; tests groen; Result-regel met de bevindingen uit het
Stripe-dashboard.

## 14.8 — Credits-transparantie: cost-aware gating + uniforme chips (backlog)
- status: backlog
- team: FEAT
- blockedBy: —

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevinding C8).
**Wat:** `PrivacyGate.evaluate` is binair (`isProActive || isDevUnlimited ||
creditsRemaining > 0`) — een Pro met 0 credits of een free user met 1 credit op een
4-credits hair-edit worden beide "allowed" en lopen pas tegen de server-402 aan (na
upload + wachttijd). `CreditMeter.canAfford(_:creditsRemaining:)` bestaat en is
getest maar wordt in `Avatar2/` nergens aangeroepen. Daarnaast zijn de chips
inconsistent: Boost toont hardcoded `"1 credit"` (niet via `CreditMeter.chipLabel`);
Colorise en Restore body tonen alléén een Pro-badge, geen kosten; de
generate-background-prijs is client-hardcoded en intern inconsistent (context
rekent 3 credits voor ultra-wide, de registry zegt 2).
**Voorstel:** `PrivacyGate` cost-aware maken via `feature.creditCost` +
`CreditMeter.canAfford` → direct `needsCredits` i.p.v. een gegarandeerde
server-roundtrip; alle credit-chips via `CreditMeter.chipLabel` genereren; de
background-generate-prijs uit één bron (server-config of `CreditMeter`) trekken.
**DoD:** alle cloud-acties tonen hun kosten via hetzelfde chip-contract vóór
uitvoering; een gebruiker met te weinig credits krijgt de melding vóór de
upload start; tests groen; Result-regel.

## 14.9 — Pro-lijst beheerbaar vanuit de CMS
- status: done
- owner: INFRA (AI-agent)
- blockedBy: —

Vraag van Thierry (2026-08-01): mensen op de Pro-lijst kunnen zetten via de CMS.
**Was:** de enige niet-Stripe-route naar Pro was `DEV_UNLIMITED_EMAILS`, een
komma-gescheiden env-var op het avatars-api-Vercel-project. Wijzigen = redeploy,
geen spoor van wie er is toegevoegd of waarom, en precies één stand (alle
creditcontroles overslaan) — prima voor onze eigen accounts, ongeschikt om
iemand Pro te geven.

**Gebouwd:**
1. **CMS-collectie `pro-access`** (`admin/src/collections/ProAccess.ts`), groep
   "Access". Velden: `email` (uniek, lowercased), `access`, `monthlyCredits`,
   `active`, `expiresAt`, `note`, `grantedAt`. Twee niveaus:
   - `pro` (default) = comped abonnement: alle Pro-gates open, `monthlyCredits`
     (default 200) per kalendermaand, cloud-acties kosten gewoon credits.
   - `unlimited` = het oude env-var-gedrag: geen creditboekhouding + de
     Advanced-modelkiezer (`is_dev_unlimited`, E15.5). Alleen eigen accounts.
2. **Schrijfrechten los van leesrechten.** Nieuwe access-regel `adminSession`
   (`admin/src/lib/access.ts`) weigert API-key-principals. De backend-API-key
   mag de lijst lézen maar er niets aan toevoegen — anders is een lek van die
   key gelijk aan gratis Pro uitdelen.
3. **Backend-resolver** `backend/lib/proAccess.ts`: 60s-cache, concurrent
   refreshes gecollapsed, en bij een CMS-storing tot 10 min de laatste goede
   lijst serveren (daarna dicht — entitlements falen closed).
   `DEV_UNLIMITED_EMAILS` blijft leven als break-glass en levert altijd
   `unlimited`, onafhankelijk van de CMS.
4. **Maandtegoed voor comped Pro** (`ensureCompedCredits`, supabase.ts). Een
   comped account heeft geen Stripe-subscription, dus de webhook grant nooit
   iets — zonder dit zou het tier "pro" tonen en op de eerste cloud-actie 402'en.
   Top-up-semantiek (niet stapelen): eerste call van de maand tilt het saldo
   naar `monthlyCredits`. Idempotent via `ref = comped:<user>:<YYYY-MM>` + de
   partiële unieke index uit sql/018, plus een in-process memo zodat de
   saldocheck één keer per warme instance per maand gebeurt.
5. **Alle callsites om**: de gesynchroniseerde `isDevUnlimitedUser` is weg uit
   `lib/auth.ts` én de twee copy-paste-varianten (`/v1/account`,
   `/v1/checkout/topup`) — één bron. Pro-gates in stylize/custom-effects en de
   cohort-targeting in `/v1/messages` + `/v1/announcements/pending` tellen een
   comped account nu als Pro. Ook `/v1/import-claim`: zonder dat liep een
   comped account tegen de drie-afbeeldingen-importcap aan terwijl de app Pro
   toonde.
6. **`/v1/account`** geeft een comped Pro een echt payload: tier `pro`,
   werkelijk saldo, `monthly_quota = monthlyCredits`, `monthly_reset_at` = de
   1e van de volgende maand UTC. Een echt abonnement wint van een comp.
   Responseshape ongewijzigd; `is_dev_unlimited` is optioneel in de client
   (`EntitlementModels.swift:188`), dus geen app-wijziging nodig.

**Uitrolvolgorde (Thierry):** eerst `backend/sql/018_pro_access.sql` in de
Supabase SQL-editor, dan admin deployen, dan backend. Andersom faalt elke
pro-access-query in Payload en valt de backend terug op alleen de env-var.

**Result:** CMS-collectie `pro-access` + backend-resolver + maandelijkse
comp-grant; `isDevUnlimitedUser` uit drie plaatsen geconsolideerd naar
`proOverrideFor`; `tsc --noEmit` schoon op backend, admin `next build` groen
(4 pre-existing tsc-errors ongewijzigd), Avatar2-target bouwt (geen Swift
geraakt). Niet gedaan: prod-uitrol — wacht op de SQL-migratie van Thierry.

## 14.10 — Drop-import boven de Starter-cap: uitleggen, deels importeren, hervatten
- status: done
- owner: FEAT (AI-agent)
- blockedBy: —
- DoD: beide targets bouwen, tests groen
- branch: `v2/e14-14.10`

Melding Thierry 2026-09-02: uitgelogd 14 beelden in een map gedropt → de tegels
flitsten kort, de "Choose your plan"-paywall opende, en na het wegklikken waren
alle beelden weg — zonder één woord uitleg. Sidebar zei ondertussen "3 left of 3".

**Oorzaak:** de batch-import (`ShellModel.importImages`) zette alle tegels
optimistisch neer en deed daarna pas per beeld de server-claim; de eerste 402
veegde alle wachtende tegels in één frame weg (`processLibraryImport`). Het
single-pad (`runCutout`) claimt wél vóór het canvas aanraakt — E14.2 heeft
alleen dat pad gewired. De paywall kende geen reden; er was geen toast en geen
deel-import.

**Besluiten Thierry (2026-09-02):** deels passend → importeer wat past + toast
met Upgrade-knop (geen gedwongen paywall); paywall door geweigerde drop krijgt
een contextregel (**bewuste afwijking van Figma-frame 4019:953**, dat kent geen
contextregel); gedropte set bewaren en hervatten na een geslaagde upgrade,
sluiten zonder upgrade → korte toast.

**Plan:**
1. `EntitlementModel.remainingImportCapacity()` — pre-flight (Pro/onbekend = nil,
   anders `freeImportsRemaining`, laadt het account één keer na). `claimImport(presentPaywall:reason:)`,
   `requestUpgrade(reason:)` + `UpgradeReason.importCapReached(dropped:capacity)` →
   `upgradeReasonCopy`; reden wist zichzelf bij sluiten. `InfoToast.action` (DSToast had de
   actie-rij al, E50.3). `paywallClosedForCheckout` zodat sluiten-voor-Stripe ≠ afzien.
2. `ShellModel.importImages(_:into:)`: niets past → geen tegel, set wacht (`pendingGatedImport`),
   paywall met reden; deel past → alleen dat deel krijgt tegels, rest wacht, aan het eind
   "X of N images imported"-toast met Upgrade; server weigert toch (stale teller) → wachtrij
   naar de pending set, niets geland → paywall. `resumePendingGatedImport()` (Pro geworden →
   import in de oorspronkelijke map), `discardPendingGatedImport()` (paywall afgewezen →
   "N images weren't imported"). Single-pad geeft `dropped: 1` mee voor de contextregel.
3. `PaywallSheet.planChooser`: contextregel onder de titel als `upgradeReasonCopy != nil`.
4. `ShellView` `GatedImportHooks` (ViewModifier): Pro → hervatten; paywall dicht zonder Pro en
   niet voor checkout → vervallen; `didBecomeActive` → account nalezen zolang er iets wacht.
5. Tests: `testBatchImportStoptOpDeCapZonderRestanten` vervangen door vijf E14.10-tests
   (geen tegel + wacht, deels + toast + actie, stale teller, hervatten in de map, vervallen met
   toast) en vier `EntitlementModelTests` (presentPaywall:false, reden/copy/wissen, capaciteit,
   toast-actie).

**Afhankelijkheid:** 14.11. Zolang `/v1/account` uitgelogd "3 over" zegt terwijl de claim
weigert, loopt een uitgelogde drop via het stale-pad: max. 3 tegels flitsen alsnog, daarna
paywall met uitleg en de set wacht. Correct en uitgelegd, maar pas zonder flits met 14.11.

**Result (2026-09-02):** Batch-import peilt eerst de Starter-cap (`EntitlementModel.remainingImportCapacity`)
en zet alleen tegels neer voor wat past; niets past → geen tegel, paywall met contextregel
("You dropped 14 images, but your 3 free images are used up…"), set wacht; deel past → dat deel
landt, daarna toast "X of N images imported" met Upgrade-knop; server weigert toch → wachtrij
naar de pending set, paywall met reden. Pro geworden → hervatten in de oorspronkelijke map
(`didBecomeActive` leest het account na zolang er iets wacht); paywall afgewezen → "N images
weren't imported"-toast; sluiten-voor-Stripe telt niet als afwijzen. Single-pad geeft de reden
óók mee. Contextregel = gedocumenteerde Figma-afwijking. Tests: 5 nieuwe ShellModel-tests
(vervangen `testBatchImportStoptOpDeCapZonderRestanten`), 4 nieuwe EntitlementModel-tests;
`testBatchImportTegelsVolgenDeLens` gehard met `context.save()` (eenmalige SwiftData-fatal op
een temporary folder-identifier, pre-existing pad). Avatar én Avatar2 bouwen groen, volledige
Avatar2-suite groen; AvatarKit/AvatarUI ongewijzigd (geen `swift test` nodig). Handmatige
smoke op een device met opgebruikte teller: Thierry. Open: 14.11 (INFRA).

## 14.11 — `/v1/account` spiegelt de device-teller [INFRA]
- status: done
- owner: INFRA (AI-agent, op verzoek Thierry 2026-09-02)
- blockedBy: —
- DoD: `tsc --noEmit` schoon, backend-test, prod-deploy via E43-pad
- branch: `v2/e14-14.10` (samen met 14.10)

**Wat:** `backend/api/v1/account.ts` stuurt op het pure-anonieme pad hardcoded
`free_imports_remaining: FREE_IMPORTS_ALLOWANCE` en op het ingelogde free-pad alleen
`users.free_imports_used`. `/v1/import-claim` weigert op `max(user, device)`
(`tryConsumeFreeImport`). Gevolg: sidebar "3 left of 3 images" naast een 402, en de
E14.10-pre-flight denkt dat er ruimte is (stale-pad, flits van max. 3 tegels).
**Voorstel:** read-only helper `freeImportsUsedForDevice(fingerprint)` in `backend/lib/supabase.ts`
(naast `freeImportsUsedForUser`, `device_imports.free_imports_used`), en op beide free-paden
`free_imports_used = max(userUsed, deviceUsed)`. Zelfde semantiek als de claim; geen
schema-wijziging. Anonieme pad: fingerprint komt al uit `readDeviceFingerprint`.
**DoD:** een device op de cap ziet uitgelogd én ingelogd "0 left of 3"; backend-test op
beide paden; Result-regel.

**Result (2026-09-02):** `freeImportsUsedForDevice(fingerprint)` toegevoegd in
`backend/lib/supabase.ts` (read-only op `device_imports`, null-fingerprint → 0) en pure
helper `freeImportCounters(user, device, allowance)` in nieuw `backend/lib/freeImports.ts`
(max(user, device), geklemd op 0..allowance). `api/v1/account.ts` gebruikt die op het
ingelogde free-pad (incl. comped-Pro-payload) én op het pure-anonieme pad, dat voorheen
hardcoded `free_imports_remaining: 3` stuurde; fingerprint wordt nu éénmaal bovenin gelezen
(`readDeviceFingerprint`, soft). Responseshape ongewijzigd → geen app-wijziging. 5 node:test-
tests (`npx tsx --test backend/tests/free-imports.test.ts`), `tsc --noEmit` schoon,
billing-tests ongewijzigd groen. **Prod-deploy gedaan (2026-09-02 22:14):** avatars-api via
`vercel --prod` vanaf de repo-root (dpl_DzqMkM2AELghisbGH7JUpmt8PRJf), alias `api.aaavatar.nl`
verwijst ernaar; anonieme `/v1/account` levert de device-teller live.


## 14.12 — Top-up-credits overleven de maandelijkse renewal (two-bucket `current_credits`) [INFRA]
- status: done
- owner: INFRA (AI-agent, audit 2026-09-04)
- blockedBy: —
- DoD: migratie met ingebouwde self-check, `tsc --noEmit` schoon, backend-tests groen, Result-regel; **sql/022 draait Thierry zelf** in de Supabase SQL-editor
- branch: `v2/e14-14.12`

**Wat:** `public.current_credits()` (001, herschreven in 009) telde alleen ledger-rijen met
`created_at >= subscriptions.current_period_start` van de laatste actieve subscription.
Gevolgen: (1) onbestede maandcredits vervallen bij renewal — bedoeld ("refills to 200");
(2) een **top-up-pack gekocht vóór de renewal verviel ook**, want dat is gewoon een oudere
ledger-rij — in tegenspraak met de client-copy ("Credits never expire and stack with your
monthly credits", `SettingsBillingPage`/`BillingCopy`/`CreditPack`-doc-comment); (3) jaar-
abonnees hadden een 12-maands-venster, dus daar stapelden cron-tranches en top-ups wél;
(4) gebruikers zónder actieve sub telden hun hele historie, inclusief élke oude maandgrant.

**Besluit (optie a — bevestigd door Thierry 2026-09-04):**
de maandgrant refillt (onbestede maandcredits vervallen bij de volgende `period_renewal`),
top-ups vervallen nooit, spends trekken eerst van de maandbucket en dan van de top-up-bucket.
Optie (b) alles rolt over en (c) huidige gedrag + copy aanpassen zijn afgewezen omdat de
website-FAQ-notitie (2026-09-04) het huidige gedrag al als "fix pending" bestempelt en de
Settings-copy/`CreditPack` al (a) beloven. Jaar-abonnees: ongewijzigd — `:0`-tranche reset,
`:1`..`:11` stapelen binnen het jaar, de volgende `:0` reset (bewuste keuze, geen gedrags-
wijziging voor bestaande jaarklanten; "maandelijks vervallen ook voor jaar" is een apart besluit).

**Result (2026-09-04):** `backend/sql/022_credit_buckets.sql`: pure fold
`credit_bucket_fold(int[], text[], text[]) → (monthly, topup)` + `credit_buckets(uuid)` +
`current_credits(uuid) = monthly + topup`; ledger-only (leest `subscriptions` niet meer, dus
audit MEDIUM #18 en het dunning-gat verdwijnen als klasse); `topup_pack` → top-up-bucket,
`period_renewal` zonder `:N`-suffix → maandbucket **=** delta (reset), overige positieve rijen
(`:N`-tranches, `comped_pro`, `*_refund`, `initial_grant`) → maandbucket **+=** delta, spends
eerst maand dan top-up (top-up gefloord op 0, zodat legacy-overspends van lapsed users onder het
oude venster vergeven worden i.p.v. als schuld meegenomen). `search_path = ''` op alle drie.
`try_spend_credits`/`refund_credit_spend` (020) en `ensureCompedCredits` roepen alleen
`current_credits()` aan → geen TypeScript-logica gewijzigd (alleen doc-comments in
`lib/supabase.ts`, `stripe-webhook.ts`, `cron/grant-yearly-credits.ts` die de ref-conventie
`:N` nu als contract markeren). Ingebouwde `do $$`-self-check (9 scenario's) breekt de migratie
af bij afwijkende semantiek; sectie 3 = pre-flight-diff-query (oud vs nieuw saldo per user)
om **tussen** sectie 1 en 2 te draaien. Geverifieerd op een echte Postgres 18 (embedded-postgres
in de scratchpad, 001→002→009→020→022): maandklant met top-up 50 vóór renewal oud 190 → nieuw
240; lapsed klant oud 380 (opgeblazen) → nieuw 230 (restant laatste periode + top-up); jaar 500
→ 500; comped 200 → 200; `try_spend_credits` trekt maand-eerst (210 van 190+50 → 0/30), weigert
overspend, refund idempotent; onbekende user → 0; pre-flight-query syntactisch ok. `tsc --noEmit`
schoon, `npm test` groen. Client-copy hoeft niet te wijzigen (beloofde al (a)). Optie (a)
bevestigd door Thierry 2026-09-04; v2-main gepusht. **Open voor Thierry:** (1) sql/022 draaien
(sectie 1 → pre-flight → sectie 2), (2) daarna de website-FAQ-regel "Credits at renewal — fix
pending" herschrijven naar "top-ups never expire, monthly credits refill". Geen backend-deploy
nodig: de functie leeft in Postgres.
