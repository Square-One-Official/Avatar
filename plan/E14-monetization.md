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
- status: backlog
- owner: —
- blockedBy: 14.1
- DoD: beide targets bouwen, tests groen
- Context: v1 FreeTierGate + supabase free_cutouts_used; QuotaBadge uit E03.2.

Importgate op 3 lifetime-afbeeldingen voor Starter; teller zichtbaar in QuotaBadge ('x/3'); bij
overschrijding → pro-modal. Watermark op Starter-export.

**Result:** _(invullen bij done)_

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
- status: backlog
- owner: —
- blockedBy: 14.3, 14.4
- DoD: beide targets bouwen, tests groen
- Context: v1 ProUpgradeSheet top-up-variant + backend checkout/topup.ts.

Bestaande packs (50/200/750) bereikbaar vanuit op=op-state; alleen voor Pro.

**Result:** _(invullen bij done)_

## 14.6 — Review-fix: authed subscribe-flow in PaywallSheet
- status: ready
- owner: —
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

**Result:** _(invullen bij done)_
