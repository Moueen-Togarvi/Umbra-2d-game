#!/usr/bin/env python3
"""Crop the boy out of captured frames into a contact sheet.

    flutter test tool/capture/capture_frames_test.dart
    python3 tools/contact_sheet.py run [--cols 6] [--zoom 2.2] [--box 2.2]

Reads build/limbo-preview/scenes.json (written by the capture harness), crops
a square of `--box` metres around the player's position in every frame of the
scene, scales it by `--zoom` and tiles the crops into
build/limbo-preview/<scene>_sheet.png.
"""
import argparse
import json
import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path("build/limbo-preview")

parser = argparse.ArgumentParser()
parser.add_argument("scene")
parser.add_argument("--cols", type=int, default=6)
parser.add_argument("--box", type=float, default=2.2, help="crop size, metres")
parser.add_argument("--cell", type=int, default=200, help="cell size, pixels")
parser.add_argument("--rise", type=float, default=0.15, help="shift crop up, metres")
args = parser.parse_args()

frames = json.loads((ROOT / "scenes.json").read_text())[args.scene]
rows = (len(frames) + args.cols - 1) // args.cols
sheet = Image.new("RGB", (args.cols * args.cell, rows * args.cell), (40, 0, 0))
draw = ImageDraw.Draw(sheet)
for i, frame in enumerate(frames):
    image = Image.open(ROOT / frame["file"]).convert("RGB")
    half = args.box * frame["ppm"] / 2
    cx, cy = frame["x"], frame["y"] - args.rise * frame["ppm"]
    crop = image.crop((int(cx - half), int(cy - half), int(cx + half), int(cy + half)))
    crop = crop.resize((args.cell - 2, args.cell - 2), Image.LANCZOS)
    x, y = (i % args.cols) * args.cell, (i // args.cols) * args.cell
    sheet.paste(crop, (x, y))
    draw.text((x + 3, y + 2), f"{i} {frame['state']}", fill=(255, 80, 80))
target = ROOT / f"{args.scene}_sheet.png"
sheet.save(target)
print(target)
