# E46 — Undo & bevestiging bij destructieve acties

Team: **FEAT**

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevinding C9).
Portret-delete heeft al een `confirmationDialog` (`PortraitContextMenu.swift:149-167`,
`BoardView.swift:224-241`); banner- en map-delete niet, en geen enkele delete is
undo'baar terwijl de undo-infrastructuur (`TransformUndo`, `CutoutDataUndo`) er al is.

---

## 46.1 — Confirm-dialoog op banner- en map-delete
- status: done
- team: FEAT
- blockedBy: —

**Wat:** `BannersGalleryView.swift:140-143` verwijdert direct vanuit het
contextmenu (`modelContext.delete(banner)`), zonder vraag. Map-delete
(`LeftNavView.swift:123-128`) idem (milder omdat de delete-rule `.nullify` is, maar
inconsistent met portret-delete).
**Voorstel:** hetzelfde `confirmationDialog`-patroon als bij portret-delete
toepassen op beide plekken.
**DoD:** beide targets bouwen; handmatige smoke (delete-poging toont dialoog, annuleren
laat het item ongemoeid); tests groen; Result-regel.
**Result:** banner-delete (`BannersGalleryView`) en map-delete (`LeftNavView`) tonen nu
hetzelfde `confirmationDialog` als portret-delete ("Delete this banner/folder?" +
destructive Delete/Cancel + message); het contextmenu zet alleen nog een
delete-target-state, de daadwerkelijke delete zit in de dialoog. Map-message benoemt
expliciet dat portretten blijven (delete-rule `.nullify`). Handmatige smoke nog te
doen door Thierry (worktree-build).

## 46.2 — Dangling `backgroundBannerID` opruimen bij banner-delete
- status: done
- team: FEAT
- blockedBy: 46.1

**Wat:** wanneer een banner verwijderd wordt die als portret-achtergrond gekoppeld is
(E40), blijft `portrait.backgroundBannerID` naar het verwijderde item wijzen — de
"Update"-badge-logica kan dan nooit meer matchen.
**Voorstel:** bij banner-delete alle portretten met dat `backgroundBannerID` naar
`nil` zetten (achtergrond-pixeldata mag blijven staan, alleen de koppeling wissen).
**DoD:** verwijderen van een als-achtergrond-gebruikte banner laat geen dode
verwijzing achter; tests groen; Result-regel.
**Result:** nieuwe centrale helper `BannerDeletion` (Features/Banners): `delete(_:in:)`
wist eerst `backgroundBannerID` van álle gekoppelde portretten en verwijdert dan
het document; pixeldata blijft staan. Matching gebeurt op de GEDECODEERDE
`PersistentIdentifier` (`bannerID(from:)`), niet op de rauwe string: de tests
bewezen dat `JSONEncoder` de sleutelvolgorde niet garandeert, dus twee encodes
van dezelfde ID kunnen verschillende bytes geven. Het contextmenu in
BannersGalleryView (de enige banner-delete-plek; geen batch- of keyboard-delete
voor banners) loopt er nu doorheen. Unit-tests:
`Avatar2Tests/BannerDeletionTests.swift` (koppeling gewist, andere banners
ongemoeid, pixeldata blijft, linkKey↔bannerID-roundtrip, corrupte sleutels → nil).
⚠️ Follow-up (buiten E46-scope, zelfde wortel): de `linked`/`isStale`-check in
`BackgroundPanel.bannersRow` byte-vergelijkt de encoded key en is dus flaky om
precies dezelfde reden — moet ook op gedecodeerde identiteit gaan vergelijken.

## 46.3 — Undo/prullenbak voor bulk-delete van portretten (backlog)
- status: backlog
- team: FEAT
- blockedBy: —

**Wat:** alle deletes zijn kale `modelContext.delete(...)`-aanroepen; een
per-ongeluk bulk-delete (12 collega's in één keer, board ondersteunt dit) is
onherstelbaar — terwijl transforms en cutout-vervangingen wél netjes op de
window-`UndoManager` registreren.
**Voorstel:** delete via undo-registratie (re-insert van een snapshot bij ⌘Z), of een
lichte soft-delete/prullenbak-staat, minimaal voor bulk-acties.
**DoD:** een bulk-delete is binnen dezelfde sessie ongedaan te maken via ⌘Z of een
prullenbak-UI; tests groen; Result-regel.
