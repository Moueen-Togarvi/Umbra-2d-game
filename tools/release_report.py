#!/usr/bin/env python3
"""Inspect completed APKs; never substitute estimates for artifact sizes."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile


def android_aapt():
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not sdk:
        properties = Path('android/local.properties').read_text()
        sdk = re.search(r'^sdk.dir=(.+)$', properties, re.M).group(1)
    versions = list((Path(sdk) / 'build-tools').glob('*/aapt'))
    return max(versions, key=lambda p: tuple(int(x) for x in p.parent.name.split('.')))


def inspect(path, aapt):
    badging = subprocess.check_output([str(aapt), 'dump', 'badging', str(path)], text=True)
    package = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging)
    with zipfile.ZipFile(path) as apk:
        names = apk.namelist()
        abis = sorted({name.split('/')[1] for name in names if name.startswith('lib/')})
        paintings = [name for name in names if '/backgrounds/' in name and name.endswith('.webp')]
        assert len(paintings) == 40, f'{path}: expected all forty paintings, got {len(paintings)}'
    size = path.stat().st_size
    with path.open('rb') as source:
        checksum = hashlib.file_digest(source, 'sha256').hexdigest()
    return dict(path=str(path), bytes=size, MB=round(size / 1e6, 2),
                MiB=round(size / 2**20, 2), abis=abis,
                sha256=checksum,
                package=package.group(1), versionCode=int(package.group(2)),
                versionName=package.group(3), backgroundAtlases=len(paintings))


if __name__ == '__main__':
    aapt = android_aapt()
    root = Path('build/releases')
    records = [inspect(root / f'umbra-0.3.0-{kind}.apk', aapt)
               for kind in ('arm64', 'universal')]
    assert records[0]['abis'] == ['arm64-v8a']
    assert records[0]['versionCode'] == records[1]['versionCode'] == 3
    assert all(r['versionName'] == '0.3.0' for r in records)
    (root / 'artifacts.json').write_text(json.dumps(records, indent=2) + '\n')
    print(json.dumps(records, indent=2))
