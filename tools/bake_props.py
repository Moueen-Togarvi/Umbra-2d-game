#!/usr/bin/env python3
"""Bake individual scenery props and the sparse layers into alpha-keyed PNGs.

Props are single silhouettes placed at specific world positions by the game
(see GameConfig.scenery), so each is trimmed to its own bounding box and the
bottom of the image is the bottom of the silhouette. Every output is black
with the shape in the alpha channel.

A silhouette is *solid*: any transparent pocket enclosed by the shape (the
mortar lines the model drew between bricks, a window) is filled, because a
thing seen against fog shows no interior at all — a brick pattern with fog
shining through every joint is what makes a prop look pasted on.

Each prop also gets two fogged variants for use at depth: `_soft` (lightly
blurred, base fading into mist) and `_far` (heavily blurred, most of the
lower half dissolved). Fog is thickest near the ground, so the further away
a thing is the less of its base survives.

usage: bake_props.py <raw_dir> <out_dir>
"""
import sys, pathlib
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

RAW = pathlib.Path(sys.argv[1]); OUT = pathlib.Path(sys.argv[2]); OUT.mkdir(parents=True, exist_ok=True)

# name: (source, crop (l, t, r, b) fractions to KEEP, key (lo, hi) luminance,
#        max_height px, trim, tile)
# FILL names the props whose enclosed transparent pockets are solid interior
# (a stone tower's mortar lines and windows). Not for open structures: the
# gaps between a fence's rails or a ladder's rungs are real.
# Luminance <= lo is fully opaque, >= hi fully transparent, linear between.
# A tight (lo, hi) band such as (90, 190) throws away light gradient
# backgrounds and soft shadows and keeps only the black silhouette.
SPECS = {
    "prop_tree_a":    ("prop_tree_a",    (0.00, 0.00, 1.00, 0.924), (70, 160), 1400, True,  False),
    "prop_tree_b":    ("prop_tree_b",    (0.00, 0.00, 1.00, 0.900), (70, 160), 1400, True,  False),
    "prop_ladder":    ("prop_ladder",    (0.05, 0.05, 0.95, 0.915), (70, 160), 1200, True,  False),
    "prop_gallows":   ("prop_gallows",   (0.10, 0.09, 0.90, 0.888), (60, 130), 1300, True,  False),
    "prop_tower":     ("prop_tower_v2",  (0.05, 0.00, 0.95, 0.852), (70, 120), 1300, True,  False),
    "prop_watchtower":("prop_watchtower",(0.08, 0.07, 0.92, 0.884), (70, 160), 1300, True,  False),
    "prop_fence":     ("prop_fence",     (0.03, 0.45, 0.97, 0.945), (60, 120),  700, True,  False),
    "prop_boulder":   ("prop_boulder",   (0.05, 0.20, 0.95, 0.825), (40, 100),  600, True,  False),
    "grass_fine":     ("grass_fine_v2",  (0.00, 0.60, 1.00, 0.795), (90, 190),  200, False, True),
    "grass_tall":     ("grass_tall",     (0.00, 0.30, 1.00, 0.900), (90, 190),  420, False, True),
}

FILL = {"prop_tower"}

def key(gray, lo, hi):
    a = (hi - gray.astype(np.float32)) * (255.0 / (hi - lo))
    return np.clip(a, 0, 255)

def close_gaps(alpha, size=9):
    """Morphological closing: seal transparent cracks narrower than `size`
    px (mortar lines, hairline gaps) while leaving thin solid features such
    as twigs untouched. Dilate, then erode."""
    im = Image.fromarray(alpha.astype(np.uint8), "L").copy()
    im = im.filter(ImageFilter.MaxFilter(size)).filter(ImageFilter.MinFilter(size))
    return np.asarray(im).astype(np.float32)

def fill_holes(alpha):
    """Make every transparent region that does not touch the border opaque."""
    solid = alpha > 100
    h, w = solid.shape
    # Pad with a transparent frame so one flood fill from the corner reaches
    # every outside region; whatever it does not reach is an enclosed hole.
    pad = np.full((h + 2, w + 2), 255, dtype=np.uint8)
    pad[1:-1, 1:-1] = np.where(solid, 0, 255)
    # `.copy()`: an image backed by a numpy array is read-only to floodfill.
    im = Image.fromarray(pad, "L").copy()
    ImageDraw.floodfill(im, (0, 0), 128)
    outside = np.asarray(im)[1:-1, 1:-1] == 128
    holes = ~solid & ~outside
    out = alpha.copy()
    out[holes] = 255
    return out

def fade_base(im, start, floor):
    """Multiply alpha by a ramp from 1 at `start` (fraction of height) down
    to `floor` at the bottom edge."""
    a = np.asarray(im).astype(np.float32)
    h = a.shape[0]
    y0 = int(start * h)
    ramp = np.ones(h, dtype=np.float32)
    ramp[y0:] = np.linspace(1.0, floor, h - y0)
    a[..., 3] *= ramp[:, None]
    return Image.fromarray(a.astype(np.uint8), "RGBA")

def to_rgba(alpha):
    rgba = np.zeros((*alpha.shape, 4), dtype=np.uint8)
    rgba[..., 3] = np.clip(alpha, 0, 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")

for name, (src, (l, t, r, b), (lo, hi), max_h, trim, tile) in SPECS.items():
    im = Image.open(RAW / f"{src}.png").convert("L")
    W, H = im.size
    im = im.crop((int(l * W), int(t * H), int(r * W), int(b * H)))
    a = key(np.asarray(im), lo, hi)

    if trim:
        # Cut away transparent margins so the image's bottom edge is the
        # silhouette's base. Ignore specks: rows/cols need real coverage.
        rows = np.where(a.max(axis=1) > 40)[0]; cols = np.where(a.max(axis=0) > 40)[0]
        a = a[rows[0]:rows[-1] + 1, cols[0]:cols[-1] + 1]
        a = close_gaps(a)
        if name in FILL:
            a = fill_holes(a)

    if tile:
        # Mirror so the strip repeats without a seam.
        a = np.concatenate([a, a[:, ::-1]], axis=1)

    out = to_rgba(a)
    if out.height > max_h:
        out = out.resize((int(out.width * max_h / out.height), max_h), Image.LANCZOS)
    out.save(OUT / f"{name}.png", optimize=True)

    line = f"{name:16s} {out.width}x{out.height}"
    if trim:
        soft = out.filter(ImageFilter.GaussianBlur(max(3, out.height // 140)))
        fade_base(soft, 0.55, 0.30).save(OUT / f"{name}_soft.png", optimize=True)
        far = out.filter(ImageFilter.GaussianBlur(max(6, out.height // 55)))
        fade_base(far, 0.40, 0.10).save(OUT / f"{name}_far.png", optimize=True)
        line += "  (+soft +far)"
    print(line)
