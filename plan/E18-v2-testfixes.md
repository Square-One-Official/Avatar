# E18 — V2 test-fixes (Thierry's testsessie 2026-06-14)

Bevindingen uit de hands-on test van Avatar2. Per fix: branch → build-v2 groen → merge v2-main →
afvinken. UI-fixes met visuele smoke.

## Blockers (testen onmogelijk zonder)
- [x] **18.1 E-mail-login vanuit Settings/Account** — DONE+gemerged. `SignInSheet` (e-mail→OTP via
      AuthService) + EntitlementModel-proxies (sendSignInCode/verifySignInCode/authBusy/authError);
      Account-pagina (uitgelogd) toont nu een "Sign in"-kaart → sheet. Smoke ✓.
- [ ] **18.7 Backend bereikbaar voor test** — AI-routes geven 404 op productie (v2-port niet
      gedeployed) en de preview staat achter Vercel-protection. BESLISSING nodig: preview
      ontsluiten (protection uit/bypass) vs productie-port. Daarna app → preview via DEBUG-override
      + login met DEV_UNLIMITED_EMAILS-account (credit-bypass).

## UX / gedrag
- [ ] **18.2 Pro-opties zichtbaar+klikbaar voor niet-Pro** — alle Pro-opties (Apply make-up,
      Restore body, Whiten teeth, Reduce wrinkles, Colorise, …) niet dimmen/disablen; tik → de
      upgrade-modal (paywall) i.p.v. dode knop.
- [ ] **18.3 Cloud-fouten als toast** — "Couldn't apply that style…" verschijnt nu als tekst onder
      de menutitel; wil een toast-notificatie. (Oorzaak van de fout zelf: 401 niet-ingelogd / 404
      backend — zie 18.1/18.7.) Generieke error-toast in EntitlementModel + Avatar2App-overlay;
      Effects/Hair/Clothes/Boost-failures daarheen routen.
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

**Volgorde:** 18.6 + 18.5 (snelle visuele wins) → 18.1 (login) → 18.3 (toast) → 18.2 (pro→upgrade)
→ 18.4 (undo-audit) → 18.7 (backend, beslissing).
