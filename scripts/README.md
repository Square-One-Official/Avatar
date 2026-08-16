# Avatar / scripts

One-shot dev tooling that doesn't ship in the app bundle.

## GTM go-live

```bash
# Unauthenticated production smokes (no Stripe sessions, no credits)
./scripts/prod-gtm-smoke.sh

# Structuur-check voor het v2-releasekanaal (geen Xcode)
./scripts/release-v2.sh --check

# Eerste signed beta — alleen op de Mac, als GitHub PRERELEASE
./scripts/release-v2.sh 2.0.0 101
```

v1 blijft `./scripts/release.sh`. Die bumpt alleen het root-versieblok; Avatar2 heeft eigen 2.0.0/100-overrides.

## TL;DR — get the downloadable matting model live

```bash
# 1. Activate venv (re-use the one you set up earlier)
source ../.venv/bin/activate
pip install -r scripts/requirements-coreml.txt

# 2. Convert ORMBG from PyTorch to CoreML fp16 (5-15 min, mostly download)
python3 scripts/convert_ormbg_to_coreml.py

# 3. Publish — the script prints the exact command at the end
gh release create models/matting-v1 \
  build/matting/matting-model.mlmodelc.zip \
  --title "Matting model v1 (ORMBG)" \
  --notes "ORMBG, CoreML fp16, 1024x1024, Apache 2.0" \
  --repo thierrzz/Avatar

# 4. Tell me the SHA-256 (printed by the script + saved in
#    build/matting/matting-model.mlmodelc.zip.sha256), and I'll plumb it
#    into ModelManager.expectedSHA256.
```

## Why ORMBG (and not BiRefNet, IS-Net, RMBG, MODNet, withoutBG, ZIM)

We went through every realistic candidate. The ones that survive the
"open + commercial-clean + CoreML-ready + better than Apple Vision V2"
filter are vanishingly few:

| Model | Year | License | CoreML | Verdict |
|---|---|---|---|---|
| **ORMBG** | **2024** | **Apache 2.0** | Convert from PyTorch (clean) | ✅ **Picked** |
| IS-Net (DIS) | 2022 | Apache 2.0 | Prebuilt | ⚠️ Older + general-purpose |
| BiRefNet | 2024 | MIT | ❌ `deform_conv2d` | Blocked |
| BiRefNet-HR | 2025 | MIT | ❌ same op | Blocked |
| RMBG-1.4/2.0 | 2024 | **CC-BY-NC** | Prebuilt | ❌ Non-commercial |
| MODNet (PPM) | 2022 | **CC-BY-NC-SA** | Conversion script | ❌ Non-commercial |
| Robust Video Matting | 2021 | **CC-BY-NC** | Prebuilt | ❌ Non-commercial |
| BackgroundMattingV2 | 2021 | MIT | Manual | ❌ Needs background frame |
| BEN2 | 2024 | base open / **paid commercial** | ❌ | ❌ Paid for commercial |
| withoutBG | 2025 | Apache 2.0 | None — multi-stage pipeline | ⚠️ ~141 MB, complex |
| ZIM | 2025 | **CC-BY-NC 4.0** | Convertible | ❌ Non-commercial |

**ORMBG specifically wins because:**

1. **Apache 2.0** for both code and weights — no license carve-outs, no
   commercial restrictions. (RMBG-1.4 is what ORMBG deliberately re-
   implements as an open clone.)
2. **DIS-family architecture**, no `deform_conv2d` — the op that
   blocked BiRefNet conversion. ORMBG uses only standard convolutions.
3. **Portrait-specialized**: trained on P3M-10K + AIM-500 + PPM-100 +
   10k synthetic portraits. IS-Net-General-Use is general-purpose;
   ORMBG's training distribution matches our production input
   (people importing portraits).
4. **2 years newer than IS-Net** with significantly better matting data.
5. **~88 MB at fp16** — half the size of IS-Net's prebuilt CoreML.
6. **F1 = 0.9932, MAE = 0.008** on the author's eval (July 2024).

## `convert_ormbg_to_coreml.py`

Snapshots `schirrmacher/ormbg` from Hugging Face (just the weights +
architecture code, ~100 MB skipping training/dataset folders), loads
the PyTorch checkpoint, traces at 1024×1024, converts to fp16 CoreML
targeting macOS 14, compiles to `.mlmodelc`, zips, prints the SHA.

Bakes ImageNet normalization into the model's preprocessing so the
Swift caller can pass a plain RGB `CVPixelBuffer` without preprocessing.

```bash
python3 scripts/convert_ormbg_to_coreml.py
```

The architecture import is defensive — if upstream renames the module
again, edit `KNOWN_MODEL_IMPORTS` at the top of the script and re-run.

## `repackage_matting_model.py`

Generic alternative path for any prebuilt `.mlmodel` / `.mlpackage`.
Compiles + zips + hashes whatever you hand it. Stdlib-only, no PyTorch
deps. Use this if a future model ships as prebuilt CoreML and we want
to repackage without going through PyTorch:

```bash
python3 scripts/repackage_matting_model.py \
  --input ~/Downloads/some-other-matting-model.mlmodel
```

## `convert_birefnet_to_coreml.py` (deprecated)

Aborts with an error pointing at the ORMBG script. Kept as a working
reference for if/when coremltools adds `torchvision::deform_conv2d`
support — at that point delete the abort block at the top of `main()`
and BiRefNet becomes available again.

## Publishing

```bash
gh release create models/matting-v1 \
  build/matting/matting-model.mlmodelc.zip \
  --title "Matting model v1 (ORMBG)" \
  --notes "ORMBG, CoreML fp16, 1024x1024, Apache 2.0" \
  --repo thierrzz/Avatar
```

Tags follow `models/matting-vN` and act as permanent version pins —
**never reuse a tag.** Bump (`-v2`, `-v3`, …) on every model swap so
`ModelManager`'s sidecar version check invalidates older caches
correctly.

## Updating Swift

In `Avatar/Services/ModelManager.swift`:
- `modelURL` — point at the new release asset URL (already targets
  `models/matting-v1` from the previous pivot).
- `expectedSHA256` — paste from `build/matting/matting-model.mlmodelc.zip.sha256`.
- `modelVersion` — bump if cached older copies need invalidating.

The on-disk model directory name (`matting-model.mlmodelc`) is engine-
agnostic — no Swift change needed when swapping models, only a new
release upload + SHA constant update.
