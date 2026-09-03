# Documentatie

## Cursor / Git-workflowgids

Visuele uitleg (Nederlands) over Cursor Cloud Agents, branches, pull requests, Vercel en Xcode.

| Versie | Doel |
|--------|------|
| [cursor-git-workflow-guide.html](./cursor-git-workflow-guide.html) | Volledige visuele gids (open lokaal in de browser) |
| [cursor-git-workflow-guide.md](./cursor-git-workflow-guide.md) | Zelfde inhoud, leesbaar op GitHub |

### Belangrijk

De gids staat op **`v2-main`** (gemerged via PR #37).

Op `main` of een checkout die alleen in `Avatar2/` zoekt krijg je **File not found** — de bestanden zitten in `docs/` op de **repo-root**.

**Direct op GitHub:**

- HTML: https://github.com/Square-One-Official/Avatar/blob/v2-main/docs/cursor-git-workflow-guide.html
- Markdown: https://github.com/Square-One-Official/Avatar/blob/v2-main/docs/cursor-git-workflow-guide.md

**Lokaal openen** (vanaf de **repo-root**, niet vanuit `Avatar2/`):

```bash
# Repo-root = map met docs/, Avatar2/, backend/, README.md
cd "/pad/naar/Avatar"

git fetch origin
git checkout v2-main
git pull origin v2-main
open docs/cursor-git-workflow-guide.html

# Zit je al in Avatar2/? Gebruik dan:
# open ../docs/cursor-git-workflow-guide.html
```
