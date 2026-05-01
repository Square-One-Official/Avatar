#!/usr/bin/env python3
"""
Generates the DMG installer background.

Source of truth for the design — edit constants below to tweak.
Outputs (next to this script):
    background.png      660 × 420  (@1x)
    background@2x.png   1320 × 840 (@2x)
    background.tiff     packed multi-resolution (handed to create-dmg)

Run:
    python3 scripts/dmg-assets/build-background.py
"""

from __future__ import annotations

import math
import os
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent

# Logical canvas (matches the DMG window size set in release.sh)
W, H = 660, 420

# Colors — flat off-white in lijn met het Avatar-icoon (geen gradient).
BG = (242, 242, 243)          # #F2F2F3 — zit naast het zilverachtige app-icoon zonder contrast-naad
LINE = (154, 160, 166)        # #9AA0A6
TEXT = (107, 114, 128)        # #6B7280

# Arc geometry (logical pt). Bow ~30pt above the icon row.
ARC_START = (235.0, 215.0)
ARC_END = (425.0, 215.0)
ARC_C1 = (285.0, 165.0)
ARC_C2 = (375.0, 165.0)

DASH_ON = 6.0
DASH_OFF = 8.0
STROKE = 1.5

# Chevron
CHEVRON_LEN = 10.0
CHEVRON_ANGLE_DEG = 28.0

# Caption
CAPTION = "Drag and drop to install"
CAPTION_Y = 320           # baseline-ish; PIL anchors handle this
CAPTION_PT = 13


def _canvas(scale: int) -> Image.Image:
    return Image.new("RGB", (W * scale, H * scale), BG)


def _bezier(t: float, p0, p1, p2, p3) -> tuple[float, float]:
    u = 1 - t
    x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
    y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
    return x, y


def _bezier_tangent(t: float, p0, p1, p2, p3) -> tuple[float, float]:
    u = 1 - t
    dx = 3 * u**2 * (p1[0] - p0[0]) + 6 * u * t * (p2[0] - p1[0]) + 3 * t**2 * (p3[0] - p2[0])
    dy = 3 * u**2 * (p1[1] - p0[1]) + 6 * u * t * (p2[1] - p1[1]) + 3 * t**2 * (p3[1] - p2[1])
    return dx, dy


def _draw_dashed_arc(draw: ImageDraw.ImageDraw, scale: int) -> None:
    samples = 600
    pts = [_bezier(i / samples, ARC_START, ARC_C1, ARC_C2, ARC_END) for i in range(samples + 1)]
    cum = [0.0]
    for i in range(1, len(pts)):
        dx = pts[i][0] - pts[i - 1][0]
        dy = pts[i][1] - pts[i - 1][1]
        cum.append(cum[-1] + math.hypot(dx, dy))
    total = cum[-1]

    def point_at(d: float) -> tuple[float, float]:
        # Linear search across cumulative table; fine for 600 samples.
        if d <= 0:
            return pts[0]
        if d >= total:
            return pts[-1]
        lo, hi = 0, len(cum) - 1
        while lo < hi - 1:
            mid = (lo + hi) // 2
            if cum[mid] <= d:
                lo = mid
            else:
                hi = mid
        seg = cum[hi] - cum[lo]
        t = 0.0 if seg == 0 else (d - cum[lo]) / seg
        x = pts[lo][0] + (pts[hi][0] - pts[lo][0]) * t
        y = pts[lo][1] + (pts[hi][1] - pts[lo][1]) * t
        return x, y

    width = max(1, round(STROKE * scale))
    d = 0.0
    while d < total:
        a = point_at(d)
        b = point_at(min(d + DASH_ON, total))
        draw.line(
            [(a[0] * scale, a[1] * scale), (b[0] * scale, b[1] * scale)],
            fill=LINE,
            width=width,
        )
        d += DASH_ON + DASH_OFF


def _draw_chevron(draw: ImageDraw.ImageDraw, scale: int) -> None:
    tx, ty = _bezier_tangent(1.0, ARC_START, ARC_C1, ARC_C2, ARC_END)
    theta = math.atan2(ty, tx)
    a = math.radians(CHEVRON_ANGLE_DEG)
    tip = ARC_END

    # Two strokes splaying back from the tip.
    for sign in (+1, -1):
        ang = theta + math.pi + sign * a
        bx = tip[0] + math.cos(ang) * CHEVRON_LEN
        by = tip[1] + math.sin(ang) * CHEVRON_LEN
        draw.line(
            [(tip[0] * scale, tip[1] * scale), (bx * scale, by * scale)],
            fill=LINE,
            width=max(1, round(STROKE * scale)),
        )


def _font(size_px: int) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for path in candidates:
        if os.path.exists(path):
            font = ImageFont.truetype(path, size_px)
            try:
                # Nudge SFNS toward Medium weight when the variable axis is exposed.
                font.set_variation_by_axes([510])
            except Exception:
                pass
            return font
    return ImageFont.load_default()


def _draw_caption(draw: ImageDraw.ImageDraw, scale: int) -> None:
    font = _font(CAPTION_PT * scale)
    draw.text(
        (W / 2 * scale, CAPTION_Y * scale),
        CAPTION,
        fill=TEXT,
        font=font,
        anchor="mm",
    )


def render(scale: int) -> Image.Image:
    img = _canvas(scale)
    draw = ImageDraw.Draw(img, "RGBA")
    _draw_dashed_arc(draw, scale)
    _draw_chevron(draw, scale)
    _draw_caption(draw, scale)
    return img


def main() -> int:
    one = HERE / "background.png"
    two = HERE / "background@2x.png"
    tiff = HERE / "background.tiff"

    render(1).save(one)
    render(2).save(two)

    # Pack into a multi-resolution TIFF for create-dmg.
    subprocess.run(
        ["tiffutil", "-cathidpicheck", str(one), str(two), "-out", str(tiff)],
        check=True,
    )
    print(f"Wrote {one.relative_to(HERE.parent.parent)}")
    print(f"Wrote {two.relative_to(HERE.parent.parent)}")
    print(f"Wrote {tiff.relative_to(HERE.parent.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
