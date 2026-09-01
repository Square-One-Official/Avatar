# Documentatie

## Cursor / Git-workflowgids

Visuele uitleg (Nederlands) over Cursor Cloud Agents, branches, pull requests, Vercel en Xcode.

| Versie | Doel |
|--------|------|
| [cursor-git-workflow-guide.html](./cursor-git-workflow-guide.html) | Volledige visuele gids (open lokaal in de browser) |
| [cursor-git-workflow-guide.md](./cursor-git-workflow-guide.md) | Zelfde inhoud, leesbaar op GitHub |

### Belangrijk

Dit bestand staat op de featurebranch van PR #37 (`cursor/unify-menu-containers-7e40`) totdat die is gemerged naar `v2-main`.

Op `main` of een andere oude branch krijg je **File not found**.

**Direct op GitHub (juiste branch):**

- HTML: https://github.com/Square-One-Official/Avatar/blob/cursor/unify-menu-containers-7e40/docs/cursor-git-workflow-guide.html
- Markdown: https://github.com/Square-One-Official/Avatar/blob/cursor/unify-menu-containers-7e40/docs/cursor-git-workflow-guide.md

**Lokaal openen** (vanaf de **repo-root**, niet vanuit `Avatar2/`):

```bash
# Repo-root = map met docs/, Avatar2/, backend/, README.md
cd "/pad/naar/Avatar"

git fetch origin
git checkout cursor/unify-menu-containers-7e40
open docs/cursor-git-workflow-guide.html

# Zit je al in Avatar2/? Gebruik dan:
# open ../docs/cursor-git-workflow-guide.html
```
