#!/usr/bin/env python3
"""Rebuild every chapter's background atlas from clean panels only.

usage: build_clean_backgrounds.py

The backgrounds are atmosphere and nothing else: sky, fog, hills, woods,
cliffs, sea, caves. No houses, roads, fences, bridges, walls, chains or
stairs, which read as things to walk on or to reach. Panels come from the
painted atlases as they were at SOURCE (so a re-run gives the same result)
and may be mirrored; each chapter gets four different ones.

Writes assets/images/backgrounds/<id>.webp (2 x 2 panels, 1672 x 941).
"""
import io
import pathlib
import subprocess

from PIL import Image, ImageFilter, ImageOps, ImageStat

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = '55f28ce'
PANEL = (836, 470)

# How bright the band that shows behind play must be, at least, out of 255:
# open country near Home's (dusk fields), caves a little darker.
OPEN_LIGHT = 70
CAVE_LIGHT = 55
SIZE = (1672, 941)

# Open country: fields, woods, hills, cliffs and sea.
OUT = {
    'home': ['home_2', 'home_3', 'dawn_0', 'dawn_1'],
    'old_orchard': ['old_orchard_3', 'home_2~', 'dawn_1~', 'forest_0'],
    'hunters_road': ['eastern_woods_0', 'forest_1', 'eastern_woods_1', 'forest_2'],
    'graveyard': ['forest_0~', 'eastern_woods_2', 'forest_2~', 'home_3~'],
    'forest': ['forest_0', 'forest_1', 'forest_2', 'eastern_woods_2~'],
    'watchers_walk': ['storm_3', 'last_watch_3', 'storm_0~', 'old_orchard_3~'],
    'broken_aqueduct': ['storm_2', 'storm_3~', 'last_watch_3~', 'eastern_woods_0~'],
    'black_reservoir': ['eastern_woods_2', 'eastern_woods_1~', 'storm_0', 'forest_1~'],
    'outer_ramparts': ['storm_0', 'storm_2~', 'last_watch_3', 'storm_3'],
    'great_gate': ['last_watch_3', 'storm_3', 'eastern_woods_0', 'storm_2'],
    'moat': ['eastern_woods_1', 'eastern_woods_2~', 'home_3', 'forest_2'],
    'storm': ['storm_0', 'storm_2', 'storm_3', 'shattered_coast_1~'],
    'shattered_coast': ['shattered_coast_0', 'shattered_coast_1', 'storm_2~', 'storm_0~'],
    'last_watch': ['last_watch_3', 'storm_3~', 'old_orchard_3', 'eastern_woods_0~'],
    'eastern_woods': ['eastern_woods_0', 'eastern_woods_1', 'eastern_woods_2', 'forest_0~'],
    'homeward_road': ['home_3~', 'old_orchard_3~', 'dawn_1', 'home_2'],
    'dawn': ['dawn_0', 'dawn_1', 'home_2', 'last_watch_3~'],
}
# Underground and within the castle: caves, in turn, never one twice.
CAVES = ['cage_3', 'caves_0', 'caves_1', 'caves_2', 'caves_3', 'drowned_quarry_3']
INSIDE = [
    'cage', 'chainworks', 'caves', 'sluice_tunnels', 'drowned_quarry', 'crypt',
    'coffin_gallery', 'bone_pit', 'floodworks', 'lower_castle', 'chase',
    'servants_passage', 'halls', 'shadow_gallery', 'chandeliers', 'organ_loft',
    'clock_tower', 'bell_foundry', 'children', 'abandoned_ward', 'drainways',
    'mill', 'furnace_passage',
]


def plan():
    out = dict(OUT)
    for j, chapter in enumerate(INSIDE):
        out[chapter] = [
            CAVES[(j + step) % len(CAVES)] + ('~' if (j + k) % 2 else '')
            for k, step in enumerate((0, 1, 3, 4))
        ]
    return out


_atlases = {}


def panel(name):
    mirrored = name.endswith('~')
    chapter, index = name.rstrip('~').rsplit('_', 1)
    if chapter not in _atlases:
        data = subprocess.run(
            ['git', 'show', f'{SOURCE}:assets/images/backgrounds/{chapter}.webp'],
            cwd=ROOT, capture_output=True, check=True).stdout
        _atlases[chapter] = Image.open(io.BytesIO(data)).convert('RGB')
    atlas = _atlases[chapter]
    w, h = atlas.width // 2, atlas.height // 2
    k = int(index)
    image = atlas.crop(((k % 2) * w, (k // 2) * h, (k % 2 + 1) * w, (k // 2 + 1) * h))
    image = image.resize(PANEL, Image.LANCZOS)
    target = CAVE_LIGHT if chapter.rstrip('~') + '_' + index in CAVES else OPEN_LIGHT
    image = lifted(image, target)
    image = calmed(image)
    return ImageOps.mirror(image) if mirrored else image


def calmed(image):
    """The painted moons and suns are full of bright speckle (pixels
    clipped to white in the source): soften only there, so they glow
    instead of fizzing."""
    grey = image.convert('L')
    mask = grey.point(lambda v: 255 if v > 175 else 0).filter(
        ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(6))
    soft = image.filter(ImageFilter.MedianFilter(7)).filter(
        ImageFilter.GaussianBlur(3))
    return Image.composite(soft, image, mask)


def seen(image):
    """How bright the part of a panel that shows behind play is: the
    middle and lower bands (the top is mostly above the screen)."""
    w, h = image.size
    band = image.convert('L').crop((0, int(h * .3), w, int(h * .9)))
    return ImageStat.Stat(band).mean[0]


def lifted(image, target):
    """Brightened to [target] where it shows, by a gamma that lifts the
    dark without blowing out the light; left alone if already bright."""
    if seen(image) >= target:
        return image
    low, high = 0.3, 1.0
    for _ in range(18):
        g = (low + high) / 2
        lut = [round(255 * (v / 255) ** g) for v in range(256)]
        if seen(image.point(lut * len(image.getbands()))) < target:
            high = g
        else:
            low = g
    lut = [round(255 * (v / 255) ** low) for v in range(256)]
    return image.point(lut * len(image.getbands()))


def main():
    chapters = plan()
    # Read every source first: the atlases written below are sources too.
    panels = {name: panel(name) for names in chapters.values() for name in names}
    for chapter, names in chapters.items():
        assert len(set(n.rstrip('~') for n in names)) == 4, chapter
        sheet = Image.new('RGB', SIZE, (0, 0, 0))
        for k, name in enumerate(names):
            sheet.paste(panels[name], ((k % 2) * PANEL[0], (k // 2) * PANEL[1]))
        sheet.save(ROOT / f'assets/images/backgrounds/{chapter}.webp', 'WEBP',
                   quality=88, method=6)
        print(chapter, names)


if __name__ == '__main__':
    main()
