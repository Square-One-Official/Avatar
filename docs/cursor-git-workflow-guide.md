# Van idee naar productie — Cursor, GitHub en Vercel zonder chaos

> Visuele HTML-versie: [`cursor-git-workflow-guide.html`](./cursor-git-workflow-guide.html)  
> Staat op `v2-main` (gemerged via PR #37). Pad: `docs/` in de **repo-root**, niet `Avatar2/docs/`.

## Hoofdregel

**Eén taak, één branch, één pull request.**  
Pas na samenvoegen (merge) is het onderdeel van de gedeelde nieuwste versie.

---

## Waarom je het overzicht verliest

1. **Elke Cursor-sessie heeft een eigen kopie** — een Cloud Agent ziet andere sessies pas na commit, push en fetch.
2. **Een commit reist niet vanzelf** — die zit op één branch tot je merget of rebase’t.
3. **Een groene Vercel-preview is niet de macOS-app** — Vercel test web/backend, niet Swift/Xcode.
4. **`main` en `v2-main` lopen naast elkaar** — “nieuwste versie” kan twee dingen betekenen.
5. **Parallel werk raakt dezelfde bestanden** — twee agents op `EditorView.swift` maken botsende versies.
6. **Screenshots hebben geen herkomstlabel** — zonder branch/commit/build weet je niet wat je ziet.

**Valkuil:** “Cursor heeft het gefixt” betekent alleen dat één werkkopie is aangepast — nog niet GitHub, jouw Mac, een andere agent of productie.

---

## Het simpele model: vijf haltes

`Idee → Branch → Commit → Pull request → Productie`

| Plek | Wat staat daar? | Gedeelde waarheid? |
|------|-----------------|--------------------|
| Lokaal | Jouw bestanden, mogelijk nog niet in Git | Nee |
| Cursor Cloud | Aparte machine + branch per sessie | Nee |
| Commit | Exacte momentopname met uniek nummer | Alleen binnen die branch |
| GitHub PR | Voorstel + checks + review | Nog niet; pas na merge |
| Hoofdbranch | Alles wat officieel is samengevoegd | Ja, voor ontwikkeling |
| Productie | Uitgerolde website, backend of appbuild | Ja, voor gebruikers |

---

## Waarom lijkt alles een pull request te worden?

Dat is **geen fout**. Cursor Cloud Agents zijn zo ingericht dat elke taak eindigt als een **aparte branch + pull request**.

### Wat een Cloud Agent standaard doet

1. Start vanaf een basisbranch (vaak `v2-main`).
2. Maakt een **nieuwe featurebranch**.
3. Schrijft code, commit en pusht naar GitHub.
4. Opent of werkt een **pull request** bij.

### Waarom dat zo is ontworpen

- **Veiligheid:** de agent mag niet zomaar direct op `main` / `v2-main` schrijven.
- **Review:** jij beslist wat in de gedeelde basis komt.
- **Isolatie:** parallelle sessies raken elkaar niet meteen.
- **Terugdraaien:** een mislukte taak gooi je weg door de PR te sluiten.

**Belangrijk:** een PR is een *voorstel*. Pas na **merge** zit het in de gedeelde nieuwste versie.  
“De agent heeft een PR gemaakt” ≠ “dit staat al in mijn Xcode-project”.

| Effect | Betekenis |
|--------|-----------|
| Veel PRs | Elke Cloud-sessie ≈ vaak één PR |
| Niet automatisch gemerged | Zonder jouw merge blijft Xcode op de oude basis |
| Oplossing | Wijs één canonieke PR aan, merge die, sluit de rest, haal lokaal opnieuw op |

### Prompt om PR-chaos te beperken

```text
- Werk verder op bestaande branch/PR [nummer of naam], open geen nieuwe PR.
- Of: alleen onderzoeken, geen commits/PR.
- Of: integreer open PRs A/B/C in één canonieke PR naar v2-main.

Zonder die instructie maakt een Cloud Agent vaak een nieuwe branch + PR.
```

---

## Waarom Xcode “nog niet werkt” terwijl Cursor al iets heeft gedaan

Xcode toont alleen de bestanden van de **branch die jij lokaal hebt uitgecheckt**.  
Een Cloud Agent werkt op een andere machine en een andere branch.

### Typische situatie

Cursor/Xcode staat op `cursor/enhance-adjust-split-74d1`,  
terwijl de geïntegreerde combinatie op `cursor/unify-menu-containers-7e40` (PR #37) staat,  
en de gedeelde basis `v2-main` is.

Dan mis je bestanden, gidsen en fixes — of zie je fouten zoals  
“Failed to open document… BannerCanvasDrop.swift”.

### Wat Xcode wél / niet ziet

| Wel | Niet automatisch |
|-----|------------------|
| Lokale checkout van één branch | Commits van een Cloud Agent op een andere branch |
| Bestanden die op die branch bestaan | Open PRs die nog niet gemerged zijn |
| Commits die je lokaal hebt opgehaald | Een gids/fix die alleen op een featurebranch staat |

### Herstelstappen

1. Bepaal welke versie je wilt bouwen (dagelijks: `v2-main`).
2. Ga naar de **repo-root** (de map met `docs/`, `Avatar2/`, `backend/`, `README.md` — niet alleen `Avatar2/`):
   ```bash
   cd "/pad/naar/Avatar"   # jouw lokale clone-root
   git fetch origin
   git checkout v2-main
   git pull origin v2-main
   ```
3. Open de gids vanaf de **repo-root** (niet vanuit `Avatar2/`):
   ```bash
   open docs/cursor-git-workflow-guide.html
   # of: open docs/cursor-git-workflow-guide.md
   #
   # Zit je al in Avatar2/? Dan:
   # open ../docs/cursor-git-workflow-guide.html
   ```
4. Regenereer het Xcode-project **in** `Avatar2/`:
   ```bash
   cd Avatar2
   xcodegen generate
   open *.xcodeproj
   ```
5. Clean Build Folder, opnieuw bouwen. Sluit stale tabs naar verdwenen bestanden.

**Veelvoorkomende vergissing:** je zit al in `.../Avatar2`, typt opnieuw `cd Avatar2` → `no such file`, en zoekt de gids in `Avatar2/docs/` → die map bestaat niet. De gids staat op `docs/` in de repo-root.

### Valkuil: lokale `v2-main` ≠ GitHub `v2-main`

Branchnaam `v2-main` alleen is niet genoeg. Controleer altijd de commit:

```bash
git fetch origin
git log -1 --oneline                 # wat jij lokaal hebt
git log -1 --oneline origin/v2-main  # wat op GitHub staat
```

Als die SHA’s verschillen, bouw je nog oude code — ook al zegt Xcode “v2-main”.

Typisch signaal: `git log -1` toont een lokale checkpoint zoals  
`checkpoint before checking out cursor/...` in plaats van  
`Integrate current v2 editor and menu sessions (#37)`.

**Herstel (sluit Xcode eerst):**

```bash
cd "/pad/naar/Avatar"                # repo-root
git fetch origin
git checkout v2-main
git reset --hard origin/v2-main      # zet lokale v2-main gelijk aan GitHub
git log -1 --oneline                 # moet nu gelijk zijn aan origin/v2-main
xcodegen generate
rm -rf ~/Library/Developer/Xcode/DerivedData/Avatar-*
open Avatar.xcodeproj
```

Daarna in Xcode: scheme `Avatar2` → Clean Build Folder → Run.

> `git reset --hard` gooit niet-gecommitte lokale wijzigingen op die branch weg.
> Heb je lokale bestanden die je wilt bewaren: eerst `git status` en eventueel `git stash -u`.

**Keten:** Cloud Agent → GitHub PR → jij merget → jij checkt lokaal uit → Xcode bouwt die code.

---

## Branch, commit en PR — vertaling

| Term | Betekenis |
|------|-----------|
| Branch | Tijdelijke kopie/werklijn voor één taak |
| Commit | Opgeslagen foto van de code op dat moment |
| Push | Zet lokale commits op GitHub |
| Pull request | Verzoek om een branch in de hoofdbranch op te nemen |
| Merge | Maakt de wijziging onderdeel van de gedeelde versie |
| Deploy | Zet een specifieke commit daadwerkelijk online |

---

## Zes regels die 90% van de chaos voorkomen

1. **Wijs één hoofdbranch aan** — voor v2: `v2-main`.
2. **Eén taak = één branch = één PR.**
3. **Controleer bestaand werk vóór je een agent start.**
4. **Werk niet parallel in dezelfde kernbestanden.**
5. **Label ieder bewijs met branch + commit.**
6. **Klaar = gemerged én geverifieerd** — niet alleen “PR gemaakt”.

---

## Bugfix — proces

1. Leg huidig en gewenst gedrag vast.  
2. Noteer reproductiestappen.  
3. Controleer of er al een branch/PR bestaat.  
4. Start vanaf de nieuwste hoofdbranch.  
5. Maak de kleinst mogelijke fix.  
6. Test relevante route + regressies.  
7. Commit, push, één PR.  
8. Merge; haal daarna lokaal opnieuw op.

### Prompttemplate fix

```text
Werk aan de macOS v2-app in repository Avatar.

Startpunt:
- Fetch eerst de nieuwste origin/v2-main.
- Controleer open PR's en actieve Cursor-sessies.
- Hergebruik bestaand werk als dezelfde bestanden al worden aangepast.

Bug:
- Huidig gedrag: [wat gaat fout]
- Gewenst gedrag: [wat moet gebeuren]
- Reproductie: [stappen]
- Bewijs: [screenshot + branch/commit/build]

Scope:
- Los alleen deze bug op.
- Behoud bestaande fixes.
- Test [concrete routes].
- Commit en push op één featurebranch.
- Meld branch, commit, PR, tests en resterende beperkingen.
```

---

## Feature — klein vs groot

- **Klein / duidelijk:** direct bouwen.
- **Groot / onduidelijk:** eerst plannen, daarna implementeren.

Noem acceptatiecriteria, states (loading/leeg/fout/succes), non-goals, platform en doelbranch.

---

## Meerdere Cursor-sessies

| Situatie | Advies |
|----------|--------|
| Gescheiden gebieden (backend vs docs) | Veilig parallel |
| Zelfde feature, andere lagen | Interfaces vooraf; één integratie-eigenaar |
| Zelfde view/model | **Niet** parallel — na elkaar |

**Limiet:** maximaal één actieve implementatiesessie per featuregebied.

---

## Advies voor deze repository (tijdens v2)

- Gebruik `v2-main` als enige integratiebasis voor `Avatar2/`.
- Laat v2-feature-PRs uitsluitend naar `v2-main` wijzen.
- Start afhankelijke taken pas na merge van de vorige PR.
- Bij parallel werk: één integratiebranch + één eigenaar.
- Behandel Vercel niet als bewijs voor de macOS-UI.
- Zet niet zomaar `v2-main` over `main`.

Huidige canonieke integratie: **PR #37** (`cursor/unify-menu-containers-7e40`).  
PR #38 (Enhance/Adjust) zit daar al in — niet apart mergen.

---

## Korte checklist

- [ ] Ik weet welke hoofdbranch geldt.
- [ ] Ik heb eerst remote updates opgehaald.
- [ ] Ik heb open PR’s en sessies gecontroleerd.
- [ ] Mijn taak heeft één branch en één PR.
- [ ] Ik snap dat een Cloud Agent-PR nog niet in Xcode zit.
- [ ] Mijn Xcode-branchkiezer toont precies de branch die ik wil bouwen.
- [ ] Mijn branch raakt geen parallel beheerde kernbestanden.
- [ ] Elke screenshot noemt branch en commit.
- [ ] Ik weet wat Vercel wel en niet test.
- [ ] Ik heb relevant gedrag getest.
- [ ] De PR is mergebaar en beoordeeld.
- [ ] Na merge heb ik de hoofdbranch opnieuw opgehaald en Xcode heropend.

**Klaar betekent: gemerged, opgehaald en geverifieerd** — niet alleen “de agent heeft een commit gemaakt”.
