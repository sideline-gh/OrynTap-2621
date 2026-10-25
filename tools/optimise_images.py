#!/usr/bin/env python3
"""
OrynTap: turn original photos into small WebP files for the website.

    pip install pillow
    python3 tools/optimise_images.py            # all files in media-src/
    python3 tools/optimise_images.py my.jpg     # one file

Why: a card shows its photo at most 300-330 CSS px wide (about 640 device
pixels on a 2x phone screen). Sending a larger file wastes data, a smaller one
looks blurry. So every photo is resized to 480 and 960 px wide (never enlarged)
and saved as WebP quality 80, which in our A2 experiment was about 40-50 %
smaller than JPEG at the same visible quality.

Graphics with small text (the floor plan) keep their full size and get a
higher quality, 85, so letters stay sharp. We also tried lossless WebP for the
plan: 220 KB, three times the JPEG, because the source is already a JPEG and
lossless coding has to keep all of its compression noise.

Originals stay in media-src/ (never loaded by the site).
"""
import sys
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent.parent
SRC, OUT = ROOT / "media-src", ROOT / "assets" / "img"
WIDTHS = (480, 960)
QUALITY = 80
GRAPHICS = {"aitu-map": 85}       # graphics with text: no resize, higher quality

def kb(p): return p.stat().st_size / 1024

def convert(src: Path):
    im = ImageOps.exif_transpose(Image.open(src)).convert("RGB")   # apply camera rotation, drop alpha
    name = src.stem
    if name in GRAPHICS:
        out = OUT / f"{name}.webp"
        im.save(out, "WEBP", quality=GRAPHICS[name], method=6)
        print(f"{src.name:28} {im.width}x{im.height} {kb(src):7.1f} KB -> {out.name:28} q{GRAPHICS[name]} {kb(out):7.1f} KB")
        return
    made = False
    for w in WIDTHS:
        if w > im.width and made:
            break                                   # never upscale
        tw = min(w, im.width)
        th = round(im.height * tw / im.width)
        out = OUT / f"{name}-{tw}.webp"
        im.resize((tw, th), Image.LANCZOS).save(out, "WEBP", quality=QUALITY, method=6)
        made = True
        print(f"{src.name:28} {im.width}x{im.height} {kb(src):7.1f} KB -> {out.name:28} {tw}x{th} {kb(out):7.1f} KB")
        if tw == im.width:
            break

if __name__ == "__main__":
    files = [Path(a) for a in sys.argv[1:]] or sorted(p for p in SRC.iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png"))
    for f in files:
        convert(f)
