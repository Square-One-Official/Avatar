# Epic-loop prompt voor Claude in terminal

Plak dit als eerste bericht in een nieuwe `claude`-sessie, gestart vanuit de
repo-root (`Avatars/`). Vul eerst `docs/EPICS.md` aan met de echte epics.

---

## Doel

Werk alle epics in `docs/EPICS.md` één voor één (of in kleine parallelle
batches) volledig af: implementeren, testen tot groen, mergen naar `main`,
en het backlog-bestand bijwerken. Gebruik git worktrees zodat gelijktijdig
werkende agents nooit dezelfde bestanden overschrijven.

## Vaste regels

1. Werk nooit direct op `main` of `v2-main`. Elke epic krijgt een eigen
   branch + eigen worktree.
2. Naamgeving volgt de bestaande conventie in deze repo: branch
   `v2/eNN-NN.M`, worktree in `.claude/worktrees/eNN-NN.M`
   (bestaande voorbeelden: `v2/e36-36.1`, `v2/e37-37.1`, `feat-e04-4.1`).
3. `docs/EPICS.md` is de single source of truth tussen sessies. Lees het
   altijd opnieuw in, ook na een `/clear`.
4. Succescriterium per epic — groene build + groene tests:
   ```
   xcodebuild -project Avatar.xcodeproj -scheme Avatar \
     -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
   xcodebuild -project Avatar.xcodeproj -scheme Avatar \
     -configuration Debug -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
   ```
   Raakt de epic ook `backend/` of `admin/`? Draai daar aanvullend
   `npm run typecheck` (backend) resp. `npm run build` (admin).
5. Max 5 fix-pogingen per epic. Lukt het daarna niet: zet status op
   `blocked`, noteer de reden in `docs/EPICS.md`, ga door naar de
   volgende epic. Nooit oneindig blijven proberen op één epic.

## Loop — herhaal tot alle epics `done` of `blocked` zijn

1. **Kies epic.** Lees `docs/EPICS.md`, pak de eerstvolgende epic met
   status `todo` (bovenaan / hoogste prioriteit).
2. **Claim.** Zet status op `in_progress` in `docs/EPICS.md`, commit die
   kleine wijziging direct op `main`.
3. **Isoleer.**
   ```
   git worktree add .claude/worktrees/eNN-NN.M -b v2/eNN-NN.M main
   ```
   (Bestaat de branch/worktree al voor deze epic? Hergebruik en check
   eerst de huidige staat voor je verder werkt.)
4. **Parallelliseer waar zinvol.** Bestaat de epic uit meerdere
   onafhankelijke taken die geen bestanden delen? Splits ze op en start
   per taak een subagent (Task tool) die in zijn eigen worktree werkt
   (`.claude/worktrees/eNN-NN.M-taskX`), zodat agents elkaars werk nooit
   overschrijven. Wacht tot alle subagents klaar zijn voor je verder gaat.
   Houd max. 3 epics tegelijk in parallelle worktrees open.
5. **Implementeer** de epic in de worktree.
6. **Test-loop.** Draai de commando's uit regel 4 van de vaste regels.
   Rood? Analyseer de output, fix, test opnieuw — tot groen of tot de
   max-pogingen-limiet.
7. **Rond af bij succes.**
   - Commit alle wijzigingen in de worktree-branch met een commitmessage
     die naar de epic-ID verwijst.
   - Merge de branch terug in `main`.
   - Verwijder de worktree: `git worktree remove .claude/worktrees/eNN-NN.M`.
   - Zet de epic-status op `done` in `docs/EPICS.md`, commit die update
     op `main`.
8. **Ruim de sessie op.** Voeg in het "Voortgangslog" van
   `docs/EPICS.md` een korte notitie toe (1-3 zinnen: wat is gedaan, wat
   was lastig). Start daarna `/clear` voordat je aan de volgende epic
   begint — de status in `docs/EPICS.md` zorgt dat je na het clearen
   precies weet waar je gebleven was.
9. Ga terug naar stap 1.

## Einde

Zodra alle epics `done` of `blocked` zijn: draai een laatste volledige
build+test op `main` en rapporteer een overzicht van afgeronde en
geblokkeerde epics.
