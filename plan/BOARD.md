# Aaavatar 2.0 — Board

**Doel:** Aaavatar 2.0 bouwen naast de bestaande app (die blijft werken tot de grote update). Scope eerste versie: Onboarding + main app volledig; Settings/Export/Paywall barebones.

Bronnen: `~/Documents/Claude/Projects/Aaavatar/aaavatar-2.0-bouwplan.md` (volledig plan), `figma-design-review.md`, `pipeline-audit-2.0.md`. Figma is de design-bron (pagina "Stories" + "Components").

## Hoe dit board werkt (voor elke agent — LEES DIT EERST)

1. Status leeft per story in het epic-bestand (`plan/E##-*.md`): `backlog` → `ready` → `in_progress` → `done`. Jij werkt alleen stories die `ready` zijn én geen open blockers hebben.
2. Claim een story door status op `in_progress` te zetten + je team in `owner`, in dezelfde commit waarin je begint. Eén story per team tegelijk (WIP-limiet 1).
3. `done` mag pas als de Definition of Done haalt: beide targets bouwen (`Avatar` én `Avatar2`), tests groen, één regel resultaat-samenvatting in de story onder **Result:**.
4. Ownership-grenzen: INFRA bezit `Avatar2/` scaffolding + `AvatarKit/`-services; DS bezit `AvatarUI/`; AI bezit `AvatarKit/Engines/` + EdgeBenchmark; FEAT bezit `Avatar2/Features/<naam>/`. Mis je iets buiten je grens → voeg een story toe bij het juiste team (status `ready`), ga zelf verder met iets anders.
5. `Avatar/` (de oude app) is verboden terrein behalve in stories gemarkeerd SHARED.
6. Branch per story: `v2/<epic>-<story-id>`, merge naar `v2-main` bij groene build. `main` blijft van v1.
7. Werk je parallel met andere agents: gebruik git worktrees (`.claude/worktrees/` bestaat al).

## Kolommen (overzicht — detail en status in de epic-bestanden)

| Epic | Team | Status |
|------|------|--------|
| [E01 Fundament](E01-fundament.md) | INFRA | ready |
| [E02 Vision-engine minimaal](E02-vision-engine.md) | AI | ready (na E01.2) |
| [E03 Design system](E03-design-system.md) | DS | done |
| [E04 Onboarding 2.0](E04-onboarding.md) | FEAT | blocked |
| [E05 Main app shell](E05-main-shell.md) | FEAT | blocked |
| [E06 Editor-framework](E06-editor-framework.md) | FEAT | blocked |
| [E07 Background](E07-background.md) | FEAT | blocked |
| [E08 Barebones-flows](E08-barebones.md) | FEAT | blocked |
| [E09 Effects](E09-effects.md) | FEAT+AI | blocked |
| [E10 Clothes](E10-clothes.md) | FEAT+AI | blocked |
| [E11 Hair](E11-hair.md) | FEAT+AI | blocked |
| [E12 Light & Retouch](E12-light-retouch.md) | FEAT | blocked |
| [E13 Release-voorbereiding](E13-release.md) | INFRA | blocked |
