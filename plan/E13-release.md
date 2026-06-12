# E13 — Release-voorbereiding

Team: **INFRA**

Laatste epic (13.0 uitgezonderd: doorlopende deploy-port, kan eerder).

## 13.0 — Backend-port v2-main → main (productie-deploy)
- status: done
- owner: INFRA
- blockedBy: —
- DoD: backend-typecheck groen op main; v2-main-kant ongewijzigd
- Context: Vercel (avatars-api, rootDirectory=backend) deployt `main`, niet v2-main. (Story toegevoegd op besluit Thierry 2026-06-12.)

Backend-wijzigingen die op v2-main landen naar `main` porten zodat ze op productie komen.
Wachten inmiddels: het recovery-endpoint `/v1/auth/send-recovery-email` (E01.7 — staat als
niet-gecommit v1-werk in de hoofd-checkout) én MODEL_REGISTRY/`model_override` (E01.10).
Tot een port gedraaid is testen agents in-app tegen een Vercel-preview-deploy van de branch
(genoteerd in E09.1 en E15.5).

**Result:** Port gedraaid 2026-06-12: branch v1/backend-port-2026-06-12 met send-recovery-email (E01.7, stond sinds 19 mei ongecommit) + de zeven E01.10-backendbestanden byte-identiek aan v2-main (diff-geverifieerd), ff-merge naar main (b27cdd5..3bc2a76) en gepusht → Vercel-productie-deploy; tsc-typecheck + models-smoke groen op main; productie-smoke OK (/v1/auth/send-recovery-email: 400 invalid_email waar eerst 404; /v1/colorize zonder auth: 401). Bewust niet mee: backend/sql/012 (device_grants account_link) — hoort bij account-link-werk dat nergens in tracked code bestaat, geen dependency van het endpoint; blijft als los punt in de hoofd-checkout. v2-main-kant ongewijzigd.

## 13.1 — Apart updatekanaal
- status: backlog
- owner: —
- blockedBy: alle FEAT-epics
- DoD: beide targets bouwen, tests groen

Eigen appcast voor 2.0-beta; v1-gebruikers merken niets.

**Result:** _(invullen bij done)_

## 13.2 — Migratiepad
- status: backlog
- owner: —
- blockedBy: E05.4
- DoD: beide targets bouwen, tests groen

v1-library → Portrait2-store (read-only import).

**Result:** _(invullen bij done)_

## 13.3 — Go/no-go-checklist
- status: backlog
- owner: —
- blockedBy: 13.1, 13.2
- DoD: beide targets bouwen, tests groen

Bakeoff-besluiten verwerkt, beide apps groen, onboarding+main flow compleet, Stripe-identiteitstest
(E01.7) geslaagd.

Checklist-items uit E01.7 (INFRA, 2026-06-12):
- [ ] E2E mismatch-pad testen tegen productie. (Deploy-helft is klaar: /v1/auth/send-recovery-email
      staat sinds de E13.0-port van 2026-06-12 op productie.)

**Result:** _(invullen bij done)_

