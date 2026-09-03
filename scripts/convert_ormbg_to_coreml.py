#!/usr/bin/env python3
"""
Convert ORMBG (`schirrmacher/ormbg`) to a fp16 CoreML .mlpackage at
1024x1024 fixed input, then compile to .mlmodelc and zip for distribution
as a GitHub release asset.

Why ORMBG (vs the alternatives):

- **Apache 2.0** for both code and weights — RMBG-1.4 (which ORMBG
  deliberately re-trains as an open clone of) is CC-BY-NC and would
  block commercial use. ORMBG is the same idea but with open training
  data and a permissive license.
- **DIS-family architecture** (Highly Accurate Dichotomous Image
  Segmentation, He et al.). No `torchvision::deform_conv2d` — that's
  the op that blocked BiRefNet conversion in coremltools 9.0. ORMBG
  uses only standard convolutions and ResNet-style blocks, so the
  PyTorch -> CoreML path is clean.
- **Portrait-specialized**: trained on P3M-10K + AIM-500 + PPM-100 +
  10k synthetic portraits via BlenderProc. IS-Net-General-Use is
  general-purpose; for our use case (people import portraits) ORMBG's
  training distribution matches the production input.
- **Newer than IS-Net** (July 2024 vs 2022) and trained on
  significantly better portrait-matting data.
- **~88 MB at fp16** — half the size of IS-Net's ~176 MB CoreML build.

Usage:

    python3 -m venv .venv && source .venv/bin/activate
    pip install -r scripts/requirements-coreml.txt
    python3 scripts/convert_ormbg_to_coreml.py

The script:
  1. Downloads the ORMBG repo from Hugging Face (~600 MB total; cached
     under ~/.cache/huggingface) to get both the .pth checkpoint AND
     the model architecture code in one shot.
  2. Imports the architecture (defensively — the module name has
     drifted across ORMBG revisions; we try a couple of known paths
     before giving up).
  3. Loads weights and traces with a 1x3x1024x1024 example input.
  4. Converts to CoreML fp16 mlpackage targeting macOS 14.
  5. Compiles to .mlmodelc via `xcrun coremlcompiler`.
  6. Zips and SHA-256s the .mlmodelc directory.

Output (in `build/matting/`):
  - matting-model.mlpackage          (intermediate CoreML)
  - matting-model.mlmodelc/          (runtime-ready)
  - matting-model.mlmodelc.zip       (upload to GitHub release)
  - matting-model.mlmodelc.zip.sha256 (paste into Swift)

The on-disk name is engine-agnostic so a future model swap (BiRefNet
once coremltools supports deform_conv2d, or whatever's current in
2027) doesn't require changing `ModelManager`.
"""
from __future__ import annotations

import hashlib
import importlib
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

BUILD_DIR = Path("build/matting")
MODEL_NAME = "matting-model"
HF_REPO = "schirrmacher/ormbg"
INPUT_SIZE = 1024  # ORMBG's native training resolution is 1024x1024

# Known import paths for the ORMBG model class. The repo's module layout
# has drifted across commits — try each in order and use the first that
# resolves. Add new entries here if the upstream layout changes again.
KNOWN_MODEL_IMPORTS = [
    ("ormbg.ormbg", "ORMBG"),
    ("ormbg.models.ormbg", "ORMBG"),
    ("ormbg", "ORMBG"),
]


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
    print(f"  1. Update ModelManager.swift:")
    print(f"       expectedSHA256 = \"{sha}\"")
    print(f"  2. Publish:")
    print(f"     gh release create models/matting-v1 \\")
    print(f"       {zip_path} \\")
    print(f"       --title 'Matting model v1 (ORMBG)' \\")
    print(f"       --notes 'ORMBG (DIS-family), CoreML fp16, 1024x1024, Apache 2.0' \\")
    print(f"       --repo Square-One-Official/Avatar")


def convert_to_mlpackage(out: Path) -> None:
    """Trace ORMBG and convert to fp16 CoreML."""
    import torch
    import coremltools as ct
    from huggingface_hub import snapshot_download

    print(f"[1/3] Snapshotting {HF_REPO} from Hugging Face…")
    repo_dir = Path(snapshot_download(
        repo_id=HF_REPO,
        # Skip the dataset / examples / training images — we only need
        # weights + architecture code. Saves ~250 MB of downloads.
        allow_patterns=[
            "models/*.pth",
            "ormbg/**/*.py",
            "ormbg/*.py",
            "*.py",
        ],
    ))
    print(f"      cached at: {repo_dir}")

    # Add the repo root to sys.path so we can import the architecture
    # exactly the way the repo's own scripts do.
    sys.path.insert(0, str(repo_dir))

    print("[1/3] Resolving ORMBG architecture import…")
    model_cls = None
    last_err: Exception | None = None
    for module_name, class_name in KNOWN_MODEL_IMPORTS:
        try:
            module = importlib.import_module(module_name)
            model_cls = getattr(module, class_name, None)
            if model_cls is not None:
                print(f"      using {module_name}.{class_name}")
                break
        except Exception as e:  # pragma: no cover — diagnostic path
            last_err = e
    if model_cls is None:
        sys.exit(
            "error: couldn't import the ORMBG model class. The upstream\n"
            "       repo layout may have changed since this script was\n"
            "       written. Inspect the cached repo at:\n"
            f"         {repo_dir}\n"
            "       and add the correct (module, class) tuple to\n"
            "       KNOWN_MODEL_IMPORTS at the top of this script.\n"
            f"       Last import error: {last_err}"
        )

    print("[1/3] Loading weights from models/ormbg.pth…")
    checkpoint_path = repo_dir / "models" / "ormbg.pth"
    if not checkpoint_path.exists():
        sys.exit(f"error: missing checkpoint {checkpoint_path}")

    model = model_cls()
    state = torch.load(checkpoint_path, map_location="cpu", weights_only=True)
    # Some DIS-family checkpoints wrap state under a top-level key. Try
    # plain dict first, then unwrap if needed.
    if isinstance(state, dict) and "state_dict" in state and not any(
        k.startswith(("conv", "bn", "stage")) for k in state.keys()
    ):
        state = state["state_dict"]
    missing, unexpected = model.load_state_dict(state, strict=False)
    if missing:
        print(f"      load_state_dict missing keys: {len(missing)} (first few: {missing[:3]})")
    if unexpected:
        print(f"      load_state_dict unexpected keys: {len(unexpected)} (first few: {unexpected[:3]})")
    model.eval()

    print(f"[1/3] Tracing with example input 1x3x{INPUT_SIZE}x{INPUT_SIZE}…")
    example = torch.rand(1, 3, INPUT_SIZE, INPUT_SIZE)

    # DIS-family models return logits (BCEWithLogitsLoss training), not
    # sigmoid'd probabilities. ORMBG's official `inference.py` takes
    # `result[0][0]` and applies *min-max normalisation* to map it into
    # [0, 1] — sigmoid alone is wrong here because the logit range is
    # narrow enough that sigmoid compresses everything towards 0.5,
    # producing the "ghost / half-transparent everywhere" matte we hit
    # on the previous build. Mirror the official postprocess inside the
    # traced graph so CoreML's output is already in [0, 1] and Swift
    # doesn't need to know about it.
    class AlphaOnly(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, x):
            out = self.m(x)
            # Drill down to the highest-resolution matte tensor.
            # ORMBG returns `(side_outputs, intermediate_features)` where
            # `side_outputs[0]` is the full-res matte (per `inference.py`).
            if isinstance(out, (tuple, list)):
                inner = out[0]
                if isinstance(inner, (tuple, list)):
                    m = inner[0]
                else:
                    m = inner
            else:
                m = out

            # Per-image min-max normalisation. `m.shape == [B, 1, H, W]`
            # for ORMBG; flatten to [B, H*W] so the reduce ops cover the
            # whole spatial extent at once, then broadcast back.
            b = m.shape[0]
            flat = m.reshape(b, -1)
            mi = flat.min(dim=1, keepdim=True).values.reshape(b, 1, 1, 1)
            ma = flat.max(dim=1, keepdim=True).values.reshape(b, 1, 1, 1)
            # `+ 1e-6` guards against the (theoretical) flat-output case
            # where every pixel has the same value — without it the
            # divide would produce NaN and the CoreML loader would fail.
            return (m - mi) / (ma - mi + 1e-6)

    wrapped = AlphaOnly(model).eval()
    with torch.no_grad():
        traced = torch.jit.trace(wrapped, example, strict=False)

    print("[2/3] Converting traced model -> CoreML fp16 mlpackage…")
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(
            name="input",
            shape=(1, 3, INPUT_SIZE, INPUT_SIZE),
            # ORMBG's preprocessing (per ormbg/inference.py and
            # data_loader_cache.py) is a plain `x / 255.0` — NO ImageNet
            # mean/std subtraction. Earlier conversions baked ImageNet
            # normalisation in by mistake; the model then received data
            # in a distribution it was never trained on and produced a
            # smudgy ghost-like matte. `scale = 1/255, bias = [0, 0, 0]`
            # matches what ORMBG actually expects and lets the Swift
            # caller hand over a plain 0-255 RGB pixel buffer.
            scale=1.0 / 255.0,
            bias=[0.0, 0.0, 0.0],
            color_layout=ct.colorlayout.RGB,
        )],
        outputs=[ct.TensorType(name="alpha")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS14,
        convert_to="mlprogram",
    )

    mlmodel.short_description = "ORMBG (DIS-family, 1024x1024 fp16)"
    mlmodel.author = "schirrmacher (ORMBG) — converted by Avatar"
    mlmodel.license = "Apache 2.0"
    mlmodel.version = "1.0"
    mlmodel.input_description["input"] = "RGB 1024x1024 image"
    mlmodel.output_description["alpha"] = "Alpha matte 1x1x1024x1024 (sigmoid)"

    mlmodel.save(str(out))
    print(f"      saved: {out}")


def compile_to_mlmodelc(mlpackage: Path, out_dir: Path) -> None:
    """Compile mlpackage -> mlmodelc via Xcode's coremlcompiler."""
    print("[3/3] Compiling mlpackage -> mlmodelc (xcrun coremlcompiler)…")
    parent = out_dir.parent
    parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["xcrun", "coremlcompiler", "compile", str(mlpackage), str(parent)],
        check=True,
    )
    produced = parent / mlpackage.with_suffix(".mlmodelc").name
    if produced != out_dir and produced.exists():
        if out_dir.exists():
            shutil.rmtree(out_dir)
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
