#!/usr/bin/env python3
"""
Convert BiRefNet_lite-matting (ZhengPeng7/BiRefNet_lite-matting) to a fp16
CoreML .mlpackage at 1024x1024 fixed input, then compile to .mlmodelc and
zip for distribution as a GitHub release asset.

Why BiRefNet_lite-matting (vs alternatives):
- ~90 MB fp16 (Swin-Tiny backbone, ~44.4M params), well under our 200 MB
  download budget.
- MIT license — clean for a paid macOS app. RMBG-1.4/2.0, MODNet PPM
  weights, and Robust Video Matting are all non-commercial; ruled out.
- Trained for matting (continuous α at hair edges), so it produces real
  alpha — Apple Vision can't.

Why this script doesn't try to be too smart:
- coremltools converters are version-sensitive and BiRefNet's Swin
  attention has known CoreML 7 ANE op-coverage gaps. This script
  targets the path most likely to work today (PyTorch trace -> ct.convert
  with FLOAT16 precision); if you hit ANE dispatch issues, the runner-up
  is IS-Net/DIS from john-rocky/CoreML-Models — prebuilt 176 MB mlmodel,
  Apache-2.0, drop-in replacement.

Usage:

    # Recommended: dedicated venv, Apple Silicon Mac.
    python3 -m venv .venv && source .venv/bin/activate
    pip install -r scripts/requirements-coreml.txt
    python3 scripts/convert_birefnet_to_coreml.py

The script:
  1. Downloads the model weights from Hugging Face on first run
     (cached under ~/.cache/huggingface).
  2. Traces with a 1x3x1024x1024 example input.
  3. Converts to CoreML fp16 targeting macOS 14.
  4. Compiles the .mlpackage to .mlmodelc via `xcrun coremlcompiler`.
  5. Zips the .mlmodelc directory as `birefnet-lite-matting.mlmodelc.zip`
     and prints the SHA-256 of the zip — paste that into ModelManager's
     `expectedSHA256` constant before tagging the GitHub release.

After running:
  1. Create a GitHub release on thierrzz/Avatar with tag
     `models/birefnet-lite-v1` (do not reuse tags — version pin matters).
  2. Upload `birefnet-lite-matting.mlmodelc.zip` as a release asset.
  3. Update `ModelManager.modelURL` and `ModelManager.expectedSHA256` in
     Avatar/Services/ModelManager.swift to point at the new asset.

Output files (created in `build/birefnet/`):
  - birefnet-lite-matting.mlpackage          (CoreML 7 package)
  - birefnet-lite-matting.mlmodelc/          (compiled, runtime-ready)
  - birefnet-lite-matting.mlmodelc.zip       (upload to GitHub release)
  - birefnet-lite-matting.mlmodelc.zip.sha256 (paste into Swift)
"""
from __future__ import annotations

import hashlib
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

BUILD_DIR = Path("build/birefnet")
MODEL_NAME = "birefnet-lite-matting"
HF_REPO = "ZhengPeng7/BiRefNet_lite-matting"
INPUT_SIZE = 1024  # square; BiRefNet trained at 1024x1024


def main() -> None:
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    mlpackage_path = BUILD_DIR / f"{MODEL_NAME}.mlpackage"

    if mlpackage_path.exists():
        print(f"[skip-convert] reusing existing {mlpackage_path}")
    else:
        convert_to_mlpackage(mlpackage_path)

    mlmodelc_path = BUILD_DIR / f"{MODEL_NAME}.mlmodelc"
    if mlmodelc_path.exists():
        shutil.rmtree(mlmodelc_path)
    compile_to_mlmodelc(mlpackage_path, mlmodelc_path)

    zip_path = BUILD_DIR / f"{MODEL_NAME}.mlmodelc.zip"
    if zip_path.exists():
        zip_path.unlink()
    zip_directory(mlmodelc_path, zip_path)

    sha = sha256_of(zip_path)
    sha_path = zip_path.with_suffix(".zip.sha256")
    sha_path.write_text(f"{sha}  {zip_path.name}\n")

    print()
    print(f"✓ Built {zip_path}  ({zip_path.stat().st_size / 1_048_576:.1f} MB)")
    print(f"  SHA-256: {sha}")
    print()
    print("Next steps:")
    print(f"  1. Create GH release: gh release create models/birefnet-lite-v1 \\")
    print(f"       {zip_path} --title 'BiRefNet lite-matting v1' \\")
    print(f"       --notes 'CoreML fp16, 1024x1024, MIT licensed' --repo thierrzz/Avatar")
    print("  2. Update ModelManager.modelURL + expectedSHA256 in Swift.")


def convert_to_mlpackage(out: Path) -> None:
    """Trace the PyTorch model and convert to fp16 CoreML."""
    import torch
    import coremltools as ct
    from transformers import AutoModelForImageSegmentation

    print(f"[1/3] Loading {HF_REPO} (cached at ~/.cache/huggingface)…")
    model = AutoModelForImageSegmentation.from_pretrained(
        HF_REPO, trust_remote_code=True
    )
    model.eval()

    print(f"[1/3] Tracing with example input 1x3x{INPUT_SIZE}x{INPUT_SIZE}…")
    example = torch.rand(1, 3, INPUT_SIZE, INPUT_SIZE)
    # BiRefNet's forward signature varies between revisions; some return a
    # tuple of (predictions, intermediate). Wrap to expose a single tensor
    # — the alpha matte — so CoreML's converter doesn't choke on the tuple.
    class AlphaOnly(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, x):
            out = self.m(x)
            # Empirically the matte tensor is `out[0][-1]` for the released
            # checkpoints. If conversion fails here, print(out) to inspect
            # and adjust this line — varies across BiRefNet revisions.
            if isinstance(out, (tuple, list)):
                inner = out[0]
                if isinstance(inner, (tuple, list)):
                    return torch.sigmoid(inner[-1])
                return torch.sigmoid(inner)
            return torch.sigmoid(out)

    wrapped = AlphaOnly(model).eval()
    traced = torch.jit.trace(wrapped, example, strict=False)

    print("[2/3] Converting traced model -> CoreML fp16 mlpackage…")
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(
            name="input",
            shape=(1, 3, INPUT_SIZE, INPUT_SIZE),
            # ImageNet normalization. Bake into scale/bias so the Swift
            # caller can pass a plain CVPixelBuffer (RGB 0-255) without
            # pre-normalizing. scale = 1/(255*std), bias = -mean/std.
            scale=1.0 / (0.229 * 255.0),
            bias=[
                -0.485 / 0.229,
                -0.456 / 0.224,
                -0.406 / 0.225,
            ],
            color_layout=ct.colorlayout.RGB,
        )],
        outputs=[ct.TensorType(name="alpha")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS14,
        convert_to="mlprogram",
    )

    mlmodel.short_description = "BiRefNet lite-matting (Swin-T, 1024x1024 fp16)"
    mlmodel.author = "ZhengPeng7 (BiRefNet) — converted by Avatar"
    mlmodel.license = "MIT"
    mlmodel.version = "1.0"
    mlmodel.input_description["input"] = "RGB 1024x1024 image"
    mlmodel.output_description["alpha"] = "Alpha matte 1x1024x1024 (sigmoid)"

    mlmodel.save(str(out))
    print(f"      saved: {out}")


def compile_to_mlmodelc(mlpackage: Path, out_dir: Path) -> None:
    """Compile mlpackage -> mlmodelc via Xcode's coremlcompiler."""
    print("[3/3] Compiling mlpackage -> mlmodelc (xcrun coremlcompiler)…")
    out_dir.parent.mkdir(parents=True, exist_ok=True)
    # `compile` writes to <output_dir>/<basename>.mlmodelc — pass the parent
    # directory and rename if the resulting basename doesn't match.
    parent = out_dir.parent
    subprocess.run(
        ["xcrun", "coremlcompiler", "compile", str(mlpackage), str(parent)],
        check=True,
    )
    produced = parent / mlpackage.with_suffix(".mlmodelc").name
    if produced != out_dir and produced.exists():
        produced.rename(out_dir)
    print(f"      compiled: {out_dir}")


def zip_directory(directory: Path, out: Path) -> None:
    """Zip the .mlmodelc directory preserving relative paths."""
    print(f"      zipping -> {out.name}…")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for path in sorted(directory.rglob("*")):
            arcname = path.relative_to(directory.parent)
            zf.write(path, arcname)


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
