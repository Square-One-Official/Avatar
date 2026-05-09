# Avatar / scripts

One-shot dev tooling that doesn't ship in the app bundle.

## `convert_birefnet_to_coreml.py`

Converts the open-source `ZhengPeng7/BiRefNet_lite-matting` PyTorch model
to a fp16 CoreML `.mlmodelc` and zips it for distribution as a GitHub
release asset. Run on **Apple Silicon Mac with Xcode installed** — the
script invokes `xcrun coremlcompiler` for the final compile step.

### Why we ship this

Apple Vision (V2) does most portraits well. It can't fully clean up
hair-edge bleed on hard cases — long flowing hair, curly flyaways
against contrasting backgrounds — because Vision is a *segmentation*
network producing near-binary alpha. BiRefNet_lite-matting is a *matting*
network: continuous α at hair edges, designed for the cases Vision
struggles with. ~90 MB fp16, MIT licensed, the alternatives (RMBG, MODNet
PPM weights, RVM) are all non-commercial and disqualified for a paid app.

### One-time setup

```bash
cd Avatar    # repo root
python3 -m venv .venv
source .venv/bin/activate
pip install -r scripts/requirements-coreml.txt
```

### Run

```bash
python3 scripts/convert_birefnet_to_coreml.py
```

Output (in `build/birefnet/`):
- `birefnet-lite-matting.mlpackage` — CoreML 7 package (intermediate).
- `birefnet-lite-matting.mlmodelc/` — compiled, runtime-ready model.
- `birefnet-lite-matting.mlmodelc.zip` — upload this to the GitHub
  release.
- `birefnet-lite-matting.mlmodelc.zip.sha256` — paste this into
  `ModelManager.expectedSHA256` in Swift.

Approximate timing: 5–15 minutes on M1, mostly model download + tracing.

### Publish

```bash
gh release create models/birefnet-lite-v1 \
  build/birefnet/birefnet-lite-matting.mlmodelc.zip \
  --title "BiRefNet lite-matting v1" \
  --notes "CoreML fp16, 1024x1024, MIT licensed" \
  --repo thierrzz/Avatar
```

Then in `Avatar/Services/ModelManager.swift`:
- Update `modelURL` to the new release asset URL.
- Update `expectedSHA256` to the value from the `.zip.sha256` file.
- Bump `modelVersion` so cached older copies get invalidated.

The release tag (`models/birefnet-lite-v1`) is part of the URL and acts as
a permanent version pin — never reuse a tag, always bump (`-v2`, etc.)
when retraining or reconverting.

### Troubleshooting

**"AttributeError on `out[0][-1]`" during tracing.**
BiRefNet's forward signature varies across releases. Open the script,
find the `AlphaOnly` wrapper, and `print(out)` inside `forward` to see
the actual shape. Adjust the indexing accordingly.

**"Op not supported on ANE" warnings during convert.**
Swin attention occasionally falls off the Apple Neural Engine in some
coremltools versions. The model still runs (CPU + GPU dispatch), it's
just slower. If unacceptable, fall back to **IS-Net (DIS)** from
[`john-rocky/CoreML-Models`](https://github.com/john-rocky/CoreML-Models)
— prebuilt `.mlmodel`, Apache-2.0, ~176 MB, drop-in replacement
(matching the SHA-256/URL constants in `ModelManager`).

**`xcrun coremlcompiler` not found.**
Install Xcode (full app, not just Command Line Tools). Confirm with
`xcrun --find coremlcompiler`.
