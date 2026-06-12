# E08 — Barebones-flows

Team: **FEAT**

Bewust minimaal; volledige flows volgen als Figma af is.

## 8.1 — Settings barebones
- status: ready
- owner: —
- blockedBy: E03.2, E03.6
- DoD: beide targets bouwen, tests groen

Notitie (FEAT): E03.6 (toggle-component) toegevoegd als blocker — de privacy/engine-sectie
heeft dezelfde online-modellen-toggle nodig als E04.3.

Privacy/engine (incl. High-fidelity edges-downloadkaart uit onboarding), account, versie. Eén
venster, drie secties.

**Result:** _(invullen bij done)_

## 8.2 — Export barebones
- status: backlog
- owner: —
- blockedBy: E07.2
- DoD: beide targets bouwen, tests groen

Eén preset (vierkant PNG 1024) + share sheet; watermark voor free.

**Result:** _(invullen bij done)_

## 8.3 — Paywall/credit-states barebones
- status: done
- owner: FEAT
- blockedBy: E01.5, E03.4
- DoD: beide targets bouwen, tests groen

Hergebruik v1 ProUpgradeSheet-logica via AvatarKit; op=op-toast.

Notities (FEAT, bij oplevering):
- EntitlementModel.requestUpgrade() is dé opstap voor alle gating (zelfde route als
  DSGated.onUpgradeRequested); handleOutOfCredits() is het 402-pad (op=op-toast, tik = paywall).
- Tijdelijke EntitlementStatusStrip (quota-badge + upgrade-knop) op de placeholder tot E05/E06
  echte callsites leveren; verwijderen bij de main-shell.
- StoreKit-tak van CheckoutResult bewust niet gebouwd (DMG-pad eerst, zoals v1) — hoort bij een
  latere MAS-story. Geen Figma-paywall-frame; opgebouwd uit DS-componenten, visuele pass later.
- Logica alleen build-gedekt tot E01.9 (Avatar2-testtarget, INFRA) landt.

**Result:** Paywall barebones in Avatar2/Features/Paywall/ — EntitlementModel (me/subscribeAnonymous/topup via AvatarKit BackendClient, jaar- en best-value-ankers uit v1), state-aware PaywallSheet (subscribe ↔ top-up-ladder), op=op-DSToast met timer en tik-naar-paywall, EntitlementStatusStrip als tijdelijke opstap; beide targets bouwen groen, packagetests groen, smoke-run OK.

