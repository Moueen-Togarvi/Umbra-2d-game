#!/usr/bin/env python3
"""Bake the chapter-end gates for the game.

usage: bake_exit_gates.py

Reads the generated gate art in assets/images/chapter_exits/ (1254 px
squares, transparent round the gate), crops each to what is drawn, scales
it to 600 px high and writes assets/images/exits/<name>.webp. The game
stands each at its chapter's end (lib/render/chapter_exit_gate.dart).
"""
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'assets/images/chapter_exits'
OUT = ROOT / 'assets/images/exits'
HIGH = 600


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for path in sorted(SOURCE.glob('*.png')):
        image = Image.open(path).convert('RGBA')
        # What is drawn: the alpha above a faint fringe.
        box = image.getchannel('A').point(lambda a: 255 if a > 32 else 0).getbbox()
        gate = image.crop(box)
        width = round(gate.width * HIGH / gate.height)
        gate = gate.resize((width, HIGH), Image.LANCZOS)
        name = path.stem.split('_')[0]  # ch01 … ch15
        gate.save(OUT / f'{name}.webp', 'WEBP', quality=86, method=6)
        print(name, gate.size)


if __name__ == '__main__':
    main()
