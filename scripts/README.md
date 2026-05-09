# Avatar / scripts

One-shot dev tooling that doesn't ship in the app bundle.

## TL;DR — get the downloadable matting model live

```bash
# 1. Manual download (one-time, ~176 MB)
#    https://github.com/john-rocky/CoreML-Models#is-net
#    Click "IS-Net" or "IS-Net-General-Use", save the .mlmodel locally.

# 2. Repackage into our distribution format
python3 scripts/repackage_matting_model.py \
  --input ~/Downloads/IS-Net-General-Use.mlmodel

# 3. Publish (the script prints the exact command at the end)
gh release create models/matting-v1 \
  build/matting/matting-model.mlmodelc.zip \
  --title "Matting model v1 (IS-Net)" \
  --notes "IS-Net DIS, CoreML, 1024x1024, Apache 2.0" \
  --repo thierrzz/Avatar

# 4. Tell me the SHA-256 (printed by the script + saved in
#    build/matting/matting-model.mlmodelc.zip.sha256), and I'll plumb it
#    into ModelManager.expectedSHA256.
```

## Why IS-Net and not BiRefNet

The original plan picked **BiRefNet_lite-matting** (~90 MB fp16, MIT) as
the primary model, with **IS-Net (DIS)** flagged as a runner-up "if
BiRefNet conversion hits a wall." The wall is real:

- BiRefNet's ASPP decoder uses **deformable convolutions**
  (`torchvision::deform_conv2d`).
- coremltools 9.0 has no built-in converter for that op.
- Writing a custom converter would mean expressing deform-conv as
  gather + bilinear-sample + conv in MIL — non-trivial, would need
  per-coremltools-version maintenance, and may not dispatch cleanly to
  ANE.

IS-Net's trade-off vs BiRefNet, honestly stated:

| | IS-Net (DIS) | BiRefNet_lite-matting |
|---|---|---|
| Size | ~176 MB | ~90 MB |
| License | Apache 2.0 | MIT |
| CoreML ready | Yes (john-rocky) | Needs unblocking |
| vs Apple Vision V2 | Clearly better | Clearly better |
| vs each other on flyaways | — | Slightly better than IS-Net |

For the user's pain (long flowing hair, curly flyaways still bleed
under V2), IS-Net should bring most of the win. Crispness on the
hardest cases will be a touch behind a hypothetical BiRefNet build.
The plan called this out as the right pivot, so we're taking it.

## `repackage_matting_model.py`

Compiles an existing `.mlmodel` / `.mlpackage` to `.mlmodelc`, zips it,
and prints the SHA-256 + a ready-to-paste `gh release create` command.
No PyTorch deps required — the model is already CoreML.

Run from the repo root on an Apple Silicon Mac with Xcode installed
(needed for `xcrun coremlcompiler`). The Python deps are stdlib only —
no `requirements-coreml.txt` install needed for this path.

```bash
python3 scripts/repackage_matting_model.py \
  --input ~/Downloads/IS-Net-General-Use.mlmodel
```

Output (in `build/matting/`):
- `matting-model.mlmodelc/` — compiled, runtime-ready.
- `matting-model.mlmodelc.zip` — upload this to the GitHub release.
- `matting-model.mlmodelc.zip.sha256` — paste hex into Swift.

The on-disk name is **engine-agnostic** (`matting-model.mlmodelc`), so
swapping IS-Net for a future better model only requires re-running this
script with the new input — no Swift constants change.

## `convert_birefnet_to_coreml.py` (deprecated)

Kept for reference. Aborts with an error pointing at
`repackage_matting_model.py`. If a future coremltools release adds
`torchvision::deform_conv2d`, delete the abort block at the top of
`main()` and the rest of the script should still trace + convert. The
`requirements-coreml.txt` deps are still pinned in case we revisit.

## Publishing the release

After `repackage_matting_model.py` finishes, publish:

```bash
gh release create models/matting-v1 \
  build/matting/matting-model.mlmodelc.zip \
  --title "Matting model v1 (IS-Net)" \
  --notes "IS-Net DIS, CoreML, 1024x1024, Apache 2.0" \
  --repo thierrzz/Avatar
```

Tags follow `models/matting-vN` and act as permanent version pins —
**never reuse a tag.** Bump (`-v2`, `-v3`, …) on every model swap so
`ModelManager`'s sidecar version check invalidates older caches
correctly.

## Updating the Swift side

In `Avatar/Services/ModelManager.swift`:
- `modelURL` — point at the new release asset URL.
- `expectedSHA256` — paste from `…/matting-model.mlmodelc.zip.sha256`.
- `modelVersion` — bump so cached older copies invalidate at launch.
