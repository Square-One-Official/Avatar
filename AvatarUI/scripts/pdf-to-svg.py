#!/usr/bin/env python3
# Gebruik: pdf-to-svg.py <map met PDF's>  — zet elke PDF om naar SVG (in-place).
# PDF → SVG. Twee converters, per bestand de bitmap-vrije variant:
#  - PyMuPDF (pip3 install pymupdf): vectoriseert softmasks, rastert gradients;
#  - pdftocairo (brew install poppler): vectoriseert gradients, rastert softmasks.
# Tekst komt als paden (exact SF Pro). 1pt = 1px voor Figma.
import fitz, sys, pathlib, re, shutil, subprocess
out = pathlib.Path(sys.argv[1]); n = 0; rasters = []
cairo = shutil.which("pdftocairo")
def fix_units(svg):
    return re.sub(r'width="([0-9.]+)pt" height="([0-9.]+)pt"', r'width="\1" height="\2"', svg, count=1)
for pdf in sorted(out.glob("*.pdf")):
    svg = fix_units(fitz.open(pdf)[0].get_svg_image(text_as_path=True))
    if "<image" in svg and cairo:
        tmp = pdf.with_suffix(".cairo.svg")
        subprocess.run([cairo, "-svg", str(pdf), str(tmp)], check=True)
        alt = fix_units(tmp.read_text()); tmp.unlink()
        if "<image" not in alt: svg = alt
    if "<image" in svg: rasters.append(pdf.stem)
    pdf.with_suffix(".svg").write_text(svg); pdf.unlink(); n += 1
print(f"export-vectors: {n} SVG's in {out}")
if rasters: print("LET OP, bevatten nog bitmaps:", ", ".join(rasters))
