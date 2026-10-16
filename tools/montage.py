#!/usr/bin/env python3
"""Tiles captured frames into one sheet for review.

usage: montage.py <frames_dir> <out.png> [columns] [every_nth]
"""
import pathlib
import sys

from PIL import Image, ImageDraw


def main():
    d = pathlib.Path(sys.argv[1])
    out = sys.argv[2]
    cols = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    every = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    files = sorted(d.glob("*.png"))[::every]
    w, h = 400, 180
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * w, max(1, rows) * (h + 14)), (40, 40, 40))
    draw = ImageDraw.Draw(sheet)
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGB").resize((w, h))
        x, y = (i % cols) * w, (i // cols) * (h + 14)
        sheet.paste(im, (x, y))
        draw.text((x + 3, y + h), f.stem, fill=(255, 255, 0))
    sheet.save(out)
    print(len(files))


if __name__ == "__main__":
    main()
