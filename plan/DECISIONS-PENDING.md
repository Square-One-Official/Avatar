# Geparkeerde besluiten

## Open

### Upscale-model voor "Boost resolution" (E10.3, AI-spike) — AANBEVELING, wacht op AI/Thierry
- **Status:** E10.3 is AI-territory (model-spike) en als enige keten-item open gelaten tijdens de
  FEAT-marathon — de FEAT-keten (E09.2/E11.x/E12.x/E10.4/E15.x) is verder af.
- **Wat al vastligt:** tarief = 1 credit (CreditMeter.upscale, live); de "Boost resolution"-actie
  staat als gegate stub in EditActionsPanel (handler nil) klaar om gewired te worden.
- **Aanbeveling (te bevestigen door AI-spike):** `nightmareai/real-esrgan` (Real-ESRGAN, 4×) als
  default — robuust, goedkoop (~$0,002–0,005/call, ruim binnen 1 credit), face-enhance-optie. Als
  hogere kwaliteit gewenst is: `philz1337x/clarity-upscaler` (duurder/trager, ~$0,01+). Bevestig
  kosten/call op Replicate, registreer in MODEL_REGISTRY (nieuwe feature `upscale`), bouw
  `/v1/upscale` (credit-gate zoals colorize) + `BackendClient.upscale` + wire de actie.
- **Waarom niet door FEAT gedaan:** modelkeuze + kostenbevestiging is een AI/infra-spike, geen
  FEAT-UI-werk; niet gokken conform de marathon-regels.

## Beslist

### Boost resolution — credit-tarief (E14.3) — BESLIST 2026-06-13
- **Besluit (Thierry):** **1 credit** (upscale = lichte cloud-call). Verwerkt: `CreditMeter.upscale` (1 credit) toegevoegd; de "Boost resolution"-actie toont nu de credit-chip i.p.v. de generieke Pro-chip.
- **Restpunt → eigen story:** de upscale-MODELKEUZE is nog open → **E10.3 (AI, AI-spike, backlog)** — geen blocker.

### Kleding-generatie: route (E10.2 / E09.2) — BESLIST 2026-06-13
- **Besluit (Thierry):** nano-banana **instruction-edit** is het PRIMAIRE pad (prompt: "change the upper clothing to <preset>, keep face/hair/pose"). **Acceptatiecriterium (hard):** alléén de kleding wijzigt — gezicht/haar/pose/achtergrond pixel-identiek. ClothesMaskGenerator (E10.1) + FLUX Fill blijft de precisie-**fallback** voor gevallen waar instruction-edit buiten de kraag kleurt. E09.2 levert het productie-`/v1/stylize`-endpoint; E10.2 wiren zodra dat er is.
