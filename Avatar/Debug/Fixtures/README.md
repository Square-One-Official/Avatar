# Subject-Lift edge benchmark fixtures

Drop curated portrait photos here (JPG / PNG / HEIC). The Debug → Run
Subject-Lift Benchmark menu item picks them up, runs both V1 and V2 of
`ImageProcessor.subjectLift`, and writes a side-by-side PNG plus timings
to `~/Desktop/edge-bench-<timestamp>/`.

The folder is intentionally **empty in git** — fixture portraits are private
and would balloon the repo. Each developer maintains their own local set.
A `.gitignore` keeps the photos out; only this README is tracked.

## Suggested fixture set

Aim for ~20 portraits that span the failure modes Subject-Lift actually has.
Name files so the result PNGs sort the way you want to scan them:

```
01-blonde-on-white.jpg          # blonde hair vs white wall — fringe test
02-blonde-on-busy.jpg
03-dark-on-dark.jpg             # silhouette clipping
04-dark-on-light.jpg
05-curly-flyaways.jpg           # Vision usually clips wisps
06-curly-busy-bg.jpg
07-long-straight-down-shoulder.jpg
08-side-ponytail.jpg            # hair zone radial gradient misses this
09-afro.jpg                     # crown ellipse not wide enough
10-braids.jpg
11-glasses-with-flyaways.jpg
12-bangs-over-eyebrows.jpg
13-translucent-hair-low-light.jpg
14-half-profile.jpg
15-clean-studio.jpg             # control — must NOT regress
16-clean-window-light.jpg       # control
17-tiny-face-large-frame.jpg    # < 1500px input — adaptive resize check
18-huge-4k-phone-portrait.jpg   # > 4K input — adaptive downsample check
19-multiple-people.jpg          # instance mask multi-handling
20-hat-with-hair-below.jpg
```

## Override location

Setting the env var `AVATAR_BENCH_FIXTURES=/some/abs/path` makes the
benchmark read from that folder instead. Useful when iterating on
fixtures that live outside the repo.
