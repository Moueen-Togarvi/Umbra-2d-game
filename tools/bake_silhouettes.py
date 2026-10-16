#!/usr/bin/env python3
"""Bake generated art into solid silhouettes for the game.

usage: bake_silhouettes.py <raw_dir> <out_dir> <config.json> [--sheet sheet.png]

The image model draws on a plain white background, but it does not always
draw a flat silhouette: it may add interior lines, white walls or colour.
So the background is found by flood-filling from the image border across
light pixels; everything that flood fill does not reach is the object,
filled solid, and only the outline survives. Its edge keeps the drawing's
anti-aliasing. Gaps that are open to the outside (between bars, branches,
pickets) stay open; pockets enclosed by the shape (window panes, mortar)
fill in, because a thing seen against fog shows no interior.

Per asset (config.json):
  "max_h": tallest output in px (mobile-friendly).
  "crop":  [l, t, r, b] fractions of the source to keep (default all).
  "cut":   named groups of rectangles [l, t, r, b], as fractions of the
           *baked* image, to cut back out as openings (a doorway, the panes
           of a window) for the game to light or to hinge a door in.
  "far":   also write a blurred `_far` variant for use at depth.
  "keep_inner_white": pockets larger than this fraction of the object are
           left open instead of filled (e.g. a cave mouth or arch).
  "despeckle": drop loose bits (gravel, specks of ink) with no part
           thicker than this many px (default 9 for solid shapes, 0 —
           off — for open ones).
  "open":  no flood fill: every light pixel is background, so all the gaps
           stay open (cage bars, chain links). Pixels darker than "dark"
           (default 150) are solid.
Every output is black with the shape in alpha, trimmed to its bounding box
and then padded with PAD transparent pixels all round, so a renderer that
clamps at the image edge (Impeller does, with a colour filter) samples
transparency there rather than smearing the outermost pixels into a frame.
A JSON of each output's size (and cut rectangles in px) is written next to
the images for the game.
"""
import json, pathlib, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

LIGHT = 214  # luminance above which a pixel can be background
PAD = 4  # transparent border round every output


def solid_mask(rgb, keep_inner_white=0.0):
    lum = np.asarray(rgb.convert("L"), dtype=np.float32)
    h, w = lum.shape
    light = Image.fromarray(((lum > LIGHT) * 255).astype(np.uint8), "L")
    # A 1 px light border so the flood reaches every edge.
    framed = Image.new("L", (w + 2, h + 2), 255)
    framed.paste(light, (1, 1))
    ImageDraw.floodfill(framed, (0, 0), 128)
    region = np.asarray(framed, dtype=np.uint8)[1:-1, 1:-1]
    background = region == 128
    obj = ~background
    if keep_inner_white > 0:
        # Large enclosed light pockets stay open (arches, cave mouths).
        pockets = (region == 255)
        labelled = Image.fromarray((pockets * 255).astype(np.uint8), "L")
        total = obj.sum()
        seen = np.zeros_like(pockets)
        ys, xs = np.nonzero(pockets)
        canvas = labelled.copy()
        for y, x in zip(ys[::97], xs[::97]):
            if seen[y, x]:
                continue
            probe = canvas.copy()
            ImageDraw.floodfill(probe, (int(x), int(y)), 64)
            part = np.asarray(probe) == 64
            seen |= part
            if part.sum() > keep_inner_white * total:
                obj &= ~part
    # Anti-aliased edge: in the background next to the object, partial
    # alpha from how dark the drawing is there.
    fringe = np.clip((248 - lum) / (248 - LIGHT), 0, 1) * 255
    alpha = np.where(obj, 255.0, 0.0)
    near = np.asarray(
        Image.fromarray(obj.astype(np.uint8) * 255, "L").filter(ImageFilter.MaxFilter(3))
    ) > 0
    alpha = np.where(background & near, fringe, alpha)
    # Drop specks: open the mask a little.
    a = Image.fromarray(alpha.astype(np.uint8), "L")
    a = a.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
    return np.maximum(np.asarray(a, dtype=np.float32), alpha * (np.asarray(a) > 0))


def despeckle(alpha, size):
    """Removes loose bits of the shape (gravel, specks of ink): any piece
    that has no part thicker than `size` px, with its anti-aliased fringe.
    Pieces that do survive an erosion; they are grown back within the
    shape until nothing changes, so thin parts joined to them stay."""
    solid = Image.fromarray((alpha > 128).astype(np.uint8) * 255, "L")
    mask = np.asarray(solid) > 0
    keep = np.asarray(solid.filter(ImageFilter.MinFilter(size))) > 0
    while True:
        grown = np.asarray(
            Image.fromarray(keep.astype(np.uint8) * 255, "L").filter(ImageFilter.MaxFilter(7))
        ) > 0
        grown &= mask
        if (grown != keep).sum() == 0:
            break
        keep = grown
    near = np.asarray(
        Image.fromarray(keep.astype(np.uint8) * 255, "L").filter(ImageFilter.MaxFilter(5))
    ) > 0
    return np.where(near, alpha, 0.0)


def open_mask(rgb, dark=150):
    lum = np.asarray(rgb.convert("L"), dtype=np.float32)
    return np.clip((236 - lum) / (236 - dark), 0, 1) * 255


def bake(raw, out, name, spec):
    rgb = Image.open(raw / f"{spec.get('source', name)}.png").convert("RGB")
    w, h = rgb.size
    l, t, r, b = spec.get("crop", [0, 0, 1, 1])
    rgb = rgb.crop((int(l * w), int(t * h), int(r * w), int(b * h)))
    if spec.get("open"):
        alpha = open_mask(rgb, spec.get("dark", 150))
    else:
        alpha = solid_mask(rgb, spec.get("keep_inner_white", 0.0))
    speck = spec.get("despeckle", 0 if spec.get("open") else 9)
    if speck > 0:
        alpha = despeckle(alpha, speck)
    ys, xs = np.nonzero(alpha > 8)
    if len(xs) == 0:
        print(f"  EMPTY {name}")
        return None
    alpha = alpha[ys.min(): ys.max() + 1, xs.min(): xs.max() + 1]
    img = Image.new("RGBA", (alpha.shape[1], alpha.shape[0]), (0, 0, 0, 0))
    img.putalpha(Image.fromarray(alpha.astype(np.uint8), "L"))
    scale = min(1.0, spec.get("max_h", 1200) / img.height)
    if scale < 1:
        img = img.resize((max(1, int(img.width * scale)), max(1, int(img.height * scale))), Image.LANCZOS)
    cuts = {}
    if spec.get("cut"):
        a = img.getchannel("A")
        draw = ImageDraw.Draw(a)
        for group, rects in spec["cut"].items():
            cuts[group] = []
            for cl, ct, cr, cb in rects:
                box = [round(cl * img.width), round(ct * img.height), round(cr * img.width), round(cb * img.height)]
                draw.rectangle([box[0], box[1], box[2] - 1, box[3] - 1], fill=0)
                cuts[group].append(box)
        img.putalpha(a)
    padded = Image.new("RGBA", (img.width + PAD * 2, img.height + PAD * 2), (0, 0, 0, 0))
    padded.paste(img, (PAD, PAD))
    img = padded
    cuts = {g: [[v + PAD for v in box] for box in boxes] for g, boxes in cuts.items()}
    img.save(out / f"{name}.png", optimize=True)
    meta = {"w": img.width, "h": img.height, "pad": PAD, "cut": cuts}
    if spec.get("far"):
        far = img.getchannel("A").filter(ImageFilter.GaussianBlur(max(2, img.height / 160)))
        f = Image.new("RGBA", img.size, (0, 0, 0, 0))
        f.putalpha(far)
        f.save(out / f"{name}_far.png", optimize=True)
    print(f"  ok   {name} {img.width}x{img.height}")
    return meta


def contact_sheet(out, names, path):
    cell = 260
    cols = 6
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 18)), (120, 120, 120))
    draw = ImageDraw.Draw(sheet)
    for i, n in enumerate(names):
        p = out / f"{n}.png"
        if not p.exists():
            continue
        im = Image.open(p)
        s = min((cell - 10) / im.width, (cell - 10) / im.height)
        im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))))
        x, y = (i % cols) * cell, (i // cols) * (cell + 18)
        # On a pale fog tone, as it will sit in the game.
        tile = Image.new("RGB", (cell - 4, cell - 4), (196, 196, 196))
        tile.paste(im, ((cell - 4 - im.width) // 2, (cell - 4 - im.height) // 2), im)
        sheet.paste(tile, (x + 2, y + 2))
        draw.text((x + 6, y + cell - 2), n, fill=(255, 255, 255))
    sheet.save(path)


if __name__ == "__main__":
    raw, out, cfg = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), json.load(open(sys.argv[3]))
    out.mkdir(parents=True, exist_ok=True)
    metas = {}
    for name, spec in cfg.items():
        if not (raw / f"{spec.get('source', name)}.png").exists():
            print(f"  miss {name}")
            continue
        m = bake(raw, out, name, spec)
        if m:
            metas[name] = m
    (out / "silhouettes.json").write_text(json.dumps(metas, indent=1))
    if "--sheet" in sys.argv:
        contact_sheet(out, list(metas), sys.argv[sys.argv.index("--sheet") + 1])
