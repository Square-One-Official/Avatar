#!/usr/bin/env python3
"""
Bakeoff: local Qwen-Image-Edit vs production gpt-image-1.5 on Avatar Effects.

One-shot spike — does not ship in the app bundle, does not touch the Xcode
target. Goal is a visual contact sheet so we can decide go/no-go on wiring
a downloadable instruction-edit model into local-only mode.

Prompts are copied 1-op-1 from `backend/api/v1/stylize.ts` (`STYLE_PROMPTS`
+ `IDENTITY_CLAUSE`, E09.1 bakeoff winner). Do not "improve" them here.

Usage:

    uv venv --python 3.12 build/bakeoff-local-effects/.venv
    source build/bakeoff-local-effects/.venv/bin/activate
    uv pip install -r scripts/requirements-local-effects.txt
    python3 scripts/bakeoff-local-effects.py

Input defaults to `Avatar/Debug/Fixtures` (gitignored portraits). Output
lands in `build/bakeoff-local-effects/` (also gitignored):

    prepared/{stem}.png              flattened + resized RGB
    {stem}-{style}-qwen.png          local Qwen-Image-Edit
    {stem}-{style}-nano.png          gpt-image-1.5, if cloud arm ran
    index.html                       contact sheet + scoring form
    metrics.json                     wall-clock, peak RSS, hardware
    VERDICT.md                       go/no-go template (fill after scoring)

Optional gpt-image-1.5 column:
  --cloud-dir DIR     pre-rendered `{stem}-{style}-nano.png` files
  REPLICATE_API_TOKEN live Replicate calls to `openai/gpt-image-1.5`
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import threading
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from html import escape
from pathlib import Path
from typing import Iterable

# ---------------------------------------------------------------------------
# Prompts — 1-op-1 from backend/api/v1/stylize.ts (E09.1 / E09.2)
# ---------------------------------------------------------------------------

IDENTITY_CLAUSE = (
    "Keep the person's facial features, expression, hairstyle and clothing "
    "clearly recognizable so the person remains identifiable."
)

STYLE_PROMPTS: dict[str, str] = {
    "clay": (
        "Transform this portrait into a claymation-style clay sculpture "
        "character: smooth modelling-clay skin with subtle hand-sculpted "
        "texture, soft studio lighting. " + IDENTITY_CLAUSE
    ),
    "wood": (
        "Transform this portrait into a hand-carved wooden figurine: "
        "visible wood grain, warm natural wood tones, slightly stylized "
        "carving. " + IDENTITY_CLAUSE
    ),
    "3d": (
        "Transform this portrait into a stylized 3D animated-film character "
        "render: soft skin shading, subtle subsurface scattering, gentle "
        "exaggeration of features. " + IDENTITY_CLAUSE
    ),
    "scribble": (
        "Transform this portrait into a loose hand-drawn scribble "
        "illustration: expressive sketchy ink lines, minimal flat colour "
        "accents, plain light background. " + IDENTITY_CLAUSE
    ),
}

STYLE_ORDER = ("clay", "wood", "3d", "scribble")

# Same grey as backend/lib/image.ts flattenOnGrey.
GREY = (200, 200, 200)

DEFAULT_MODEL = "AbstractFramework/qwen-image-edit-2511-4bit"
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff"}
REPO_ROOT = Path(__file__).resolve().parent.parent


# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------


@dataclass
class Hardware:
    chip: str
    mem_bytes: int
    mem_gb: float
    arch: str
    python: str
    mlxgen: str | None
    apple_silicon: bool


@dataclass
class CellMetric:
    stem: str
    style: str
    arm: str  # "qwen" | "nano"
    seconds: float | None = None
    peak_rss_mb: float | None = None
    output: str | None = None
    skipped: str | None = None
    error: str | None = None


@dataclass
class RunMetrics:
    started_at: str
    finished_at: str | None = None
    model: str = DEFAULT_MODEL
    steps: int = 20
    guidance: float = 4.0
    seed: int = 42
    max_edge: int = 768
    hardware: dict = field(default_factory=dict)
    model_bytes: int | None = None
    portraits: list[str] = field(default_factory=list)
    cells: list[dict] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Hardware / deps
# ---------------------------------------------------------------------------


def _sysctl(name: str) -> str:
    try:
        return subprocess.check_output(["sysctl", "-n", name], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def probe_hardware(mlxgen: str | None) -> Hardware:
    mem_raw = _sysctl("hw.memsize")
    try:
        mem_bytes = int(mem_raw)
    except ValueError:
        mem_bytes = 0
    chip = _sysctl("machdep.cpu.brand_string") or platform.processor() or "unknown"
    arch = platform.machine()
    mlxgen_ver = None
    if mlxgen:
        try:
            mlxgen_ver = subprocess.check_output(
                [mlxgen, "--version"], text=True, stderr=subprocess.STDOUT
            ).strip()
        except (OSError, subprocess.CalledProcessError) as exc:
            mlxgen_ver = f"(version failed: {exc})"
    return Hardware(
        chip=chip,
        mem_bytes=mem_bytes,
        mem_gb=round(mem_bytes / (1024**3), 1) if mem_bytes else 0.0,
        arch=arch,
        python=sys.version.split()[0],
        mlxgen=mlxgen_ver,
        apple_silicon=arch == "arm64",
    )


def resolve_mlxgen(explicit: str | None) -> str:
    if explicit:
        path = Path(explicit).expanduser()
        if not path.exists():
            raise SystemExit(f"--mlxgen not found: {path}")
        return str(path)
    found = shutil.which("mlxgen")
    if found:
        return found
    raise SystemExit(
        "mlxgen not on PATH. Install with:\n"
        "  uv venv --python 3.12 build/bakeoff-local-effects/.venv\n"
        "  source build/bakeoff-local-effects/.venv/bin/activate\n"
        "  uv pip install -r scripts/requirements-local-effects.txt"
    )


def load_replicate_token() -> str | None:
    token = os.environ.get("REPLICATE_API_TOKEN", "").strip()
    if token:
        return token
    env_path = REPO_ROOT / "backend" / ".env"
    if not env_path.is_file():
        return None
    for line in env_path.read_text().splitlines():
        if line.startswith("REPLICATE_API_TOKEN="):
            value = line.split("=", 1)[1].strip().strip("\"'")
            return value or None
    return None


# ---------------------------------------------------------------------------
# Images
# ---------------------------------------------------------------------------


def discover_portraits(folder: Path, limit: int) -> list[Path]:
    if not folder.is_dir():
        raise SystemExit(f"Input folder does not exist: {folder}")
    files = [
        p
        for p in sorted(folder.iterdir())
        if p.is_file() and p.suffix.lower() in IMAGE_EXTS and not p.name.startswith(".")
    ]
    if not files:
        raise SystemExit(
            f"No portraits in {folder}. Drop 3–4 JPG/PNG/WebP files there "
            "(see Avatar/Debug/Fixtures/README.md) and re-run."
        )
    return files[:limit]


def sanitize_stem(path: Path) -> str:
    stem = path.stem
    stem = re.sub(r"[^A-Za-z0-9._-]+", "-", stem).strip("-")
    return stem or "portrait"


def flatten_and_resize(src: Path, dest: Path, max_edge: int) -> tuple[int, int]:
    from PIL import Image

    with Image.open(src) as im:
        im = im.convert("RGBA")
        bg = Image.new("RGBA", im.size, GREY + (255,))
        composed = Image.alpha_composite(bg, im).convert("RGB")
        w, h = composed.size
        long_edge = max(w, h)
        if long_edge > max_edge:
            scale = max_edge / long_edge
            w = max(16, int(round(w * scale)))
            h = max(16, int(round(h * scale)))
        w = max(16, (w // 16) * 16)
        h = max(16, (h // 16) * 16)
        if composed.size != (w, h):
            composed = composed.resize((w, h), Image.Resampling.LANCZOS)
        dest.parent.mkdir(parents=True, exist_ok=True)
        composed.save(dest, format="PNG")
        return w, h


def file_size(path: Path) -> int | None:
    try:
        return path.stat().st_size
    except OSError:
        return None


def dir_size(path: Path) -> int:
    total = 0
    if not path.exists():
        return 0
    for p in path.rglob("*"):
        if p.is_file():
            total += p.stat().st_size
    return total


# ---------------------------------------------------------------------------
# Local inference
# ---------------------------------------------------------------------------


def peak_rss_sampler(pid: int, bucket: list[int], stop: threading.Event) -> None:
    """Sample RSS of `pid` (KB on macOS `ps`) until stop is set."""
    while not stop.wait(0.4):
        try:
            out = subprocess.check_output(
                ["ps", "-o", "rss=", "-p", str(pid)], text=True
            ).strip()
            if out:
                bucket.append(int(out))
        except (OSError, subprocess.CalledProcessError, ValueError):
            return


def run_mlxgen_edit(
    mlxgen: str,
    *,
    model: str,
    image: Path,
    prompt: str,
    output: Path,
    width: int,
    height: int,
    steps: int,
    guidance: float,
    seed: int,
) -> tuple[float, float]:
    """Returns (seconds, peak_rss_mb). Raises on non-zero exit."""
    output.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        mlxgen,
        "generate",
        "--model",
        model,
        "--image",
        str(image),
        "--i2i-mode",
        "edit",
        "--prompt",
        prompt,
        "--width",
        str(width),
        "--height",
        str(height),
        "--steps",
        str(steps),
        "--guidance",
        str(guidance),
        "--seed",
        str(seed),
        "--output",
        str(output),
        "--replace",
        "--low-ram",
        "--progress",
    ]
    t0 = time.perf_counter()
    proc = subprocess.Popen(cmd)
    samples: list[int] = []
    stop = threading.Event()
    sampler = threading.Thread(
        target=peak_rss_sampler, args=(proc.pid, samples, stop), daemon=True
    )
    sampler.start()
    rc = proc.wait()
    stop.set()
    sampler.join(timeout=2)
    elapsed = time.perf_counter() - t0
    peak_mb = (max(samples) / 1024.0) if samples else 0.0
    if rc != 0:
        raise RuntimeError(f"mlxgen exited {rc} for {output.name}")
    if not output.is_file():
        raise RuntimeError(f"mlxgen reported success but missing {output}")
    return elapsed, peak_mb


def ensure_model_downloaded(mlxgen: str, model: str) -> None:
    env = os.environ.copy()
    env.setdefault("HF_XET_HIGH_PERFORMANCE", "1")
    print(f"→ mlxgen download --model {model}", flush=True)
    subprocess.check_call([mlxgen, "download", "--model", model], env=env)


def huggingface_snapshot_size(model: str) -> int | None:
    """Best-effort size of the cached HF snapshot for `owner/name`."""
    hf_home = Path(os.environ.get("HF_HOME", Path.home() / ".cache" / "huggingface"))
    hub = hf_home / "hub" / f"models--{model.replace('/', '--')}"
    if hub.is_dir():
        return dir_size(hub)
    return None


# ---------------------------------------------------------------------------
# Cloud arm (optional)
# ---------------------------------------------------------------------------


def copy_cloud_ref(cloud_dir: Path | None, stem: str, style: str, dest: Path) -> bool:
    if cloud_dir is None:
        return False
    candidates = [
        cloud_dir / f"{stem}-{style}-nano.png",
        cloud_dir / f"{stem}-{style}.png",
        cloud_dir / stem / f"{style}.png",
    ]
    for src in candidates:
        if src.is_file():
            shutil.copy2(src, dest)
            return True
    return False


def nearest_gpt_aspect(width: int, height: int) -> str:
    if width <= 0 or height <= 0:
        return "1:1"
    ratio = width / height
    options = (("1:1", 1.0), ("3:2", 1.5), ("2:3", 2 / 3))
    return min(options, key=lambda item: abs(ratio - item[1]))[0]


def replicate_gpt_image(token: str, image: Path, prompt: str, dest: Path) -> float:
    import requests
    from PIL import Image

    with Image.open(image) as im:
        width, height = im.size
    data_url = "data:image/png;base64," + base64.b64encode(image.read_bytes()).decode()
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Prefer": "wait",
    }
    payload = {
        "input": {
            "prompt": prompt,
            "input_images": [data_url],
            "input_fidelity": "high",
            "quality": "high",
            "output_format": "png",
            "moderation": "low",
            "aspect_ratio": nearest_gpt_aspect(width, height),
        }
    }
    t0 = time.perf_counter()
    resp = requests.post(
        "https://api.replicate.com/v1/models/openai/gpt-image-1.5/predictions",
        headers=headers,
        json=payload,
        timeout=120,
    )
    resp.raise_for_status()
    body = resp.json()
    status = body.get("status")
    get_url = body.get("urls", {}).get("get")
    deadline = time.time() + 90
    while status not in {"succeeded", "failed", "canceled"} and time.time() < deadline:
        time.sleep(2)
        poll = requests.get(get_url, headers={"Authorization": f"Bearer {token}"}, timeout=30)
        poll.raise_for_status()
        body = poll.json()
        status = body.get("status")
    elapsed = time.perf_counter() - t0
    if status != "succeeded":
        err = body.get("error") or status
        raise RuntimeError(f"gpt-image-1.5 {err}")
    output = body.get("output")
    url = output[0] if isinstance(output, list) else output
    if not url:
        raise RuntimeError("gpt-image-1.5 returned empty output")
    img = requests.get(url, timeout=60)
    img.raise_for_status()
    dest.write_bytes(img.content)
    return elapsed


# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------


def write_metrics(path: Path, metrics: RunMetrics) -> None:
    path.write_text(json.dumps(asdict(metrics), indent=2) + "\n")


def _img_cell(rel: str | None, label: str) -> str:
    if rel:
        return (
            f'<div class="cell"><img src="{escape(rel)}" alt="{escape(label)}">'
            f"<div class='cap'>{escape(label)}</div></div>"
        )
    return (
        f'<div class="cell missing"><div class="placeholder">not run</div>'
        f"<div class='cap'>{escape(label)}</div></div>"
    )


def write_html(
    path: Path,
    *,
    portraits: list[tuple[str, Path]],
    styles: Iterable[str],
    out_dir: Path,
    hardware: Hardware,
    metrics: RunMetrics,
) -> None:
    style_list = list(styles)
    rows = []
    for stem, prepared in portraits:
        orig_rel = os.path.relpath(prepared, path.parent)
        for style in style_list:
            qwen = out_dir / f"{stem}-{style}-qwen.png"
            nano = out_dir / f"{stem}-{style}-nano.png"
            qwen_rel = os.path.relpath(qwen, path.parent) if qwen.is_file() else None
            nano_rel = os.path.relpath(nano, path.parent) if nano.is_file() else None
            rows.append(
                "<tr>"
                f"<th>{escape(stem)}<br><span class='style'>{escape(style)}</span></th>"
                f"<td>{_img_cell(orig_rel, 'original')}</td>"
                f"<td>{_img_cell(nano_rel, 'gpt-image-1.5')}</td>"
                f"<td>{_img_cell(qwen_rel, 'Qwen local')}</td>"
                "<td class='score'>"
                "<label>identity <input type='number' min='1' max='5' placeholder='1–5'></label>"
                "<label>style <input type='number' min='1' max='5' placeholder='1–5'></label>"
                "</td>"
                "</tr>"
            )

    mem_note = (
        f"{hardware.mem_gb:g} GB unified"
        if hardware.mem_gb
        else "RAM unknown"
    )
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Local Effects bakeoff</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ font: 13px/1.45 -apple-system, BlinkMacSystemFont, sans-serif;
         margin: 24px; max-width: 1400px; }}
  h1 {{ font-size: 20px; font-weight: 600; margin: 0 0 6px; }}
  .meta {{ color: #666; margin-bottom: 20px; }}
  table {{ border-collapse: collapse; width: 100%; }}
  th, td {{ border-top: 1px solid #ddd; padding: 10px 8px; vertical-align: top; }}
  th {{ text-align: left; width: 140px; font-weight: 600; }}
  .style {{ font-weight: 400; color: #666; }}
  .cell img {{ width: 220px; height: auto; border-radius: 6px; display: block; }}
  .cell .cap {{ font-size: 11px; color: #666; margin-top: 4px; }}
  .missing .placeholder {{ width: 220px; height: 220px; background: #eee;
      display: flex; align-items: center; justify-content: center;
      color: #999; border-radius: 6px; }}
  .score label {{ display: block; margin-bottom: 6px; }}
  .score input {{ width: 4em; }}
  .criteria {{ background: #f6f6f6; padding: 12px 16px; border-radius: 8px;
               margin: 24px 0; }}
  .criteria li {{ margin: 4px 0; }}
  @media (prefers-color-scheme: dark) {{
    .meta, .style, .cell .cap {{ color: #aaa; }}
    th, td {{ border-top-color: #333; }}
    .missing .placeholder {{ background: #222; color: #666; }}
    .criteria {{ background: #1c1c1c; }}
  }}
</style>
</head>
<body>
<h1>Local Effects bakeoff</h1>
<p class="meta">
  {escape(hardware.chip)} · {escape(mem_note)} · {escape(metrics.model)} ·
  {metrics.steps} steps · guidance {metrics.guidance} · seed {metrics.seed} ·
  max edge {metrics.max_edge}px
</p>
<div class="criteria">
  <strong>Go if ≥3 of 4 portraits pass:</strong>
  <ul>
    <li>Person remains identifiable (HR-portrait bar, same axis as E09.1)</li>
    <li>Style is recognisable as clay / wood / 3D / scribble</li>
    <li>Runtime acceptable for a Mac app (guideline: &lt; ~60 s per image)</li>
    <li>16 GB unified memory can run it, or a smaller quant exists that does</li>
  </ul>
  Score identity and style 1–5 per row (5 = matches gpt-image-1.5 / production bar).
</div>
<table>
<thead>
<tr><th></th><th>Original</th><th>gpt-image-1.5</th><th>Qwen local</th><th>Score</th></tr>
</thead>
<tbody>
{"".join(rows)}
</tbody>
</table>
</body>
</html>
"""
    path.write_text(html)


def write_verdict_template(path: Path, hardware: Hardware, metrics: RunMetrics) -> None:
    qwen_times = [
        c["seconds"]
        for c in metrics.cells
        if c.get("arm") == "qwen" and c.get("seconds") is not None
    ]
    qwen_rss = [
        c["peak_rss_mb"]
        for c in metrics.cells
        if c.get("arm") == "qwen" and c.get("peak_rss_mb")
    ]
    avg_s = (sum(qwen_times) / len(qwen_times)) if qwen_times else None
    max_rss = max(qwen_rss) if qwen_rss else None
    errors = [c for c in metrics.cells if c.get("error")]
    path.write_text(
        "\n".join(
            [
                "# Local Effects bakeoff — verdict",
                "",
                f"- Machine: {hardware.chip}, {hardware.mem_gb:g} GB, {hardware.arch}",
                f"- Model: {metrics.model}",
                f"- Qwen cells completed: {len(qwen_times)} / expected",
                f"- Average Qwen wall-clock: {avg_s:.1f}s" if avg_s is not None else "- Average Qwen wall-clock: n/a",
                f"- Peak Qwen RSS: {max_rss:.0f} MB" if max_rss is not None else "- Peak Qwen RSS: n/a",
                f"- Errors: {len(errors)}",
                "",
                "Fill after opening index.html:",
                "",
                "- [ ] Identity holds on ≥3 / 4 portraits",
                "- [ ] Style is recognisable for all four keys",
                f"- [ ] Runtime < 60s (measured avg: {avg_s:.0f}s)" if avg_s is not None else "- [ ] Runtime < 60s",
                "- [ ] 16 GB Macs can run this (this machine is "
                f"{hardware.mem_gb:g} GB — cannot prove 16 GB here)"
                if hardware.mem_gb > 24
                else "- [ ] 16 GB Macs can run this",
                "",
                "**Verdict:** _pending visual scoring_",
                "",
                "Go → follow-up epic: second ModelManager engine, local stylize path,",
                "no credits, Effects visible in localOnly.",
                "No-go → stop; do not integrate into the app.",
                "",
            ]
        )
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument(
        "--inputs",
        type=Path,
        default=REPO_ROOT / "Avatar" / "Debug" / "Fixtures",
        help="Folder of portraits (default: Avatar/Debug/Fixtures)",
    )
    p.add_argument(
        "--out",
        type=Path,
        default=REPO_ROOT / "build" / "bakeoff-local-effects",
        help="Output directory (default: build/bakeoff-local-effects)",
    )
    p.add_argument("--limit", type=int, default=4, help="Max portraits (default 4)")
    p.add_argument(
        "--styles",
        default=",".join(STYLE_ORDER),
        help="Comma-separated style keys",
    )
    p.add_argument("--max-edge", type=int, default=768)
    p.add_argument("--steps", type=int, default=20)
    p.add_argument("--guidance", type=float, default=4.0)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--model", default=DEFAULT_MODEL)
    p.add_argument("--mlxgen", default=None, help="Path to mlxgen binary")
    p.add_argument("--cloud-dir", type=Path, default=None)
    p.add_argument("--skip-local", action="store_true")
    p.add_argument("--skip-cloud", action="store_true")
    p.add_argument("--skip-download", action="store_true")
    p.add_argument("--skip-existing", action="store_true", default=True)
    p.add_argument("--force", action="store_true", help="Re-run cells even if output exists")
    p.add_argument("--qwen-only", action="store_true", help="Alias for --skip-cloud")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    if args.qwen_only:
        args.skip_cloud = True
    if args.force:
        args.skip_existing = False

    styles = [s.strip() for s in args.styles.split(",") if s.strip()]
    unknown = [s for s in styles if s not in STYLE_PROMPTS]
    if unknown:
        raise SystemExit(f"Unknown style(s) {unknown}. Known: {list(STYLE_PROMPTS)}")

    out_dir: Path = args.out
    out_dir.mkdir(parents=True, exist_ok=True)
    prepared_dir = out_dir / "prepared"
    prepared_dir.mkdir(exist_ok=True)

    mlxgen = None if args.skip_local else resolve_mlxgen(args.mlxgen)
    hardware = probe_hardware(mlxgen)
    print(
        f"Hardware: {hardware.chip} · {hardware.mem_gb:g} GB · {hardware.arch}",
        flush=True,
    )
    if not args.skip_local and not hardware.apple_silicon:
        raise SystemExit("Qwen MLX bakeoff requires Apple Silicon (arm64).")

    portraits_src = discover_portraits(args.inputs, args.limit)
    print(f"Portraits ({len(portraits_src)}):", flush=True)
    prepared_list: list[tuple[str, Path, int, int]] = []
    for src in portraits_src:
        stem = sanitize_stem(src)
        dest = prepared_dir / f"{stem}.png"
        w, h = flatten_and_resize(src, dest, args.max_edge)
        print(f"  {src.name} → {dest.name} {w}×{h}", flush=True)
        prepared_list.append((stem, dest, w, h))

    token = None if args.skip_cloud else load_replicate_token()
    metrics = RunMetrics(
        started_at=datetime.now(timezone.utc).isoformat(timespec="seconds"),
        model=args.model,
        steps=args.steps,
        guidance=args.guidance,
        seed=args.seed,
        max_edge=args.max_edge,
        hardware=asdict(hardware),
        portraits=[s for s, *_ in prepared_list],
    )
    if args.skip_cloud:
        metrics.notes.append("Cloud arm skipped (--skip-cloud / --qwen-only).")
    elif token:
        metrics.notes.append("Cloud arm: live Replicate openai/gpt-image-1.5.")
    elif args.cloud_dir:
        metrics.notes.append(f"Cloud arm: files from {args.cloud_dir}.")
    else:
        metrics.notes.append(
            "Cloud arm skipped: no REPLICATE_API_TOKEN and no --cloud-dir."
        )

    if not args.skip_local and not args.skip_download:
        try:
            ensure_model_downloaded(mlxgen, args.model)
        except subprocess.CalledProcessError as exc:
            raise SystemExit(f"mlxgen download failed: {exc}") from exc
    metrics.model_bytes = huggingface_snapshot_size(args.model)

    cells: list[CellMetric] = []

    for stem, prepared, width, height in prepared_list:
        for style in styles:
            prompt = STYLE_PROMPTS[style]
            qwen_out = out_dir / f"{stem}-{style}-qwen.png"
            nano_out = out_dir / f"{stem}-{style}-nano.png"

            qwen = CellMetric(stem=stem, style=style, arm="qwen")
            if args.skip_local:
                qwen.skipped = "skip-local"
            elif args.skip_existing and qwen_out.is_file():
                qwen.skipped = "exists"
                qwen.output = qwen_out.name
            else:
                print(f"→ Qwen {stem} / {style}", flush=True)
                try:
                    seconds, rss = run_mlxgen_edit(
                        mlxgen,
                        model=args.model,
                        image=prepared,
                        prompt=prompt,
                        output=qwen_out,
                        width=width,
                        height=height,
                        steps=args.steps,
                        guidance=args.guidance,
                        seed=args.seed,
                    )
                    qwen.seconds = round(seconds, 2)
                    qwen.peak_rss_mb = round(rss, 1)
                    qwen.output = qwen_out.name
                    print(f"   {seconds:.1f}s  peak RSS {rss:.0f} MB", flush=True)
                except Exception as exc:  # noqa: BLE001 — surface any mlxgen failure
                    qwen.error = str(exc)
                    print(f"   ERROR: {exc}", flush=True)
            cells.append(qwen)

            nano = CellMetric(stem=stem, style=style, arm="nano")
            if args.skip_cloud:
                nano.skipped = "skip-cloud"
            elif args.skip_existing and nano_out.is_file():
                nano.skipped = "exists"
                nano.output = nano_out.name
            elif copy_cloud_ref(args.cloud_dir, stem, style, nano_out):
                nano.skipped = "cloud-dir"
                nano.output = nano_out.name
            elif token:
                print(f"→ gpt-image-1.5 {stem} / {style}", flush=True)
                try:
                    seconds = replicate_gpt_image(token, prepared, prompt, nano_out)
                    nano.seconds = round(seconds, 2)
                    nano.output = nano_out.name
                    print(f"   {seconds:.1f}s", flush=True)
                except Exception as exc:  # noqa: BLE001
                    nano.error = str(exc)
                    print(f"   ERROR: {exc}", flush=True)
            else:
                nano.skipped = "no-token"
            cells.append(nano)

    metrics.cells = [asdict(c) for c in cells]
    metrics.finished_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    write_metrics(out_dir / "metrics.json", metrics)
    write_html(
        out_dir / "index.html",
        portraits=[(s, p) for s, p, *_ in prepared_list],
        styles=styles,
        out_dir=out_dir,
        hardware=hardware,
        metrics=metrics,
    )
    write_verdict_template(out_dir / "VERDICT.md", hardware, metrics)
    print(f"\nSheet: {out_dir / 'index.html'}", flush=True)
    print(f"Metrics: {out_dir / 'metrics.json'}", flush=True)


if __name__ == "__main__":
    main()
