# E14 — Monetization 2.0

Team: **FEAT + INFRA**

Pro-model: Starter Free (3 afbeeldingen totaal, lokale features, watermark) vs Pro €12,99/mnd (onbeperkt, alle features, 100 credits/mnd, top-up). Principe: on-device = 0 credits, cloud = credits (1 = lichte call, 2 = generatief). Volledig voorstel in aaavatar-2.0-bouwplan.md §Pro-model.

## 14.1 — Pro-modal conform Figma
- status: ready
- owner: —
- blockedBy: E03.2, E01.5
- DoD: beide targets bouwen, tests groen
- Context: Figma node 4019:953 'Choose your plan'; v1 ProUpgradeSheet-logica via AvatarKit als basis.

Plan-kiezer met Starter/Pro-cards, Monthly/Yearly-toggle (Save 20%), Upgrade to pro-CTA. Bestaat als
design — pixel-volgen.

**Result:** _(invullen bij done)_

## 14.2 — Free-gate: 3 afbeeldingen totaal
- status: backlog
- owner: —
- blockedBy: 14.1
- DoD: beide targets bouwen, tests groen
- Context: v1 FreeTierGate + supabase free_cutouts_used; QuotaBadge uit E03.2.

Importgate op 3 lifetime-afbeeldingen voor Starter; teller zichtbaar in QuotaBadge ('x/3'); bij
overschrijding → pro-modal. Watermark op Starter-export.

**Result:** _(invullen bij done)_

## 14.3 — Credit-metering per feature
- status: backlog
- owner: —
- blockedBy: E03.4, E01.5
- DoD: beide targets bouwen, tests groen
- Context: bouwplan §Pro-model (prijzen per actie); backend credits-administratie bestaat; ProChip uit E03.4. INTERFACE-STORY: CreditMeter-API documenteren in Result.

CreditMeter in AvatarKit: elke cloud-actie meldt z'n kosten (1 of 2 credits) vóór uitvoering via
ProChip, trekt af via bestaande backend, toont op=op-state → top-up. On-device-acties tonen geen
credits.

**Result:** _(invullen bij done)_

## 14.4 — Stripe-prijzen 2.0 [INFRA + actie Thierry]
- status: backlog
- owner: —
- blockedBy: 14.1
- DoD: beide targets bouwen, tests groen
- Context: backend/lib/stripe.ts (PRICE_ID_PRO/_ANNUAL, creditsForTier 200→100 voor 2.0 bepalen).

Nieuwe price-IDs (€12,99/mnd, jaarlijks −20%) in backend-env koppelen; tier-mapping en webhook
ongewijzigd. THIERRY maakt de prijzen aan in het Stripe-dashboard — agent levert de exacte
specificatie en wacht.

**Result:** _(invullen bij done)_

## 14.5 — Top-up-flow
- status: backlog
- owner: —
- blockedBy: 14.3, 14.4
- DoD: beide targets bouwen, tests groen
- Context: v1 ProUpgradeSheet top-up-variant + backend checkout/topup.ts.

Bestaande packs (50/200/750) bereikbaar vanuit op=op-state; alleen voor Pro.

**Result:** _(invullen bij done)_
