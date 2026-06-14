# E18 — V2 test-fixes (Thierry's testsessie 2026-06-14)

Bevindingen uit de hands-on test van Avatar2. Per fix: branch → build-v2 groen → merge v2-main →
afvinken. UI-fixes met visuele smoke.

## Blockers (testen onmogelijk zonder)
- [x] **18.1 E-mail-login vanuit Settings/Account** — DONE+gemerged. `SignInSheet` (e-mail→OTP via
      AuthService) + EntitlementModel-proxies (sendSignInCode/verifySignInCode/authBusy/authError);
      Account-pagina (uitgelogd) toont nu een "Sign in"-kaart → sheet. Smoke ✓.
- [x] **18.7 Backend bereikbaar voor test** — DONE: Thierry koos productie-deploy. Gecureerde port
      (main + v2-backend, send-recovery-email behouden) live op api.aaavatar.nl; origin/main → b27b31b.
      stylize/upscale/messages-routes geverifieerd (401/405 i.p.v. 404). LET OP: fill_body 1→2 credits
      raakt nu ook de live v1-app. DB-migraties (013/014/Payload-messages) blijven gated.

## UX / gedrag
- [x] **18.2 Pro-opties klikbaar → contextuele gate** — DONE+gemerged. Stub-cloud-acties (Colorise,
      Whiten teeth, Apply make-up, Reduce wrinkles, Restore body) niet meer gedimd; tik →
      `EntitlementModel.allowCloudFeature()`: (1) online uit → "Turn on online models?"-alert; (2)
      niet ingelogd → SignInSheet; (3) geen Pro/credits → paywall. Effects/Hair/Clothing/Boost
      gaan ook door de gate. Smoke ✓ (acties enabled).
- [x] **18.3 Cloud-fouten als toast** — DONE+gemerged (samen met 18.2). `EntitlementModel.errorToast`
      + `presentError`; DSToast-overlay onderin (auto-dismiss 4s). Effects/Hair/Clothes/Boost-
      failures → toast i.p.v. inline tekst onder de menutitel.
- [ ] **18.4 Undo/redo dekt álle stappen** — "Match lighting" (sidebar) undo't niet. Controleer dat
      undo/redo écht elke stap meeneemt: effects, kleding, haar, boost, match-lighting, reframing.
      (Match lighting gebruikt CutoutDataUndo + eigen undo-groep; waarschijnlijk werkt de
      sidebar-undoManager niet of de @Query ververst de thumb niet na revert — onderzoeken.)

## Layout / styling
- [x] **18.5 Name/Role-header** — DONE+gemerged. Header top-uitgelijnd met de topbar-knoppen
      (padding gap8→gap3) en `.frame(height:52, alignment:.top)` zodat het editveld bij focus alleen
      naar beneden uitklapt — "Name" springt niet meer naar boven. Smoke ✓.
- [x] **18.6 Topbar-padding** — DONE+gemerged. Gedeelde `ShellMetrics.topBarInset` (gap-3, == redo):
      gear-trailing gap-3 (niet meer tegen de rand), counter zit gap-3 ná de window-controls. Smoke ✓.
      (Links kan niet hélemaal tegen de rand — macOS traffic lights bezetten ~60pt.)

## Ronde 2 (test 2026-06-14, vervolg)
- [x] **18.8 Account sign-in in Email-rij** — DONE+gemerged. "Sign in"-knop in de Email-rij; los
      Session-blok weg (alleen nog Sign out bij ingelogd). Smoke ✓.
- [x] **18.9 Disabled-knop leesbaar** — DONE+gemerged. DSPrimaryButton: disabled = neutrale pil +
      muted-leesbare tekst i.p.v. donkere tekst op dof-lime.
- [ ] **18.10 Tooltips op icon-buttons** — hover ~1–1.5s → label (bv. "Edit") boven de knop.
- [ ] **18.11 Name/Role springt NOG steeds** bij focus (18.5 top-align loste het niet op — echte
      oorzaak = baseline-verschil Text vs NSTextField in DSInlineEditLabel).
- [ ] **18.12 One-click retouch = toggle** — 2e klik herhaalt nu i.p.v. terug naar origineel; maak
      het een aan/uit-knop.
- [ ] **18.13 Credit-badge subtieler** — groene badge = Pro-indicator (voor niet-Pro); credit-kost
      subtiel grijs ónder de titel i.p.v. prominente groene chip (knop mag hoger).
- [x] **18.14 Counter op eigen rij ónder de traffic-lights** — DONE+gemerged (keuze Thierry).
      ShellTopBar is nu een VStack: rij 1 = top-strook (h52) met rechts Share/Settings, links de
      OS-lights; rij 2 = quota + Upgrade-chip, leading = `topBarInset` (gap-3 = 12). Counter zit nu
      écht ~12pt van de linkerrand i.p.v. ~72pt ernaast. Smoke ✓.
- [ ] **18.15 Edit-paneel compacter + scrollbaar** — alle acties onder elkaar in een scrollbare
      lijst; paneel minder hoog + niet volle vensterbreedte (compacter); foto groter. Idem voor de
      andere menupanelen (Effects/Hair/Clothing/Background).

## DB-migraties
- [x] **013 + 014** — DONE door Thierry (in Supabase SQL-editor, 2026-06-14). newsletter_cohorts-
      grants ingetrokken + newsletter_optins-tabel aangemaakt.
- [ ] **Payload `messages`-tabellen** — wacht-op-Thierry: ontstaan via `push:true` bij de volgende
      **avatar-admin**-deploy met de v2-config. /v1/messages geeft tot dan leeg terug (geen fout).

**Volgorde:** 18.6 + 18.5 → 18.1 → 18.8 + 18.9 (done) → dan 18.2 (pro-gate) → 18.13 (credit-badge)
→ 18.15 (paneel-redesign) → 18.12 (retouch-toggle) → 18.3 (toast) → 18.4 (undo) → 18.11 (baseline)
→ 18.10 (tooltips). 18.7 backend = productie gedeployed; DB-migraties wacht-op-Thierry.
