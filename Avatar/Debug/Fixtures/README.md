# Subject-Lift edge benchmark fixtures

Drop any portrait photos here (JPG / PNG / HEIC / AVIF / WebP). **Naming and
curation are optional** — the harness picks up everything in this folder, sorts the output
PNGs by source filename, and runs both V1 and V2 on each.

The folder is intentionally **empty in git** — fixture portraits are private
and would balloon the repo. Each developer maintains their own local set.
A `.gitignore` keeps the photos out; only this README is tracked.

## Running the benchmark

In a Debug build of the app:

- **First run** triggers an OS file picker because the app is sandboxed —
  point it at this folder (or any folder of portraits). macOS hands the
  app a security-scoped bookmark so subsequent runs read the same folder
  without re-prompting. Use **Debug → Choose Fixtures Folder…** to re-pick
  later (e.g. after moving the worktree).
- **Debug → Run Subject-Lift Benchmark (Quick — 5 Random)** — 5 random
  fixtures, ~10–30s. Use this while iterating on a V2 parameter.
- **Debug → Run Subject-Lift Benchmark (Full)** — every fixture in the
  folder, ~1–3 min for ~25 photos. Use to confirm a candidate generalises
  before flipping `subjectLiftV2` on by default.
- **Debug → Open Latest Benchmark Folder** — re-opens the most recent run.

Output lands inside the app's sandbox container at
`~/Library/Containers/com.aaavatar.Avatar/Data/Library/Application Support/EdgeBench/edge-bench-<ISO8601>/`
and Finder reveals it automatically when the run completes:
- `00-summary.csv` — header, summary row (averages), then one row per fixture
  with V1 ms, V2 ms, ratio, and ok flags.
- `<source>-v1-cutout.png`, `<source>-v2-cutout.png` — raw cutouts.
- `<source>-side-by-side.png` — six panels: V1 (top row) / V2 (bottom row)
  composited over light grey, dark grey, and a busy backdrop. Hair-edge
  defects only show against backdrops that contrast with the original photo.

## Useful patterns to include

You don't need all of these — even five varied portraits expose most of the
edge-quality gaps. But if you want a representative set:

- Blonde hair on light background (fringe test).
- Dark hair on dark background (silhouette clipping).
- Curly / textured hair with flyaways.
- Long hair past the shoulders (V1's radial-gradient hair zone misses this).
- Side ponytail / asymmetric hair (V1 ignores hair outside the crown ellipse).
- Glasses with hair strands across them.
- A clean studio shot — control, **must not regress**.
- A small input (<1500 px long edge) and a large one (>4 K) to exercise the
  V2 adaptive resize.

## Override location

Setting `AVATAR_BENCH_FIXTURES=/some/abs/path` makes the benchmark read from
that folder instead of this one. Useful when iterating on fixtures that live
outside the repo.
