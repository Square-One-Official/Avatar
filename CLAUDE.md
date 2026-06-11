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
- Design-bron: Figma "Aaavatar", pagina's "Stories" (flows) en "Components" (tokens/componenten). Lokale Figma MCP-server staat in `.mcp.json` (vereist draaiende Figma desktop-app).
- Plandocumenten: `~/Documents/Claude/Projects/Aaavatar/` (redesign-audit-en-plan.md, aaavatar-2.0-bouwplan.md, pipeline-audit-2.0.md, figma-design-review.md).
- Auth 2.0 = e-mail + OTP, geen Google-UI (Google-infra bewaren). Stripe hangt aan Supabase user-id + e-mail; zie E01.7 voor de identiteitstest.
- Builds: `xcodegen` voor projectgeneratie waar een project.yml ligt; test op beide targets.
