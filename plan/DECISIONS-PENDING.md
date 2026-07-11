# Geparkeerde besluiten

## Open

### Frame-vorm: cirkel als DEFAULT-merkvorm (E24.16) — BEVESTIGEN, wacht op Thierry
- **Context:** 24.16 maakt de frame-vorm per-portret kiesbaar (Frame ▾ → Shape: Circle/Square) en
  zet de **default op circle** (zoals het story-plan vroeg). Via de SwiftData-migratie-default
  (`frameShapeRaw = "circle"`) krijgen óók bestaande portretten de cirkel — d.w.z. de cirkel wordt
  de zichtbare merkvorm op canvas + in de export (transparante hoeken).
- **Te bevestigen:** is cirkel de gewenste default (i.p.v. square)? Zo niet: één regel in
  `Portrait2.frameShapeRaw` (default → `.square.rawValue`). Niet-blokkerend; alles werkt nu met circle.

### Double-opt-in filtering bij nieuwsbrief-dispatch (E17.6) — VOORSTEL, wacht op Thierry
- **Context:** `newsletter_optins` (sql 014) is een additief opt-in-grootboek. De dispatch filtert
  er nu bewust NIET op, zodat bestaande account-houders (die al opt-in gaven bij registratie) niet
  retroactief uitgesloten raken.
- **Voorstel:** voor puur-marketing-/re-engagement-cohorten de dispatch optioneel laten filteren op
  `confirmed_at IS NOT NULL` (ontgrendel dan ook de `payload_app`-SELECT-grant in sql 014).
  Transactionele/welkom-mails blijven ongefilterd. Te bevestigen door Thierry vóór live.

## Beslist

### Banners-feature-flag: blijft uit tot gebruikersvraag (E37) — BESLIST 2026-07-12
- **Besluit (Thierry):** `AppFeatureFlags.bannersEnabled` blijft default **uit**, ook nu alle
  technische blockers (37.17–37.19) zijn opgelost. Flip pas wanneer er aantoonbare gebruikersvraag
  naar banners is. De matched-background banner-export in Social Preview blijft wél live.

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

### OTP "token has expired or is invalid" bij sign-in — ✅ OPGELOST (2026-06-15)
- **Resolutie:** end-to-end onderzocht via de Supabase Management API + auth-logs. Server-zijde is
  gezond en was NIET de oorzaak. De templates (confirmation + magic_link) zijn al **token-only**
  (`{{ .Token }}`, geen `ConfirmationURL`/href/URL) sinds 06-12, `mailer_otp_exp=3600`, Resend-SMTP
  actief. Een **vers** OTP verifieert direct met `type: .email` (getest via `admin/generate_link` +
  `/auth/v1/verify`). De "expired" was **client/build-state** (oude binary, of een oude code ná
  "Resend" die de vorige ongeldig maakt) — verholpen met een verse build + één schone poging.
  Logs bevestigden `/otp`→`/verify`→`login` zonder `otp_expired`.
- **WEERLEGD (niet opnieuw najagen):** de magic-link-prefetch-theorie en "OTP-expiry te kort" —
  beide kloppen niet met de live config. (Memory: `project_otp_expired_resolved`.)
- **Historie:** symptoom was "Token expired" bij verify; E18.21 probeerde `.email`+`.signup`-fallback
  (later teruggedraaid naar enkel `.email`, wat correct is). App-kant (verify + foutweergave) klaar.

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
- **Status:** DEFAULT GEBOUWD (24.8 done). De keuzes hieronder blijven open ter bevestiging/iteratie
  door Thierry — niet-blokkerend.
- **Gevraagd:** scroll/pinch = canvas-zoom (view); de afbeelding zélf schalen via een SELECTIE
  (resize-handles / scale-grip), niet via zoom. Referenties volgen.
- **Gebouwde default:** view-zoom (efemeer 1×–4×) op pinch/scroll/dubbelklik + zoom-HUD; subject-
  schaal via 4 HOEK-handles (aspect-locked, om het onderwerp-midden, op `Portrait2.scale`, undo'baar).
- **Nog te beslissen/itereren door Thierry:** (a) welke handles — alléén hoeken (huidige default) of
  ook zijkanten?, (b) aspect-lock altijd aan (default) of vrij?, (c) scale op `Portrait2.scale`
  (default) of een aparte selectie-transform?, (d) gedrag bij meerdere lagen later, (e) moet de
  view-zoom pannen wanneer ingezoomd? Pas ik aan zodra Thierry kiest.

### E31 Toolbar-unificatie — geblokkeerd: Figma-bestand niet open (2026-06-21)
- **Status:** ALLE 6 ready-stories (31.1–31.6) geblokkeerd. Geen andere `ready` stories op het board
  (de rest is `done`/`blocked`/`backlog`/`todo`). De marathon-loop stopt hierop.
- **Probleem:** E31.1 (onderste toolbar = Figma-capsule) is een expliciete **1-op-1 Figma-build** —
  DoD eist "screenshot tegen `4114:903`". De rest van E31 chaint hierop (31.2→31.1, 31.3→31.2,
  31.6→31.1; 31.4/31.5 horen narratief ná 31.2/31.3/31.5-besluit). De lokale Figma-MCP
  (localhost:3845) is bereikbaar en geïnitialiseerd, maar **de Aaavatar-file is niet de actieve tab**:
  `get_metadata` faalt op `151:1409` (Stories-pagina, CLAUDE.md), `4114:903` én `4114:978` met
  "No node could be found … Make sure the Figma desktop app is open and the document containing the
  node is the active tab." Conform CLAUDE.md ("meld het aan Thierry i.p.v. op een ander bestand door
  te bouwen") bouw ik 31.1 niet blind.
- **Wat Thierry moet doen om te deblokkeren:** open het Figma-bestand **"Aaavatar"** (key
  NtX3dQvGU29gwYQKEcOkSy) in de Figma desktop-app en maak de pagina **Stories** (`151:1409`) de
  actieve tab, zodat de capsule-nodes `4114:903` (App/Hair-scherm) en `4114:978` (floatingToolbar)
  voor de MCP bereikbaar zijn. Daarna kan de loop E31.1 1-op-1 bouwen.
- **NB:** 31.4 zegt formeel `blockedBy: —` en "GEEN Figma-referentie" (placeholder-bouw), maar de
  inhoud ("alléén nog frame/scène-controls") is de **eindstaat ná 31.2/31.3** (Adjust/AI eruit) en
  ná 31.5 (Background erin) → in de praktijk niet vóór 31.1–31.3/31.5 te bouwen zonder rework.

### E31 — bewuste Figma-afwijkingen in de toolbar-unificatie (besloten, gedocumenteerd 2026-06-21)
Geen open vraag — Thierry's besluiten vastgelegd voor het register (CLAUDE.md: afwijkingen van
Figma alleen met expliciet besluit + documentatie):
- **31.5 — Background → frame-lokale toolbar.** Figma zet Background in de onderste capsule-overflow
  (`⋯`, 4114:978). Besluit Thierry (2026-06-19): Background is canvas-gerelateerd → hoort bij de
  frame-lokale (boven)toolbar, niet onderaan. Gevolg: de capsule-overflow is leeg → de **`⋯`-knop
  wordt niet getoond** (keert automatisch terug zodra er wél overflow-tools komen). Background-
  functie (swatches + upload) ongewijzigd; blijft in `CanvasActionToolbar`.
- **31.6 — Face = eigen top-level capsule-knop.** Figma heeft geen top-level Face in de capsule
  (4114:978 = Enhance·Effects·Hair·Shirt·⋯). Besluit Thierry: Face krijgt een eigen knop tussen
  Effects en Hair → onderste set = **Enhance · Effects · Face · Hair · Shirt**.
