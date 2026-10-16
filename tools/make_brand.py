#!/usr/bin/env python3
"""Builds the Umbra brand assets from the generated icon art and the font.

usage: make_brand.py

  assets/brand/icon_1024.png      the app icon art, in the brand colours
  assets/brand/wordmark.png       UMBRA with the amber eyes, for splash/web
  android mipmaps                 legacy icons and adaptive foregrounds
  android drawable-nodpi          the splash wordmark
  web/icons, web/favicon.png      web app icons

The icon is the boy in the lit doorway of home (assets/raw/part1/
brand_icon.png): its greys are mapped onto the brand ramp, near-black
through the lamp's amber to a warm cream, so the light in the door is the
lamp's light.
"""
import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
BLACK = (11, 11, 11)
AMBER = (232, 168, 74)
CREAM = (250, 228, 186)
INK = (216, 212, 204)


def ramp(lum):
    """0..1 luminance onto near-black → deep amber → amber → cream."""
    stops = [(0.0, BLACK), (0.3, (52, 30, 12)), (0.72, AMBER), (1.0, (247, 206, 140))]
    out = np.zeros(lum.shape + (3,), np.float32)
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        t = np.clip((lum - a) / (b - a), 0, 1)[..., None]
        m = ((lum >= a) & (lum <= b))[..., None]
        out = np.where(m, np.array(ca) * (1 - t) + np.array(cb) * t, out)
    return out.astype(np.uint8)


def icon_art():
    raw = Image.open(ROOT / "assets/raw/part1/brand_icon.png").convert("L")
    w = raw.width
    # The door and the boy, with a dark margin.
    box = [int(v * w / 480) for v in (46, 34, 434, 422)]
    crop = raw.crop(box).resize((1024, 1024), Image.LANCZOS)
    lum = np.asarray(crop, np.float32) / 255
    # A little glow spilling round the door.
    bloom = np.asarray(crop.filter(ImageFilter.GaussianBlur(40)), np.float32) / 255
    lum = np.clip(np.maximum(lum, bloom * 0.55), 0, 1)
    # The lamp is low and to one side: the light is warmest away from it.
    yy, xx = np.mgrid[0:1024, 0:1024] / 1024.0
    falloff = 1 - 0.22 * np.clip(np.hypot(xx - 0.42, yy - 0.62) / 0.7, 0, 1)
    lum = lum * falloff
    return Image.fromarray(ramp(lum), "RGB")


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def on_black(img, size, scale):
    canvas = Image.new("RGB", (size, size), BLACK)
    s = int(size * scale)
    canvas.paste(img.resize((s, s), Image.LANCZOS), ((size - s) // 2, (size - s) // 2))
    return canvas


def wordmark(height):
    """UMBRA in Cinzel, letter-spaced, with two amber eyes in the U."""
    font = ImageFont.truetype(str(ROOT / "assets/fonts/Cinzel-Variable.ttf"), int(height * 1.18))
    try:
        font.set_variation_by_axes([500])
    except Exception:
        pass
    spacing = height * 0.32
    letters = "UMBRA"
    widths = [font.getbbox(c)[2] - font.getbbox(c)[0] for c in letters]
    total = sum(widths) + spacing * (len(letters) - 1)
    pad = int(height * 0.4)
    img = Image.new("RGBA", (int(total) + pad * 2, int(height * 1.6) + pad), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x = pad
    top = pad // 2
    u_box = None
    for c, w in zip(letters, widths):
        bb = font.getbbox(c)
        d.text((x - bb[0], top), c, font=font, fill=INK + (255,))
        if c == "U":
            u_box = (x, top + bb[1], x + w, top + bb[3])
        x += w + spacing
    # The eyes: a soft glow and a bright core.
    l, t, r, b = u_box
    cx, cy = (l + r) / 2, t + (b - t) * 0.55
    gap = (r - l) * 0.15
    rr = height * 0.045
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for dx in (-gap, gap):
        gd.ellipse([cx + dx - rr * 3, cy - rr * 3, cx + dx + rr * 3, cy + rr * 3], fill=AMBER + (120,))
    glow = glow.filter(ImageFilter.GaussianBlur(rr * 1.5))
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)
    for dx in (-gap, gap):
        d.ellipse([cx + dx - rr * 1.1, cy - rr * 0.8, cx + dx + rr * 1.1, cy + rr * 0.8], fill=(246, 214, 160, 255))
    return img.crop(img.getbbox())


def main():
    brand = ROOT / "assets/brand"
    brand.mkdir(parents=True, exist_ok=True)
    art = icon_art()
    art.save(brand / "icon_1024.png")
    mark = wordmark(160)
    mark.save(brand / "wordmark.png")

    res = ROOT / "android/app/src/main/res"
    for folder, legacy, adaptive in [
        ("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216),
        ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432),
    ]:
        out = res / f"mipmap-{folder}"
        out.mkdir(exist_ok=True)
        rounded(art.resize((legacy, legacy), Image.LANCZOS), legacy // 5).save(out / "ic_launcher.png")
        # Adaptive: the door within the safe zone, black all round.
        on_black(art, adaptive, 0.78).save(out / "ic_launcher_foreground.png")
    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n"
    )
    nodpi = res / "drawable-nodpi"
    nodpi.mkdir(exist_ok=True)
    m = mark.copy()
    m.thumbnail((720, 720))
    m.save(nodpi / "splash_wordmark.png")

    web = ROOT / "web"
    for size in (192, 512):
        art.resize((size, size), Image.LANCZOS).save(web / "icons" / f"Icon-{size}.png")
        on_black(art, size, 0.8).save(web / "icons" / f"Icon-maskable-{size}.png")
    art.resize((32, 32), Image.LANCZOS).save(web / "favicon.png")
    print("brand assets written")


if __name__ == "__main__":
    main()
