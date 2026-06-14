# Geparkeerde besluiten

## Open

_(geen)_

## Beslist

### Upscale-model voor "Boost resolution" (E10.3) — BESLIST 2026-06-14
- **Besluit:** **Real-ESRGAN** (`nightmareai/real-esrgan`, gepind op versie) als default-upscaler,
  scale 2. Robuust en goedkoop (~$0,002–0,005/call, ruim binnen het 1-credit-tarief). Clarity
  blijft een latere kwaliteits-optie indien gewenst.
- **Verwerkt (E10.3):** `upscale` als CloudFeature in MODEL_REGISTRY (credits 1); `/v1/upscale`
  (credit-gate zoals colorize, flatten→real-esrgan→reapplyAlpha herschaalt alfa naar 2×);
  `BackendClient.upscale`; "Boost resolution"-actie in EditActionsPanel gewired (→ canvas+cutout,
  undo, 402→paywall). Backend = port-only → preview-test; kostenbevestiging op de Replicate-
  modelpagina vóór productie. Bij 404 op de gepinde versie: herpinnen.

### Boost resolution — credit-tarief (E14.3) — BESLIST 2026-06-13
- **Besluit (Thierry):** **1 credit** (upscale = lichte cloud-call). Verwerkt: `CreditMeter.upscale` (1 credit) toegevoegd; de "Boost resolution"-actie toont nu de credit-chip i.p.v. de generieke Pro-chip.
- **Restpunt → eigen story:** de upscale-MODELKEUZE is nog open → **E10.3 (AI, AI-spike, backlog)** — geen blocker.

### Kleding-generatie: route (E10.2 / E09.2) — BESLIST 2026-06-13
- **Besluit (Thierry):** nano-banana **instruction-edit** is het PRIMAIRE pad (prompt: "change the upper clothing to <preset>, keep face/hair/pose"). **Acceptatiecriterium (hard):** alléén de kleding wijzigt — gezicht/haar/pose/achtergrond pixel-identiek. ClothesMaskGenerator (E10.1) + FLUX Fill blijft de precisie-**fallback** voor gevallen waar instruction-edit buiten de kraag kleurt. E09.2 levert het productie-`/v1/stylize`-endpoint; E10.2 wiren zodra dat er is.
