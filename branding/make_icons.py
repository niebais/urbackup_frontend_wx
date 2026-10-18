#!/usr/bin/env python3
"""
Guardian Backup Client icons (distribution branding, not upstream).

Builds the tray state icons, the program icon and the About logo from the
Guardian logo (a red rounded tile with a white "G"), with a status badge in
the corner for each tray state. Needs rsvg-convert and Pillow.

    python3 branding/make_icons.py        # writes into the repository root and data/

Every icon is rendered from SVG at each size (not scaled down from 256 px),
so the 16 px tray icon stays sharp.
"""
import io
import os
import shutil
import subprocess
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZES = [16, 20, 24, 32, 40, 48, 64, 256]

# The Guardian "G" on a 400x400 canvas.
GLYPH = """
<path d="M346.2 196.4H298.2V240.8H346.2V196.4Z" fill="white"/>
<path d="M290.3 265.5V214.2L267.4 196.4H191.8V240.8H195.9H241.1V265.4H151.2C144.4 265.4 140.9 262 140.9 255.1V145.5C140.9 138.7 144.3 135.2 151.2 135.2H241.1V108.5L218.2 90.7H149.2C110.9 90.7 91.7 109.9 91.7 148.2V252.4C91.7 290.7 110.9 309.9 149.2 309.9H267.9L290.4 292.5V265.5H290.3Z" fill="white"/>
<path d="M290.2 143.3H241.2V188.5H290.2V143.3Z" fill="white"/>
"""

TILES = {
    "brand": ("#E54444", "#CE2626"),
    "muted": ("#8A8F98", "#6B7079"),
}

# Badge glyphs, drawn inside a circle centred at (0,0) with radius 100.
MARKS = {
    "check": '<path d="M-48 2 L-14 36 L52 -34" stroke="white" stroke-width="30" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
    "up": '<path d="M0 50 V-40 M-40 0 L0 -44 L40 0" stroke="white" stroke-width="28" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
    "dots": '<circle cx="-46" cy="0" r="17" fill="white"/><circle cx="0" cy="0" r="17" fill="white"/><circle cx="46" cy="0" r="17" fill="white"/>',
    "pause": '<rect x="-40" y="-45" width="26" height="90" rx="8" fill="white"/><rect x="14" y="-45" width="26" height="90" rx="8" fill="white"/>',
    "bang": '<rect x="-14" y="-56" width="28" height="70" rx="12" fill="white"/><circle cx="0" cy="40" r="16" fill="white"/>',
    "cross": '<path d="M-38 -38 L38 38 M38 -38 L-38 38" stroke="white" stroke-width="28" stroke-linecap="round"/>',
}

# file name -> (tile, badge colour, mark); None = no badge
STATES = {
    "backup-ok": ("brand", "#16A34A", "check"),
    "backup-progress": ("brand", "#2563EB", "up"),
    "backup-indexing": ("brand", "#2563EB", "dots"),
    "backup-progress-pause": ("brand", "#D97706", "pause"),
    "backup-no-recent": ("brand", "#D97706", "bang"),
    "backup-no-server": ("brand", "#4B5563", "cross"),
    "backup-bad": ("muted", "#DC2626", "bang"),
}


def svg(tile, badge=None, size=400):
    top, bottom = TILES[tile]
    # Small sizes get a bigger badge so it stays readable in the tray.
    r = 150 if size <= 24 else 120
    badge_svg = ""
    if badge:
        colour, mark = badge
        cx = cy = 400 - r + 8
        scale = r / 100.0
        badge_svg = (
            f'<circle cx="{cx}" cy="{cy}" r="{r + 14}" fill="white"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{colour}"/>'
            f'<g transform="translate({cx} {cy}) scale({scale})">{MARKS[mark]}</g>'
        )
    return f"""<svg width="400" height="400" viewBox="0 0 400 400" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="g" x1="200" y1="0" x2="200" y2="400" gradientUnits="userSpaceOnUse">
<stop stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient></defs>
<rect width="400" height="400" rx="60" fill="url(#g)"/>{GLYPH}{badge_svg}
</svg>"""


def render(svg_text, px):
    png = subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px)], input=svg_text.encode(),
                         capture_output=True, check=True).stdout
    return Image.open(io.BytesIO(png)).convert("RGBA")


def write_ico(path, make_svg):
    images = [render(make_svg(px), px) for px in SIZES]
    # Pillow writes every size listed; each is the bitmap rendered for that size.
    images[-1].save(path, format="ICO", sizes=[(px, px) for px in SIZES], append_images=images[:-1])


def main():
    if not shutil.which("rsvg-convert"):
        sys.exit("rsvg-convert is required")
    os.makedirs(os.path.join(ROOT, "branding", "svg"), exist_ok=True)
    for name, (tile, colour, mark) in STATES.items():
        make = lambda px, t=tile, c=colour, m=mark: svg(t, (c, m), px)
        with open(os.path.join(ROOT, "branding", "svg", name + ".svg"), "w") as f:
            f.write(make(32))
        for target in (os.path.join(ROOT, name + ".ico"), os.path.join(ROOT, "data", name + ".ico")):
            write_ico(target, make)
    plain = lambda px: svg("brand", None, px)
    with open(os.path.join(ROOT, "branding", "svg", "guardian-backup.svg"), "w") as f:
        f.write(plain(256))
    write_ico(os.path.join(ROOT, "icon3.ico"), plain)
    render(plain(96), 96).save(os.path.join(ROOT, "logo1.png"))
    render(plain(96), 96).save(os.path.join(ROOT, "data", "logo1.png")) if os.path.exists(os.path.join(ROOT, "data", "logo1.png")) else None
    print("icons written")


if __name__ == "__main__":
    main()
