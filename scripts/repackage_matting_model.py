#!/usr/bin/env python3
"""
Compile, zip, and SHA-256 an existing CoreML matting model so it's ready
to upload as a GitHub release asset and consumed by `ModelManager` in
the Swift app.

Why this script exists (and why it's not a converter):
- We initially planned to convert BiRefNet_lite-matting from PyTorch
  via coremltools. Conversion fails on `torchvision::deform_conv2d` —
  BiRefNet's ASPP decoder uses deformable convolutions and coremltools
  has no converter for that op. The plan flagged this risk and named
  IS-Net (DIS) as the runner-up: Apache 2.0, prebuilt CoreML, hair
  quality clearly above Apple Vision, ~176 MB.
- IS-Net is hosted on Google Drive in `john-rocky/CoreML-Models`. We
  can't redistribute their `.mlmodel` directly inside the source tree,
  but the Apache-2.0 license is fine for repackaging into our own
  GitHub release once the dev (you) downloads the asset.

Usage:

    # 1. Download IS-Net from john-rocky/CoreML-Models manually:
    #    https://github.com/john-rocky/CoreML-Models#is-net
    #    (Click the "IS-Net" or "IS-Net-General-Use" link, save the
    #    .mlmodel into ~/Downloads/ or anywhere convenient.)
    #
    # 2. Run this script with the path to the downloaded model:
    python3 scripts/repackage_matting_model.py \\
        --input ~/Downloads/IS-Net-General-Use.mlmodel

The script:
  1. Compiles the input `.mlmodel` / `.mlpackage` via
     `xcrun coremlcompiler` to a `matting-model.mlmodelc` directory.
  2. Zips that directory.
  3. Prints the SHA-256 of the zip — paste into ModelManager's
     `expectedSHA256` constant.
  4. Prints the `gh release create` command to publish.

Output (in `build/matting/`):
  - matting-model.mlmodelc/                    (compiled, runtime-ready)
  - matting-model.mlmodelc.zip                 (upload to GitHub release)
  - matting-model.mlmodelc.zip.sha256          (paste hex into Swift)

Why "matting-model.mlmodelc" instead of the upstream filename:
  Keeps the on-disk path inside `ModelManager` stable across model
  swaps. If a future coremltools release adds deform_conv2d support
  and we re-pivot to BiRefNet — or if IS-Net is replaced by something
  better — the Swift constant doesn't move, only the model bytes.
"""
from __future__ import annotations

import argparse
import hashlib
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

BUILD_DIR = Path("build/matting")
MODEL_NAME = "matting-model"
RELEASE_TAG = "models/matting-v1"
GH_REPO = "Square-One-Official/Avatar"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compile + zip + hash a CoreML matting model for distribution."
    )
    parser.add_argument(
        "--input", "-i", type=Path, required=True,
        help="Path to the .mlmodel or .mlpackage to repackage. "
             "For IS-Net, download from "
             "https://github.com/john-rocky/CoreML-Models#is-net first."
    )
    args = parser.parse_args()

    src: Path = args.input.expanduser().resolve()
    if not src.exists():
        sys.exit(f"error: input not found: {src}")
    if src.suffix not in (".mlmodel", ".mlpackage"):
        sys.exit(f"error: expected .mlmodel or .mlpackage, got {src.suffix}")

    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    mlmodelc = BUILD_DIR / f"{MODEL_NAME}.mlmodelc"
    if mlmodelc.exists():
        shutil.rmtree(mlmodelc)
    compile_to_mlmodelc(src, mlmodelc)

    zip_path = BUILD_DIR / f"{MODEL_NAME}.mlmodelc.zip"
    if zip_path.exists():
        zip_path.unlink()
    zip_directory(mlmodelc, zip_path)

    sha = sha256_of(zip_path)
    sha_path = zip_path.with_suffix(".zip.sha256")
    sha_path.write_text(f"{sha}  {zip_path.name}\n")

    size_mb = zip_path.stat().st_size / 1_048_576
    print()
    print(f"✓ Built {zip_path}  ({size_mb:.1f} MB)")
    print(f"  SHA-256: {sha}")
    print()
    print("Next steps:")
    print(f"  1. Update ModelManager.swift:")
    print(f"       expectedSHA256 = \"{sha}\"")
    print(f"       modelURL       = …/releases/download/{RELEASE_TAG}/{zip_path.name}")
    print(f"  2. Publish:")
    print(f"     gh release create {RELEASE_TAG} \\")
    print(f"       {zip_path} \\")
    print(f"       --title 'Matting model v1 (IS-Net)' \\")
    print(f"       --notes 'IS-Net DIS, CoreML, 1024x1024, Apache 2.0' \\")
    print(f"       --repo {GH_REPO}")


def compile_to_mlmodelc(model: Path, out_dir: Path) -> None:
    """Compile mlmodel/mlpackage -> mlmodelc via Xcode's coremlcompiler."""
    print(f"[1/2] Compiling {model.name} -> {out_dir.name}…")
    parent = out_dir.parent
    parent.mkdir(parents=True, exist_ok=True)

    # `compile <model> <out-dir>` writes <out-dir>/<basename>.mlmodelc
    # The basename is taken from the source file, which we can't always
    # control — rename to our canonical `matting-model.mlmodelc` after.
    subprocess.run(
        ["xcrun", "coremlcompiler", "compile", str(model), str(parent)],
        check=True,
    )
    produced = parent / f"{model.stem}.mlmodelc"
    if produced != out_dir:
        if out_dir.exists():
            shutil.rmtree(out_dir)
        produced.rename(out_dir)
    print(f"      compiled: {out_dir}")


def zip_directory(directory: Path, out: Path) -> None:
    """Zip the .mlmodelc directory preserving relative paths."""
    print(f"[2/2] Zipping -> {out.name}…")
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
