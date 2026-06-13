
## Boost resolution — credit-tarief (E14.3)
- **Context:** De "Boost resolution"-actie staat in het Edit-paneel maar het tarief is niet in de E14.3-besluit-tabel vastgelegd, en er is nog geen upscale-model gekozen.
- **Aanbeveling (default waarmee gebouwd):** 1 credit (upscale-modellen op Replicate zijn licht, ~$0,002–0,01/call — past ruim binnen netto). Tot een besluit toont de actie de generieke "Pro"-chip i.p.v. een credit-label.
- **Beslissing nodig van Thierry:** model + definitief tarief (verwachting 1). Daarna CreditMeter-case toevoegen en de chip aanzetten.


## Kleding-generatie: route (E10.2)
- **Context:** E10.1 bouwde een kledingmasker (ClothesMaskGenerator) voor een masked FLUX-Fill-route; de E09.1-bakeoff koos echter nano-banana **instruction-edit** (zónder mask) als beste voor kledingwissel (identity-behoud). De E10.2-storytekst noemt nog "FLUX Fill met kledingmasker". Twee onverenigbare routes.
- **Aanbeveling (default):** nano-banana instruction-edit via een productie-`/v1/stylize` (E09.2), prompt "change the upper clothing to <preset/omschrijving>, keep face/hair/pose". De ClothesMaskGenerator blijft beschikbaar als fallback/refinement maar is niet het primaire pad. Reden: de bakeoff testte kleding direct en instruction-edit won; geen mask-plumbing nodig.
- **Beslissing nodig van Thierry:** route bevestigen. Daarna E10.2's generate-actie wiren (nu stub) en E09.2 (Effects/stylize productie) levert het endpoint.
