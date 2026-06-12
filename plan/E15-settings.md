# E15 — Settings volledig

Team: **FEAT**

Vervangt E08.1 (barebones). Figma heeft nu twee voorbeeld-frames: 'App / Settings / Preferences' en 'App / Settings / AI & Models' (sectie Settings, node 4017:10181). Patroon: sub-nav links (4 items) + content rechts met Settings-secties. **Besluit Thierry: de rest van de pagina's zelf invullen in dezelfde stijl.**

## 15.1 — Settings-shell + Preferences
- status: ready
- owner: —
- blockedBy: E03.2
- DoD: beide targets bouwen, tests groen
- Context: Figma 'App / Settings / Preferences' (4019:497); componenten Navigation Button/Setting Row uit Components-pagina.

Venster met sub-nav (4 items) + content-area, conform Figma. Preferences-pagina: Appearance- en
Notifications-secties zoals ontworpen.

**Result:** _(invullen bij done)_

## 15.2 — AI & Models-pagina
- status: backlog
- owner: —
- blockedBy: 15.1, E02.3
- DoD: beide targets bouwen, tests groen
- Context: Figma 'App / Settings / AI & Models' (4019:823); ModelManager-vereenvoudiging uit E02.3. Let op: waveform-icoon in design is placeholder — gebruik cloud/sparkle.

'Allow online models'-toggle (zelfde PrivacyPreferences als onboarding) + Local models-lijst (naam •
RAM-eis • grootte, Active-state, download/delete via icon-button). Hier landt de High-fidelity
edges-download (was E04.4/E08.1).

**Result:** _(invullen bij done)_

## 15.3 — Account-pagina (zelf invullen)
- status: backlog
- owner: —
- blockedBy: 15.1, E14.1
- DoD: beide targets bouwen, tests groen
- Context: stijl uit 15.1; gegevens via AvatarKit (AuthService, ProEntitlement).

In dezelfde stijl: e-mail, plan (Starter/Pro) + Manage subscription, credits-saldo + resetdatum,
sign out. Geen design — extrapoleer Setting Row-patroon.

**Result:** _(invullen bij done)_

## 15.4 — About/Updates-pagina (zelf invullen)
- status: backlog
- owner: —
- blockedBy: 15.1
- DoD: beide targets bouwen, tests groen
- Context: v1 UpdatesSection als functionele referentie; appcast.

Versie, updatekanaal, check-for-updates (Sparkle), links (privacy, site). Zelfde patroon.

**Result:** _(invullen bij done)_
