# E44 — Cloud-actie betrouwbaarheid & foutafhandeling

Team: **FEAT + INFRA**

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevindingen B2, B3).
Focus: wat er gebeurt als een cloud-call (Colorise, Boost, generate-background, …)
mislukt of te lang duurt — vandaag inconsistent en op sommige paden volledig stil.
(De grayscale-import-bug B1 zit bewust **niet** hier maar in `E02-vision-engine.md`
story 2.5 — dat is een engine-bug in `AvatarKit/Engines/`, geen app-laag-foutafhandeling.)

---

## 44.1 — Colorise-timeout te krap + fouttoast te kort zichtbaar
- status: done
- team: INFRA + FEAT
- blockedBy: —

**Wat:** `REPLICATE_TIMEOUT_MS = 50_000` (`backend/lib/replicate.ts:16`) geldt ook
voor colorize, terwijl `vercel.json` colorize 90s `maxDuration` geeft (comment "10s
headroom under the 60s ceiling" is stale). DeOldify op `render_factor: 35` +
cold start zit geregeld tegen/over 50s → 504, **geen** `logCredit` (goed:
geen credit-verlies) maar ook geen zichtbaar resultaat. De client vangt dit wél via
een toast, maar die auto-dismisst na 4s (`Avatar2App.swift:145-148`) — makkelijk te
missen, wat live als "er gebeurt niets" oogde.
**Voorstel:** per-feature timeout in `replicate.ts` (colorize ≥ 80s, in lijn met
`STYLIZE_TIMEOUT_MS`); fout-toasts die een échte fout tonen (i.p.v. info) persistent
maken of minimaal ≥ 8s.
**DoD:** een colorize-call op een grote/trage input faalt niet meer voortijdig; de
foutmelding (bij een resterende timeout) is minimaal 8s zichtbaar; tests groen;
Result-regel.
**Result:** `COLORIZE_TIMEOUT_MS = 80_000` in `backend/lib/replicate.ts` (zelfde
80s/90s-verhouding als STYLIZE/BACKGROUND) + stale "default ceiling"-comment op de
50s-default herschreven naar het per-feature-budgetmodel. Client: fout-toast
auto-dismiss 4s → `EntitlementModel.errorToastDuration` (8s, testbare constante;
`Avatar2App.swift` leest 'm). Test: `testErrorToastStaysVisibleAtLeastEightSeconds`
borgt de ondergrens. `tsc --noEmit` OK; AvatarKit 89 + AvatarUI 37 + Avatar2-scheme
groen. Backend-wijziging NIET gedeployed — lift mee op de volgende deploy.

## 44.2 — Stille guard-paden na een geslaagde server-call
- status: done
- team: FEAT
- blockedBy: —

**Wat:** meerdere plekken in `EditorView.swift` (regels 1291-1294, 1225, 1334-1337)
doen `guard let after = NSImage(data: data) else { return }` — bij een 200 met
onbruikbare bytes: geen fout-toast, geen undo-entry, en géén
`entitlement.refresh()`, terwijl de server op dat pad al een credit kan hebben
afgeschreven. Dit is het codepad dat alle Colorise-symptomen (geen resultaat, geen
zichtbare fout, saldo lijkt onveranderd terwijl er wél afgeschreven kan zijn)
tegelijk kan produceren.
**Voorstel:** elke guard-tak → `presentError(...)` + `entitlement.refresh()` i.p.v.
een kale `return`.
**DoD:** alle drie de genoemde call-sites hebben een zichtbaar faalpad; tests groen;
Result-regel.
**Result:** nieuwe helper `EntitlementModel.presentCloudResultFailure(_:)` =
`presentError` + `await refresh()` (saldo kan al afgeschreven zijn). Alle drie de
guard-sites in `EditorView.swift` (Boost `performBoostResolution`, Colorise
`runColorise`, Fill-in-body `runFillBody`) roepen 'm aan met hun bestaande
feature-copy i.p.v. een kaal `return`. Tests (stub-sessie, E47-patroon):
`testPresentCloudResultFailureShowsToastAndRefreshesBalance` +
`testPresentCloudResultFailureKeepsToastWhenRefreshFails`. Alle suites groen.
De helper is meteen de kiem voor het 44.3-contract (backlog).

## 44.3 — Eén presentError-contract voor alle cloud-acties (backlog)
- status: backlog
- team: FEAT
- blockedBy: 44.1, 44.2

**Wat:** foutafhandeling is vandaag drie-erlei: de globale editor-toast (4s,
auto-dismiss), een inline `errorMessage` in `GenerateBackgroundSheet` (mét
`refresh()` in de catch — dat voorbeeld is goed), en de stille guards uit 44.2.
**Voorstel:** één gedeeld `presentError`-contract (severity, duur, wel/niet
`entitlement.refresh()` triggeren) dat alle cloud-actie-call-sites gebruiken, met
`GenerateBackgroundSheet`'s aanpak als referentie-implementatie.
**DoD:** minstens Effects/Hair/Clothes/Face/Boost/Colorise/Fill-in-body/
generate-background gebruiken hetzelfde contract; tests groen; Result-regel.
