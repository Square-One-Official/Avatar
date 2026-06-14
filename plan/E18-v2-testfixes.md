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
- [x] **18.4 Undo/redo dekt álle stappen** — DONE+gemerged. Audit-uitkomst:
      • Effects/Clothing/Hair riepen `onApply` rechtstreeks aan → **géén undo**. Nu via
        `undoableApply(name)` (leest before vers uit het model-cutoutData, registreert
        ImageEnhanceUndo; undo/redo lopen via onApplyResult → canvas + cutout bewegen mee).
      • Match lighting (CutoutDataUndo) wijzigt alleen cutoutData, niet het gecachte canvas → de
        revert was onzichtbaar. ShellModel.`refreshCanvasFromSelection()` her-afleidt het canvas uit
        het geselecteerde portret; ShellView roept 'm aan op elke undo/redo-notificatie.
      • Reframing (AutoFramer/TransformUndo) wijzigt offset/scale — het E06.4-canvas observeert het
        model al reactief, dus dat werkte. Boost + lokale toggles waren al undo'baar.
      Build groen; undo-wiring spiegelt het werkende boost-pad. (Volledige apply→undo round-trip van
      cloud-effects vraagt live backend + credits → niet via screenshot ge-smoket.)

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
- [x] **18.10 Tooltips op icon-buttons** — DONE+gemerged (ronde 3: nu de Figma Tooltip-component).
      Nieuwe `DSTooltip` 1-op-1 op Figma Components 58:1298: zwart (background/tooltip #000000), witte
      Body/Small, r-lg-hoeken, caret naar het doel. Op DSToolButton: **gecentreerd** bóven (toolbar/
      editor) of ónder (topbar gear/share, tegen de rand) het icoon, caret **4px** (gap-1) van de
      knop, na ~1,2s hover. (Niet via screenshot ge-smoket: .onHover leunt op NSTrackingArea-enter —
      synthetische events triggeren dat niet; Thierry bevestigt hands-on.)
- [x] **18.11 Name/Role-baseline bij focus** — DONE+gemerged. Oorzaak bevestigd: NSTextField
      top-uitlijnt z'n tekst in een hoogte kleiner dan z'n natuurlijke celhoogte, terwijl de
      rust-SwiftUI-Text centreert → de tekst sprong omhoog bij focus. Fix: `VerticallyCenteredText
      FieldCell` (centreert teken- én editor-/selectierechthoek) op het editveld → editstaat valt op
      de rust-Text. Build groen. (Pixel-smoke lastig: het veldje is klein voor synthetische klikken;
      canonieke centreer-cel-patroon — Thierry bevestigt hands-on.)
- [x] **18.12 Lokale enhances = aan/uit-knoppen** — DONE+gemerged. One-click retouch ÉN Improve
      lighting (besluit Thierry: alle lokale, gratis, omkeerbare enhances) zijn nu toggles: 2e klik
      herstelt de foto van vóór i.p.v. stapelen. Generiek `toggleLocalEnhance(key,transform)` +
      `localToggleBaselines`-dict in EditorView; undo/redo houden de staat in sync. Aan-staat =
      checkmark + lime accentrand (EditActionsPanel.activeToggles). Cloud/generatief (Colorise,
      Whiten teeth, …) en uitlijnen (Auto-crop) blijven gewone "pas toe"-acties — toggle is daar
      niet logisch (kost credits / niet zuiver omkeerbaar). Smoke ✓ (beide rijen tonen aan-staat).
- [x] **18.13 Credit-badge subtieler** — DONE+gemerged. EditActionsPanel-rij: titel boven, credit-
      kost (1/2/4 credits) subtiel grijs (Foreground.muted) eronder; rijhoogte 40→52. Groene
      DSProChip alléén nog als Pro-indicator voor niet-Pro (isPro=false). Smoke ✓. (Effects/Hair/
      Clothing tonen de kost al subtiel via een bolt-label — ongemoeid.)
- [x] **18.14 Counter op eigen rij ónder de traffic-lights** — DONE, later TERUGGEDRAAID door 18.19
      (Thierry vond de eigen rij te laag). Zie 18.19.
- [x] **18.15 Edit-paneel compacter + scrollbaar** — DONE+gemerged. Centraal in DSEditPanel:
      `maxWidth: 600` (niet meer volle breedte) + `maxContentHeight: 280` met interne ScrollView
      (minder hoog, scrollbaar) → geldt meteen voor álle panelen (Edit/Effects/Hair/Clothing/
      Background). EditActionsPanel: 2-koloms grid → één kolom (alles onder elkaar). Container:
      fixedSize weg zodat de hoogte-cap regeert; foto (layoutPriority -1) krijgt de extra ruimte →
      merkbaar groter. DSEditPanel-pixeltest aangepast (ImageRenderer rastert scroll-inhoud niet;
      toetst nu op de paneel-kaart i.p.v. scroll-inhoud). Smoke ✓ (smal paneel, één kolom, scroll,
      grotere foto).

## Ronde 3 (test 2026-06-14, live correcties tijdens AI-feature-test)
- [x] **18.17 Klik buiten paneel sluit het** — DONE+gemerged. Staat er een paneel/sidebar open, dan
      sluit een klik op de foto/canvas het (toolSelection → nil). Overlay op de foto-slot, alleen
      actief als er iets open is (anders blijft pan/zoom werken). Smoke ✓ (Background-paneel sloot
      bij klik op de foto).
- [x] **18.18 Paneel hugt de inhoud** — DONE+gemerged. DSEditPanel meet de inhoudshoogte
      (GeometryReader + PreferenceKey) en zet de ScrollView op `min(inhoud, cap)` → géén lege ruimte
      meer onderaan korte panelen (bv. Background). Boven de cap scrollt het. Smoke ✓ (Background
      strak om kleur/afbeelding-rijen, foto groter).
- [x] **18.19 Counter+Upgrade terug op de top-rij** — DONE+gemerged. 18.14 (eigen rij onder de
      lights) bleek te laag; nu weer op de top-rij, verticaal uitgelijnd met de naam-header en de
      Share/Settings-knoppen (gelijke top-inset gap-3, gecentreerd in de 48-knop-band), beginnend ná
      de OS-traffic-lights. Smoke ✓.

- [x] **18.20 Icon-button eerste-klik-animatie** — DONE+gemerged (vermoedelijke fix). De eerste
      paneel-open animeerde "te snel"/naspringerig; oorzaak waarschijnlijk de 18.18-hoogtemeting die
      mee-veerde met de open-animatie (0 → inhoudshoogte). De meting wordt nu zonder animatie gezet
      (`Transaction.disablesAnimations`), zodat het paneel meteen op maat opent. (Animatie-timing
      niet via screenshot te smoken — Thierry bevestigt hands-on of de naspring weg is.)

- [x] **18.22 Panelen overlappen de foto + glas** — DONE+gemerged. De foto houdt nu een CONSTANTE
      maat; het paneel overlapt de onderkant i.p.v. de foto te verkleinen (wisselen tussen menu's gaf
      een onrustige resize). DSEditPanelContainer: foto vult de ruimte, paneel als `.overlay(.bottom)`
      dat van onderen in schuift (clip). DSEditPanel-achtergrond is nu subtiel glas
      (WithinWindowBlur + Background.card 0.82) → de foto schemert licht door, inhoud blijft leesbaar.
      Smoke ✓.

- [x] **18.21 OTP "token expired" + fout als toast** — DONE+gemerged.
      • Vermoedelijke oorzaak: `signInWithOTP(shouldCreateUser: true)` geeft voor een NIEUW adres een
        `.signup`-token, maar we verifieerden altijd met type `.email` → "Token has expired or is
        invalid". `AuthService.verifyCode` probeert nu `.email` en valt terug op `.signup`.
        (Andere mogelijke oorzaak — te korte OTP-expiry in Supabase — = wacht-op-Thierry, live config.)
      • Fout als **toast**: SignInSheet toonde de fout als blijvende inline-tekst; nu een DSToast
        (auto-dismiss 4s) i.p.v. lingerende tekst. Inline-fouttekst in beide stappen verwijderd.
      • Lingerende tekst gewist: `dismissAuthError()` bij sheet-open en bij "Wrong email? Go back";
        code-veld leegt bij een mislukte verify. (Toast-weergave niet ge-smoket: vraagt een live
        Supabase-auth-fout; Thierry bevestigt hands-on.)

## Ronde 4 (test 2026-06-14, vervolg-correcties)
- [x] **18.10v4 Tooltip-positie** — DONE+gemerged. Tooltip stond mídden op het icoon i.p.v.
      erboven; nu via gemeten hoogte (PreferenceKey) + offset volledig bóven (of ónder) de 48-knop,
      gecentreerd, 4px gap. (Hover-weergave niet synthetisch te smoken.)
- [x] **18.23 Toasts rechtsonderin + slide** — DONE+gemerged. App-toasts (cloud-fout, out-of-
      credits) van centraal-onder → `.bottomTrailing` met slide-in/out (move .trailing + opacity),
      gap-5 marge — overlappen geen knoppen meer. Smoke ✓ (layout).
- [x] **18.24 Input error/success-states** — DONE+gemerged. `DSValidationState` (normal/error/
      success) op DSTextField + DSOTPField → rand licht op (Signal.error/success, b-medium). SignInSheet
      gebruikt deze i.p.v. de toast: e-mail/OTP-fout = rode rand (herstelt bij bewerken of na 3s),
      succes = groene rand met 0,7s delay vóór het sluiten. **Figma-TODO:** exacte Input-error/
      success-variant + signaalkleuren op dark bevestigen (nu Badge-signaalkleuren hergebruikt).
- [~] **18.21b OTP "token expired" — dieper onderzocht; app-kant af, root cause WACHT-OP-THIERRY.**
      Tweede ronde n.a.v. test: (1) de "error vóór klik" kwam door **auto-verify op het 6e cijfer** →
      verwijderd; verifiëren vereist nu een klik op Verify. (2) De **toast was weg** (18.24 verving 'm
      door alleen een input-state) → toast terug (toont de echte fout-reden) náást de rode rand. (3)
      De `.email→.signup`-fallback verwijderd: een tweede poging kan de single-use token verbruiken →
      nu één `.email`-verify (correct voor signInWithOTP). Faalt het nog steeds met "Token expired",
      dan ligt het **serverzijde** (Supabase) — zie DECISIONS-PENDING (e-mailtemplate magic-link-
      prefetch / OTP-expiry). De ruwe Supabase-fout staat nu in de toast → bevestigt de oorzaak.

## DB-migraties
- [x] **013 + 014** — DONE door Thierry (in Supabase SQL-editor, 2026-06-14). newsletter_cohorts-
      grants ingetrokken + newsletter_optins-tabel aangemaakt.
- [ ] **Payload `messages`-tabellen** — wacht-op-Thierry: ontstaan via `push:true` bij de volgende
      **avatar-admin**-deploy met de v2-config. /v1/messages geeft tot dan leeg terug (geen fout).

**Volgorde:** 18.6 + 18.5 → 18.1 → 18.8 + 18.9 (done) → dan 18.2 (pro-gate) → 18.13 (credit-badge)
→ 18.15 (paneel-redesign) → 18.12 (retouch-toggle) → 18.3 (toast) → 18.4 (undo) → 18.11 (baseline)
→ 18.10 (tooltips). 18.7 backend = productie gedeployed; DB-migraties wacht-op-Thierry.
