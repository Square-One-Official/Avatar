# E51 — macOS 26-kansen

Team: **AI + FEAT**

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, dwarsdoorsnede-review).
Backlog/research-epic: geen OS-floor-verhoging (basis blijft macOS 14+), elke
opportuniteit is feature-gated (`#available`/`#if canImport`) met het bestaande
gedrag als fallback voor oudere Macs. De bestaande Apple-Intelligence-tier
(`AIPrivacyTier.appleCloud`, weak-linked ImagePlayground) is een echte integratie,
geen placeholder — dit epic bouwt daarop voort. Kans 51.1 + 51.2 vervangen precies de
twee paden die in de audit braken (cloud-generate-background-decode, on-device-cutout
op non-RGB) door on-device/Apple-routes zonder credits.

---

## 51.1 — ImagePlayground `ImageCreator` als default achtergrond-generatie
- status: backlog
- team: AI + FEAT
- blockedBy: E43 (huidige cloud-pad moet eerst weer werken als fallback)

**Wat:** vandaag loopt achtergrond-generatie via de cloud (`BackendClient.
generateBackground`, 2-3 credits, Vercel/Replicate-roundtrip) of de user-facing
Playground-*sheet*. `ImageCreator` (headless, programmatic) kan vanuit de bestaande
`BackgroundGenerationCatalog`-prompt genereren zonder credits, zonder
netwerk-roundtrip.
**Voorstel:** nieuwe engine-tak naast de backend-call in
`BackgroundGenerationCoordinator.swift`, bridge-uitbreiding in
`ImagePlaygroundBridge.swift`. Gate: `#if canImport(ImagePlayground)` +
`#available(macOS 15.2/26, *)` + `ImagePlaygroundBridge.isAvailable`; cloud blijft
fallback voor oudere Macs of wanneer Playground niets bruikbaars levert.
**DoD:** op een ondersteunde Mac genereert de achtergrond-sheet on-device zonder
credit-afschrijving; op een niet-ondersteunde Mac blijft het cloud-pad ongewijzigd
werken; tests groen; Result-regel.

## 51.2 — Vision tap-to-segment / verbeterde matting als nieuwe engine-variant
- status: backlog
- team: AI
- blockedBy: —

**Wat:** de instance-mask-request levert al per-instance-maskers; macOS 26 heeft
nieuwe matting-revisies en een tap-to-segment-achtige interactie. "Tik op wat
ontbreekt" is bijna gratis bovenop de bestaande maskers, en de nieuwe revisie mat
haar zichtbaar beter.
**Voorstel:** nieuwe engine-variant in `AvatarKit/Engines/`, geregistreerd in
`PipelineRouter` vóór de bestaande Vision v1-engine, achter `#available(macOS 26,
*)` — de fallback-cascade uit de juni-audit maakt dit triviaal. UI-haak aan de
bestaande "Remove background"-chip in `EditColorPanel`.
**DoD:** op macOS 26 gebruikt cutout de nieuwe revisie met zichtbaar betere
haarranden op de bestaande lastige-haar-testset; op oudere macOS ongewijzigd; tests
groen; Result-regel.

## 51.3 — FoundationModels import-pre-check vóór de claim
- status: backlog
- team: AI + FEAT
- blockedBy: E44.2 (claimImport() moet eerst pas ná succes lopen)

**Wat:** `entitlement.claimImport()` verbrandt vandaag een van de 3 gratis imports
vóórdat er ook maar naar de foto gekeken is (zie E02.5/E44.2). Een on-device
kwaliteitscheck kan vooraf waarschuwen: "is dit een portret, staat er een gezicht
op, is de resolutie bruikbaar?".
**Voorstel:** nieuw `Avatar2/Features/Shell/ImportPrecheck.swift`, aangeroepen in
`runCutout` vóór de claim. Gate: `#if canImport(FoundationModels)` +
`#available(macOS 26, *)`; zonder FoundationModels valt hij terug op geen check
(huidig gedrag).
**DoD:** een duidelijk ongeschikte foto (geen gezicht, extreem laag-res) krijgt op
een ondersteunde Mac een waarschuwing vóór de credit/import verbruikt wordt; tests
groen; Result-regel.

## 51.4 — App Intents
- status: backlog
- team: FEAT
- blockedBy: —

**Wat:** nul App Intents vandaag; werkt al vanaf macOS 14, dus geen OS-gate nodig.
**Voorstel:** "Import portrait", "Export as PNG/social size", "Apply style X" als
`AppIntent` in een nieuw `Avatar2/Intents/`-mapje, die alleen `ShellModel`/
`PortraitExporter` aanroepen — geen nieuwe business-logica.
**DoD:** de drie intents zijn zichtbaar en werkend in Shortcuts/Spotlight; tests
groen; Result-regel.
