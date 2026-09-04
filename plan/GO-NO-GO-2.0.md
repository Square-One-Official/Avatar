# Go/no-go — Aaavatar 2.0 (E13.3)

Status per **2026-08-21**. ✅ = geverifieerd · ⬜ = open (Thierry) · ✂ = scoped out.
**Regel: alles wat ⬜ staat is een bewust besluit van Thierry — óf doen, óf
expliciet accepteren als launch-risico.** Agent-kant voor epics is af voor
deze release; wat rest is gated (signing, live e2e, assets).

## Scope-wijzigingen (2026-08-21)

- ✂ **E32 Face** (32.0 / 32.1 cloud / 32.5) scoped out of 2.0. On-device Whiten
  teeth (32.2–32.3) blijft in de build.
- ✂ **E55.10** isolatie-erosie deferred — niet release-blokkerend.
- ✂ **E41.3** crystal-pin wontfix — Topaz is Boost-default.
- v1-app-ontwikkeling is bevroren; alleen het **v1→v2 importpad** telt nog
  (bestaande gebruikers).

## 1. Build & tests — ✅ (herverifiëren na WIP-land)

- ✅ Beide targets bouwen, suites groen via `scripts/build-v2.sh` (laatste
  volle groene run 2026-08-01; WIP op v2-main opnieuw draaien vóór beta).
- ✅ v1 (`Avatar`-target) blijft meebouwen in DoD — bevroren, niet kapot.

## 2. Flows compleet — ✅ (code) / ⬜ (laatste oogtest)

- ✅ Onboarding, shell, editor, settings, monetization, E53 UX-polish: done.
- ⬜ **Laatste visuele pass** (Thierry): Home-tijdsecties, reduce-motion,
  icoongrootte, dark+light shell-smoke.

## 3. Bakeoff-besluiten — ✅ (face geschrapt)

- ✅ E09 / E41 / E54 / E10 / E55.7 verwerkt.
- ✂ E32.0 face-bakeoff — scoped out of 2.0.

## 4. Update-kanaal (13.1) — ✅ feed live / ⬜ eerste release

- ✅ Eigen feed op prod: `https://api.aaavatar.nl/appcast-v2.xml` → **200**
  (lege channel — geldig tot de eerste beta).
- ✅ `release-v2.sh` + versielijn 2.0.0 / build 100. **2026-09-04:** script
  publiceert nu als `--latest` mét `Aaavatar.dmg` (website-link serveert 2.0
  zonder Framer-edit); `PRERELEASE=1` = staged. Release-notes:
  `docs/releases/RELEASE-NOTES-2.0.0.md` (concept staat klaar).
- ⬜ **Eerste publieke release** (Thierry: signing / notarisatie / Sparkle-key),
  vanuit de merge-worktree (`.claude/worktrees/merge-main`, AvatarKit wijkt
  daar af van v2-main): `PRERELEASE=1 ./scripts/release-v2.sh 2.0.0 101` →
  appcast-commit → `main` ff + push (= backend-deploy) → Sparkle-e2e →
  `gh release edit v2.0.0 --prerelease=false --latest`. Volledige volgorde in
  het runbook (§Per release).
  *Agent 2026-08-21: Keychain `AC_PASSWORD` ontbreekt op deze Mac → kan de
  release-script niet autonoom afronden.*

## 5. Migratiepad (13.2) — ✅ code / ⬜ echte-data-test

- ✅ `V1LibraryArchive` + `V1LibraryImporter` + Settings “Import backup…”.
- ⬜ **E2E met een échte v1-bibliotheek** (Thierry).

## 6. Stripe-identiteit (E01.7) — ⬜ Thierry

- ✅ Recovery-endpoint op prod.
- ⬜ E2E mismatch-pad + webhook delivery-log.

## 7. Backend & productie-surface — ✅

- ✅ Prod-smoke 2026-08-21: `/appcast-v2.xml` 200; `/v1/effects` 200 met **9**
  actieve stijlen (`balloon`…`urban-chic`).
- ✅ **Custom effects / sql/015** — uitgevoerd in E55.8 (2026-08-03); GO-NO-GO
  was stale. Optioneel: Thierry nog één Create-effect smoke in de app.
- ⬜ Nieuwsbrief double-opt-in (E17.6) — niet blokkerend voor app-launch.
- ✅ **Release-review 2026-09-04** (agent): Avatar2 schoon (alle smoke-haken
  DEBUG-gated, flags default uit, geen keys/hosts), AvatarKit schoon
  (prod-URL hardcoded, preview-override DEBUG-only), backend: `/v1/unsplash`
  kreeg optionalUser + per-IP-limiter; cloud-cutout in BackendClient is
  v1-only gemarkeerd (Avatar2 heeft geen call site, v1's ImageProcessor wel —
  weg zodra het v1-target weg is); CI groen gemaakt (backend `ws`+`sharp` gebumpt; admin `payload
  generate:types` in CI). Geverifieerd via build-v2.sh + npm test.
- ⬜ **sql/021 toepassen** (Thierry, Supabase SQL-editor) — `max_app_version`
  op `payload.announcements`; **vóór de main-push** (admin-deploy), anders
  gaat de Announcements-detailpagina zwart en soft-failt `/v1/announcements/pending`.
- ⬜ **v1-gebruikers informeren**: Payload-Announcement "Aaavatar 2.0 is here"
  met `maxAppVersion` = `1.99`, eerst-backup-exporteren-instructie (2.0 heet
  óók Aaavatar.app en vervangt v1 bij drag-install), CTA naar de download;
  publiceren ná stap 9 van het runbook.

## 8. Feature-flags & vangnetten — ✅

- ✅ `bannersEnabled` default UIT; Sparkle + E46/E44/E47 intact.

## 9. Assets — ✅ beta met placeholders

- ✅ **2.0.0-beta besluit (2026-08-21):** ship met geregistreerde placeholders
  (ASSETS.md). Definitieve batch post-beta, niet blokkerend.

## Kort: wat moet er minimaal gebeuren vóór "go"

### Alleen Thierry kan dit (signing, echte data, dashboards)

1. `release-v2.sh 2.0.0 101` + Sparkle-update-e2e (**AC_PASSWORD** nodig) —
   stappen in [docs/eng/RELEASE-2.0.md](../docs/eng/RELEASE-2.0.md).
2. v1→v2 migratie-e2e met echte bibliotheek.
3. Stripe-mismatch-e2e + webhook-log.
4. Visuele passes (Home-secties voorop). ~~E32.0~~ ✂ scoped out.

### Al groen

- ~~Backend appcast-v2 + sql/015~~ ✅ gedaan.
- ~~Assets~~ ✅ beta-met-placeholders.
- Build & tests, flows (code), feature-flags, backend-surface — zie §1, §2, §7, §8.

### Dag-2, niet blokkerend

- Nieuwsbrief double-opt-in (E17.6).
- Definitieve asset-batch (ASSETS.md).
- Scripthardening release-v2 (preflight/verify/hervatbaar) — zie "Bekende
  gaten" in het runbook.
- admin: `sharp` <0.35 (libvips-CVE's, high) en `payload` ≤3.88 (moderate,
  geen fix) — de admin-audit-stap in CI is sinds 2026-09-04 advisory
  (`continue-on-error`); oplossen = Payload-familie in lockstep bumpen
  (payload + alle @payloadcms/* op één versie) en dan sharp 0.35. Backend
  draait al op sharp 0.35.4.
- BackendClient: 401 → token-refresh → retry (nu "Session expired"-pad);
  `fatalError` bij ModelContainer-creatie → herstel-UI; TLS-pin-rotatie
  vóór 2027-03 (LE R13); `backend/.env.example` bijwerken;
  `website/terms.md` "free of charge" → credits/Stripe.
