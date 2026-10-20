#!/usr/bin/env python3
"""Move unbundled source artwork into a recoverable, checksummed local archive."""
import hashlib, json, shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
ARCHIVE=ROOT.parent/'Umbra-source-archive'/'campaign40-2026-10-19'
paths=[]
for sub in ['assets/design/campaign40','assets/design/retired-plates','assets/design/background-samples']:
    paths.extend((ROOT/sub).glob('*.png'))
paths.extend((ROOT/'assets/images/backgrounds').glob('chapter_*.png'))
paths.extend((ROOT/'assets/images/white_trees').glob('*.png'))
for name in ['assets/design/audio/vampires_piano_cc0.wav','assets/design/enemy-concept.png','assets/design/mother-concept.png']:
    p=ROOT/name
    if p.exists(): paths.append(p)
manifest_path=ROOT/'assets/design/archive-manifest.json'
manifest=json.loads(manifest_path.read_text()) if manifest_path.exists() else {'archive':str(ARCHIVE),'files':[]}
for source in sorted(paths):
    rel=str(source.relative_to(ROOT)); data=source.read_bytes(); digest=hashlib.sha256(data).hexdigest()
    target=ARCHIVE/rel;target.parent.mkdir(parents=True,exist_ok=True)
    if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest()!=digest:
        raise RuntimeError(f'Archive conflict: {target}')
    shutil.copy2(source,target)
    assert hashlib.sha256(target.read_bytes()).hexdigest()==digest
    manifest['files'].append({'path':rel,'bytes':len(data),'sha256':digest})
    source.unlink()
manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
print(f"Archived {len(paths)} files outside repository; manifest: {manifest_path}")
