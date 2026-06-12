# Aaavatar — werkafspraken voor agents

## Aaavatar 2.0 (actief project)

We bouwen Aaavatar 2.0 naast de bestaande app. **Lees vóór elke taak `plan/BOARD.md`** — dat is de bron van waarheid voor wat je mag oppakken, en bevat de volledige werkwijze (claimen, WIP-limiet, DoD, branch-naamgeving).

Kernregels (samenvatting, details in BOARD.md):
- Pak alleen stories met status `ready` zonder open blockers; claim door status → `in_progress` + owner te zetten in het epic-bestand.
- Ownership: INFRA = `Avatar2/` + `AvatarKit/`-services · DS = `AvatarUI/` · AI = `AvatarKit/Engines/` + `Avatar/Debug/EdgeBenchmark.swift` · FEAT = `Avatar2/Features/<naam>/`. Blijf binnen je grens; ontbrekende dingen buiten je grens worden een nieuwe story voor het juiste team.
- **`Avatar/` (v1) niet aanraken** behalve in stories gemarkeerd SHARED. De oude app moet blijven werken.
- `done` = beide targets bouwen + tests groen + Result-regel in de story.
- Branch per story: `v2/<epic>-<story-id>` → merge naar `v2-main`. `main` is van v1.

## Vaste kennis

- Cutout-stack: 3 paden — Vision (default), gedownload ORMBG-model, Replicate cloud (`men1scus/birefnet`). Het oude `birefnetLift()` is dood. Comments in deze codebase liegen soms: vertrouw call sites, niet headers.
- Design-bron: Figma-bestand "Aaavatar" (key NtX3dQvGU29gwYQKEcOkSy) — **moet open staan in de Figma desktop-app** voor de lokale MCP. Gebruik node-id's, niet de zichtbare pagina:
  - Stories (flows/schermen): node `151:1409` — https://www.figma.com/design/NtX3dQvGU29gwYQKEcOkSy/Aaavatar?node-id=151-1409
  - Components (tokens/componenten): node `11:180` — https://www.figma.com/design/NtX3dQvGU29gwYQKEcOkSy/Aaavatar?node-id=11-180
  - Settings-voorbeelden: node `4017:10181` · Pro-modal: node `4019:953`
  Check bij twijfel eerst met get_metadata of je het juiste bestand te pakken hebt (verwacht pagina's Stories/Components); zo niet: meld het aan Thierry i.p.v. op een ander bestand door te bouwen.
- Figma is de bron, 1-op-1 overnemen; visuele afwijkingen alleen met expliciet besluit van Thierry, gedocumenteerd in de story. Interacties/states die Figma niet toont: interpreteren in de geest van het hoofddesign. Tokens komen uit Figma's variabelen (get_variable_defs), niet uit benaderingen. Assets (afbeeldingen/illustraties): bouw met een duidelijk gemarkeerde placeholder op de juiste afmetingen/verhouding uit Figma, zodat interacties en animaties volledig uitgewerkt kunnen worden; registreer elke placeholder in plan/ASSETS.md (wat, Figma-frame, formaat). Thierry levert definitieve assets later in één batch — een placeholder stilletjes als definitief behandelen mag niet.
- Plandocumenten: `~/Documents/Claude/Projects/Aaavatar/` (redesign-audit-en-plan.md, aaavatar-2.0-bouwplan.md, pipeline-audit-2.0.md, figma-design-review.md).
- Auth 2.0 = e-mail + OTP, geen Google-UI (Google-infra bewaren). Stripe hangt aan Supabase user-id + e-mail; zie E01.7 voor de identiteitstest.
- Builds: `xcodegen` voor projectgeneratie waar een project.yml ligt; test op beide targets.
