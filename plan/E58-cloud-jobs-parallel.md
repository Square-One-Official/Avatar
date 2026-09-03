# E58 — Parallelle cloud-edits over portretten (job-registry + multi-toast)

Team: **FEAT** (lead) + **DS** + **INFRA**

Aanleiding (Thierry, 2026-09-03): "It seems like we can't apply multiple
enhances that use the cloud whilst something is already in progress." De
gewenste workflow is van foto naar foto gaan en op elk een cloud-edit starten
zonder te wachten tot de vorige (40–85 s) klaar is.

**Besluit-richting (voorstel, audit 2026-09-03): parallel over portretten,
serieel per portret.** Een wachtrij zou foto 3 laten wachten op foto 1 en 2 —
precies de workflow die we willen ontgrendelen. Jobs op verschillende
portretten zijn onafhankelijk (resultaat reist mee met het doelportret, server
rekent pas af ná succes). Binnen één portret niet: de panelen bouwen bewust
een volgende edit op het resultaat van de vorige (E32.3), dus daar blijft
één job tegelijk.

## Bevindingen audit (waar de blokkade nu zit)

Er is géén echte globale lock; het zijn vier losse, inconsistente stukjes
UI-state:

1. **Paneel-modellen** (Effects/Hair/Clothes/Face) gaten op hun eigen
   `phase == .working` (`EffectsPanel.swift` `isBusy`). Ze worden per portret
   herbouwd (`.id(portraitModel?.persistentModelID)` in `EditorView`), dus een
   portret-wissel maakt het paneel al vrij — maar het oude model leeft door in
   zijn Task en roept bij afronden `dismissWorkingToast()` zónder id aan.
2. **Boost / Colorise / Remove background / Fill body** zijn `@State`-vlaggen
   (`isBoosting`, `isColorising`, `isRemovingBackground`, `isFillingBody`) op
   één persistente `EditorView` die níet op het portret gekeyed is. Boost op
   foto A blokkeert dus Boost op foto B.
3. **Fill body** zet `blocksOtherAIFeatures: true` → `allowAIFeature` weigert
   élke cloud-feature app-breed, en `PortraitEditSubmenu` disablet de Edit-tak.
4. **Working-toast is één slot** (`EntitlementModel.workingContext`, host in
   `Avatar2App.swift`). Job B vervangt A's toast; als A klaar is verdwijnt B's
   toast terwijl B nog loopt. Dáárdoor voelt het als "kan niet".

Wat al klopt voor parallel: `ShellView` geeft de panelen het doelportret mee
in de closure (`[target = model.selectedPortrait]`), `storeEffectResult` zet
het canvas alleen als het doel nog geselecteerd is, en het E55.9-detach-
patroon (resultaat landt stil in de kaart-cache + `portrait.effectCache`)
is precies het gedrag dat we app-breed willen. De tegelmenu-batches (E57)
lopen al netjes serieel met "x of N" en één batch tegelijk.

Randvoorwaarde backend: `checkRateLimit` (`backend/lib/auth.ts`,
`cutoutLimiter`) is een token-bucket van **3 tokens, refill 3 per 6 s per
gebruiker**, gedeeld door stylize/colorize/upscale/fill-body. Meer dan drie
vrijwel-gelijktijdige starts → 429.

## 58.1 — Cloud-job-registry: parallel over portretten, serieel per portret
- status: backlog (richting voorgesteld 2026-09-03; claimen zodra Thierry de
  richting "parallel, niet queue" bevestigt)
- team: FEAT
- blockedBy: —

**Wat.** Eén centrale registry van lopende cloud-jobs (op `ShellModel` of
`EntitlementModel`): `id`, `portraitID`, `kind` (effect/hair/clothes/face/
boost/colorise/fillBody/removeBackground), `startedAt`, `expectedSeconds`,
`cancel`/`detach`-handler, `blocksSamePortrait`. Panelen en `EditorView`
leiden hun busy-staat hieruit af **per portret + kind** i.p.v. eigen vlaggen.

**Scope.**
- `EditorView`-vlaggen (`isBoosting` e.d.) vervangen door registry-lookups op
  `portraitModel.persistentModelID`; `fillBodyTask` in de registry.
- Paneel-`isBusy` = "loopt er een job op dít portret" (elke kind — serieel per
  portret), niet "loopt er iets in dit paneel".
- **Portret-wissel = impliciete detach**, generalisatie van E55.9 naar Hair,
  Clothes, Face, Boost, Colorise, Fill body, Remove background: de job loopt
  door, resultaat landt op het doelportret (bestaande target-closures), undo
  registreert op het portret (niet op de view — zie `registerSelectionUndo`-
  les), canvas alleen bijwerken als het doel geselecteerd is (bestaat al).
- Terug-navigeren naar een portret met een lopende job = re-attach van de
  toast met doorlopende tijd (55.9-patroon `reattach`).
- Fill body's `blocksOtherAIFeatures` wordt per-portret (`blocksSamePortrait`);
  `PortraitEditSubmenu.editIsBusy` gaat over op de registry (batch-acties
  blijven één batch tegelijk, maar blokkeren geen losse editor-jobs op
  andere portretten en andersom niet).
- **Concurrency-cap 3 in flight** met FIFO daarachter (client-side), passend
  bij de 3/6 s-bucket; de vierde start toont "Queued — starts when a slot
  frees up" i.p.v. een 429-fout. Cap als constante, zodat 58.3 'm kan
  verhogen.
- Iedere `dismissWorkingToast`-aanroep gaat op id (bestaat al:
  `dismissWorkingToast(id:)`, callers gebruiken 'm nu niet).
- Tegel-badge in Home/Portraits/board voor "job loopt" (spinner) en
  "resultaat geland, nog niet bekeken" (checkmark, zelfde taal als de
  55.9-kaartstip) zodat de gebruiker gedetachte resultaten terugvindt.

**Buiten scope.** Parallel binnen één portret; server-side job-queue;
her-proberen na 429 (blijft bestaande `rateLimited`-fout); Effects-
versiehistorie (55.12 — gedetachte generaties blijven overschrijven tot
55.12 landt).

**DoD.** Beide targets bouwen; unit-tests op de registry (per-portret
serieel, cross-portret parallel, cap+FIFO, detach-bij-wissel, dismiss-op-id
laat andere jobs staan); smoke: effect op A starten → naar B → Boost op B →
terug naar A (toast re-attached, tijd loopt door) → beide resultaten landen
op het juiste portret, canvas van het geselecteerde portret klopt, undo per
portret; vierde job toont Queued en start vanzelf; `build-v2.sh` groen.

## 58.2 — Multi-job WorkingToast
- status: backlog
- team: DS+FEAT
- blockedBy: 58.1

**Wat.** `WorkingToastView`/host in `Avatar2App.swift` van één `WorkingContext`
naar de registry: de job van het geselecteerde portret staat voorop (titel,
klok, voortgang, Cancel/Detach zoals nu); andere jobs als compacte regel
"2 more running" met portret-naam, klok en eigen Cancel. Fouten van een
niet-geselecteerd portret komen als error-toast mét portret-naam. Geen
Figma-frame: interpreteren in de geest van het hoofddesign (DSToast-chrome
van 55.9), placeholder in plan/ASSETS.md alleen als er een icoon nodig is
dat het DS nog niet heeft.

**DoD.** Beide targets bouwen; `WorkingToastLabelTests` uitgebreid met de
meer-jobs-samenvatting; reduce-motion-guard (E53.4) blijft groen; smoke
zoals 58.1 met zichtbare stapeling.

## 58.3 — Backend: aparte rate-bucket voor lange generaties (optioneel)
- status: backlog
- team: INFRA
- blockedBy: 58.1

**Waarom.** `cutoutLimiter` (3/6 s) is gedimensioneerd op snelle cutouts en
wordt gedeeld door stylize/colorize/upscale/fill-body. Met parallelle edits
is de bucket de feitelijke cap. Voorstel: eigen `stylizeLimiter` (bv. 6
tokens, refill 6 per 30 s per gebruiker) voor de dure, lange endpoints; de
client-cap in 58.1 meebewegen. Kosten-exposure blijft begrensd door credits
(server rekent per succes af) en de bestaande Replicate-throttle
(zie memory "Replicate-ratelimits").

**DoD.** Limiter-test in `backend/`; prod-deploy gated op Thierry
(`vercel --prod` vanaf repo-root, zie release-runbook).

## Risico's
- Meerdere lopende jobs × ~2 MB PNG-resultaten in geheugen: bij de cap van 3
  verwaarloosbaar; bij verhoging (58.3) meten.
- Een job die landt op een portret dat intussen verwijderd is: registry
  moet het resultaat stil laten vallen (test in 58.1).
- Undo-stack over portretten heen: `NSUndoManager` is per venster; een
  gedetacht resultaat registreert undo op een niet-zichtbaar portret —
  zelfde situatie als 55.9-detach vandaag, acceptabel, maar in de smoke
  expliciet checken dat Cmd+Z op portret B niet A's edit terugdraait.
