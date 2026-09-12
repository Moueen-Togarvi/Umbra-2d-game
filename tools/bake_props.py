#!/usr/bin/env python3
"""Bake individual scenery props and the sparse layers into alpha-keyed PNGs.

Props are single silhouettes placed at specific world positions by the game
(see GameConfig.scenery), so each is trimmed to its own bounding box and the
bottom of the image is the bottom of the silhouette. Every output is black
with the shape in the alpha channel; each prop also gets a `_soft` variant,
blurred for use in the far distance.

usage: bake_props.py <raw_dir> <out_dir>
"""
import sys, pathlib
from PIL import Image, ImageFilter
import numpy as np

RAW = pathlib.Path(sys.argv[1]); OUT = pathlib.Path(sys.argv[2]); OUT.mkdir(parents=True, exist_ok=True)

# name: (source, crop (l, t, r, b) fractions to KEEP, key (lo, hi) luminance,
#        max_height px, trim, tile)
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
    "mist_trees":     ("mist_trees",     (0.00, 0.06, 1.00, 0.870), (60, 232),  800, False, True),
    "grass_fine":     ("grass_fine_v2",  (0.00, 0.60, 1.00, 0.795), (90, 190),  200, False, True),
}

def key(gray, lo, hi):
    a = (hi - gray.astype(np.float32)) * (255.0 / (hi - lo))
    return np.clip(a, 0, 255)

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

    if tile:
        # Mirror so the strip repeats without a seam.
        a = np.concatenate([a, a[:, ::-1]], axis=1)

    out = to_rgba(a)
    if out.height > max_h:
        out = out.resize((int(out.width * max_h / out.height), max_h), Image.LANCZOS)
    out.save(OUT / f"{name}.png", optimize=True)

    line = f"{name:16s} {out.width}x{out.height}"
    if trim:
        soft = out.filter(ImageFilter.GaussianBlur(max(3, out.height // 150)))
        soft.save(OUT / f"{name}_soft.png", optimize=True)
        line += "  (+soft)"
    print(line)
