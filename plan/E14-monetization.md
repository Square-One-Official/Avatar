# E14 — Monetization 2.0

Team: **FEAT + INFRA**

Pro-model: Starter Free (3 afbeeldingen totaal, lokale features, watermark) vs Pro **€4,99/mnd of €49,90/jr** (onbeperkt, alle features, **200 credits/mnd**, top-up). Principe: on-device = 0 credits, cloud = kosten-proportionele credits (zie 14.3). **Besluit Thierry 2026-06-12: prijs en credits blijven gelijk aan v1 — de €12,99/100 uit het bouwplan §Pro-model was een voorbeeld en is vervallen.**

## 14.1 — Pro-modal conform Figma
- status: ready
- owner: —
- blockedBy: E03.2, E01.5
- DoD: beide targets bouwen, tests groen
- Context: Figma node 4019:953 'Choose your plan'; v1 ProUpgradeSheet-logica via AvatarKit als basis.

Plan-kiezer met Starter/Pro-cards, Monthly/Yearly-toggle, Upgrade to pro-CTA. Bestaat als
design — pixel-volgen, maar met de werkelijke prijzen: **€4,99/mnd, €49,90/jr en 200 credits/mnd**
(besluit Thierry 2026-06-12). Let op: de "Save 20%"-toggle-label uit Figma klopt niet bij €49,90
(dat is −17% / "2 maanden gratis") — toon de werkelijke korting, geen designtekst overnemen die
feitelijk onjuist is.

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
- Context: backend credits-administratie bestaat; ProChip uit E03.4. INTERFACE-STORY: CreditMeter-API documenteren in Result.

CreditMeter in AvatarKit: elke cloud-actie meldt z'n kosten in credits vóór uitvoering via ProChip,
trekt af via bestaande backend, toont op=op-state → top-up. On-device-acties tonen geen credits.
CreditMeter exposeert per actie ook **`requiresCloud`** (voer voor de cloud/AI-glyph uit E03.7).

**Credit-tarieven (besluit Thierry 2026-06-12: kosten-proportioneel, AI-kostenbescherming):**

| Actie | Model (huidig/bakeoff) | Kosten/call | Credits |
|---|---|---|---|
| Magic Cutout | BiRefNet (Replicate, community/per-seconde) | ~$0,002 | **1** |
| Colorize | DeOldify (Replicate) | ~$0,001 | **1** |
| Fill body | FLUX Fill pro (Replicate) | ~$0,05 | **2** |
| Generatieve stijl/kleding/haar — standaardmodel | Nano Banana 2 ($0,067) / GPT Image 2 medium ($0,053) / FLUX.2 edit (vanaf $0,045/MP) | ~$0,05–0,07 | **4** |
| Generatieve stijl/kleding/haar — premiummodel (alleen als E09.1-bakeoff het rechtvaardigt) | Nano Banana Pro | $0,134 (1K/2K) | **5** |

Rekensom (peildatum 12 jun 2026, koers ~€0,93/$): 1 credit kost de gebruiker €4,99/200 =
**€0,025**. Worst case is 200 credits volledig aan 5-credit-acties: 40 × $0,134 = $5,36 ≈ €4,98 —
nét binnen de €4,99-grens (break-even, geen retry-marge: premiummodel dus alléén inzetten waar de
bakeoff het hard maakt). Standaard-generatief: 50 × $0,067 = $3,35 ≈ €3,12. Fill: 100 × $0,05 ≈
€4,65. Lichte calls: 200 × $0,002 ≈ €0,37. Realistische mix zit ruim onder de grens; bij
modelwissel of koersdaling de tabel herijken (secundaire check: het 750-top-up-pack verkoopt
credits voor €0,020/stuk — duurste actie mag ook dáár niet structureel boven uitkomen, vandaar
geen 5-credit-actie als standaardroute). GPT Image 2 op kwaliteit high ($0,211) past in geen
enkel tarief — niet inzetten.

**Result:** _(invullen bij done)_

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
