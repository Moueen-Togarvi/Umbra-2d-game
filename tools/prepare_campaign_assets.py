#!/usr/bin/env python3
"""Export approved originals to runtime WebP; never modify source paintings."""
import json
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
rows = json.loads((ROOT / 'tools/campaign40.json').read_text())
def export():
    done=[]
    for row in rows:
        source = ROOT / f"assets/design/campaign40/{row['id']}.png"
        if not source.exists():
            source = ROOT.parent / 'Umbra-source-archive/campaign40-2026-10-19' / f"assets/design/campaign40/{row['id']}.png"
        if not source.exists() and row['legacy']:
            source = ROOT / f"assets/images/backgrounds/chapter_{row['legacy']:02}.png"
        target = ROOT / f"assets/images/backgrounds/{row['id']}.webp"
        if not source.exists(): continue
        if not target.exists() or source.stat().st_mtime > target.stat().st_mtime:
            with Image.open(source) as img:
                img.convert('RGB').save(target, 'WEBP', quality=80, method=6)
        done.append(row['id'])
    return done
if __name__ == '__main__':
    print(f'{len(export())}/40 chapter backgrounds exported')
