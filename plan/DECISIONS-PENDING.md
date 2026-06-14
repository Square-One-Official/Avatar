# Geparkeerde besluiten

## Open

### Double-opt-in filtering bij nieuwsbrief-dispatch (E17.6) — VOORSTEL, wacht op Thierry
- **Context:** `newsletter_optins` (sql 014) is een additief opt-in-grootboek. De dispatch filtert
  er nu bewust NIET op, zodat bestaande account-houders (die al opt-in gaven bij registratie) niet
  retroactief uitgesloten raken.
- **Voorstel:** voor puur-marketing-/re-engagement-cohorten de dispatch optioneel laten filteren op
  `confirmed_at IS NOT NULL` (ontgrendel dan ook de `payload_app`-SELECT-grant in sql 014).
  Transactionele/welkom-mails blijven ongefilterd. Te bevestigen door Thierry vóór live.

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

### OTP "token has expired or is invalid" bij sign-in — WACHT-OP-THIERRY (2026-06-14)
- **Symptoom:** e-mail + 6-cijfer-OTP-login geeft direct "Token expired" bij verify, ook met
  snel ingevoerde code.
- **Al gedaan (E18.21):** `AuthService.verifyCode` probeert nu `.email` én valt terug op `.signup`
  (nieuw adres = signup-token). Loste het NIET op.
- **Verdachte (gated, live Supabase-config):**
  1. **E-mailtemplate stuurt een magic-link** naast `{{ .Token }}` → een mailclient/security-scanner
     pre-fetcht de link en verbruikt de single-use token vóórdat de gebruiker de code inttypt →
     "expired/invalid". **Fix:** template zo zetten dat alléén de OTP-code (`{{ .Token }}`) wordt
     gemaild, geen `{{ .ConfirmationURL }}`.
  2. **OTP-expiry te kort** in Auth-instellingen → verhoog naar bv. 3600s.
  3. flowType/PKCE: AuthService gebruikt `.implicit` (correct voor OTP) — waarschijnlijk niet de oorzaak.
- **Te doen door Thierry:** Supabase → Authentication → Email template + OTP-expiry checken; daarna
  in-app opnieuw testen. App-kant (verify + foutweergave als input-error-state) is klaar.

### Phosphor-iconen: SPM-package incompatibel met CLI-DoD (2026-06-14)
- **Probleem:** `phosphor-icons/swift` (2.1.0) bevat een **asset-catalog**. CLI `swift build`/
  `swift test` heeft geen `actool`, dus de resource-bundle-accessor wordt niet gegenereerd →
  `type 'Bundle?' has no member 'module'` in PhosphorSwift.swift. De DoD-stap
  `swift test --package-path AvatarUI` faalt daardoor. Onder xcodebuild (app-target) zou het
  wél bouwen.
- **Interim (gedaan):** `DSIcon`-laag draait op SF Symbols met de bedoelde Phosphor-naam per case
  in commentaar; één plek om later om te zetten.
- **Opties voor Thierry (kies één):**
  1. AvatarUI-unittests vía xcodebuild draaien (scheme/host opzetten) i.p.v. `swift test`, dan kan
     de Phosphor-package mee. Build-v2.sh aanpassen.
  2. Een font-gebaseerde Phosphor-bron gebruiken (geen asset-catalog → CLI-vriendelijk).
  3. Phosphor-SVG's als eigen resources vendoren zonder asset-catalog.
- Tot dan blijft DSIcon op SF Symbols (visueel benaderend, niet 1-op-1 Figma).

### E24.8 — canvas-zoom vs afbeelding-schaling via selectie-handles (2026-06-14)
- **Gevraagd:** scroll/pinch = canvas-zoom (view); de afbeelding zélf schalen via een SELECTIE
  (resize-handles / scale-grip), niet via zoom. Referenties volgen.
- **Waarom geparkeerd:** dit is een eigen interactie-ontwerp: een handle-laag op EditorCanvasView
  (4–8 resize-grips + hit-testing + drag-to-scale, met aspect-lock?), gescheiden van de bestaande
  pan/zoom (E06.4). Te groot/risicovol om in de marathon af te raffelen; vraagt visuele iteratie.
- **Te beslissen door Thierry:** (a) welke handles (hoeken + zijden, of alleen hoeken?), (b)
  aspect-lock standaard?, (c) waar leeft de scale — op `Portrait2.scale` (bestaand) of een aparte
  selectie-transform?, (d) interactie bij meerdere lagen later. Daarna bouw ik het als losse story.
