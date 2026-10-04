#!/usr/bin/env python3
"""Writes the app's launcher icons from design/nonya.png. Run it again when the artwork changes,
rather than editing the PNGs it writes.

The artwork is a rounded square on black. A launcher draws its own shape (a circle, a squircle,
iOS's rounded square), so the icon has to be full-bleed: the black outside the square is replaced
with the square's own background, continued, and the result is cropped around the mark. Android's
adaptive icon masks to as little as the centre 66 of its 108dp, so there the mark is kept inside
that; iOS rounds a full square, so the mark is drawn larger.

Needs Pillow (`pip install pillow`). Usage: python3 scripts/icons.py
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "design" / "nonya.png"
RES = ROOT / "android" / "app" / "src" / "main" / "res"
IOS = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

# Where the square's background is sampled: inside each corner, clear of the rim and the mark.
SAMPLES = [(200, 200), (1050, 200), (200, 1050), (1050, 1050)]


def full_bleed(art: Image.Image, pad: int) -> Image.Image:
    """The artwork on its own background continued to the edges, with [pad] pixels more each side."""
    w, h = art.size
    size = (w + 2 * pad, h + 2 * pad)
    # The background lightens toward the top left: four samples, blended across the whole canvas.
    corners = Image.new("RGB", (2, 2))
    corners.putdata([art.getpixel(p) for p in SAMPLES])
    ground = corners.resize(size, Image.BILINEAR)

    # What is outside the square: the black reachable from the corners. Flood-filled rather than a
    # drawn rounded rectangle, so it follows the artwork's own corner, whatever its radius.
    outside = Image.new("L", (w, h), 0)
    lum = art.convert("L").point(lambda v: 255 if v < 8 else 0)
    for corner in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        ImageDraw.floodfill(lum, corner, 128)
    outside = lum.point(lambda v: 255 if v == 128 else 0)
    # Kept well inside the square's lighter rim, and faded out, so no outline of it survives.
    inside = (
        outside.point(lambda v: 255 - v)
        .filter(ImageFilter.MinFilter(81))
        .filter(ImageFilter.GaussianBlur(35))
    )
    ground.paste(art, (pad, pad), inside)
    return ground


def crop(image: Image.Image, centre: tuple[int, int], side: int) -> Image.Image:
    cx, cy = centre
    return image.crop((cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2))


def main() -> None:
    art = Image.open(ART).convert("RGB")
    pad = 400
    canvas = full_bleed(art, pad)
    # The mark's bounds in the artwork: x 262..990, y 218..1020.
    centre = (626 + pad, 619 + pad)
    mark = 802

    # Android adaptive icon: the mark within the 66dp safe zone of 108dp, with a little to spare.
    adaptive = crop(canvas, centre, round(mark / 0.58))
    for density, px in {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}.items():
        adaptive.resize((px, px), Image.LANCZOS).save(RES / f"mipmap-{density}" / "ic_launcher_foreground.png")
    # Before Android 8 there is no mask: the artwork's own rounded square, transparent outside.
    legacy = Image.open(ART).convert("RGBA").crop((65, 50, 1190, 1188))
    corner = legacy.convert("L").point(lambda v: 255 if v < 8 else 0)
    for c in [(0, 0), (legacy.width - 1, 0), (0, legacy.height - 1), (legacy.width - 1, legacy.height - 1)]:
        ImageDraw.floodfill(corner, c, 128)
    legacy.putalpha(corner.point(lambda v: 0 if v == 128 else 255).filter(ImageFilter.GaussianBlur(1)))
    for density, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        legacy.resize((px, px), Image.LANCZOS).save(RES / f"mipmap-{density}" / "ic_launcher.png")

    # iOS: a full square, no transparency; iOS rounds the corners itself.
    ios = crop(canvas, centre, round(mark / 0.7))
    for image in json.loads((IOS / "Contents.json").read_text())["images"]:
        points = float(image["size"].split("x")[0])
        px = round(points * int(image["scale"].rstrip("x")))
        ios.resize((px, px), Image.LANCZOS).save(IOS / image["filename"])


if __name__ == "__main__":
    main()
