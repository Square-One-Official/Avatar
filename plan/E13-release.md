# E13 — Release-voorbereiding

Team: **INFRA**

Laatste epic (13.0 uitgezonderd: doorlopende deploy-port, kan eerder).

## 13.0 — Backend-port v2-main → main (productie-deploy)
- status: in_progress
- owner: INFRA
- blockedBy: —
- DoD: backend-typecheck groen op main; v2-main-kant ongewijzigd
- Context: Vercel (avatars-api, rootDirectory=backend) deployt `main`, niet v2-main. (Story toegevoegd op besluit Thierry 2026-06-12.)

Backend-wijzigingen die op v2-main landen naar `main` porten zodat ze op productie komen.
Wachten inmiddels: het recovery-endpoint `/v1/auth/send-recovery-email` (E01.7 — staat als
niet-gecommit v1-werk in de hoofd-checkout) én MODEL_REGISTRY/`model_override` (E01.10).
Tot een port gedraaid is testen agents in-app tegen een Vercel-preview-deploy van de branch
(genoteerd in E09.1 en E15.5).

**Result:** _(invullen bij done)_

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
- [ ] /v1/auth/send-recovery-email deployen (staat als niet-gecommit v1-werk) en E2E mismatch-pad
      testen.

**Result:** _(invullen bij done)_

