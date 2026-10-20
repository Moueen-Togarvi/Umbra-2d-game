#!/usr/bin/env python3
"""Bound long audio size and report decoded loop-boundary discontinuities."""
import json, subprocess, pathlib
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[1]
report=[]
for folder,rate in [('music',80000),('loops',64000)]:
    for p in sorted((ROOT/'assets/audio'/folder).glob('*.ogg')):
        meta=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-of','json',str(p)]))['format']
        duration=float(meta['duration']);before=p.stat().st_size
        if before*8/duration > rate*1.15:
            backup=ROOT/'build/upgrade-baseline/audio-originals'/folder/p.name
            backup.parent.mkdir(parents=True,exist_ok=True)
            if not backup.exists():backup.write_bytes(p.read_bytes())
            target=p.with_suffix('.optimized.ogg')
            subprocess.run(['ffmpeg','-v','error','-y','-i',str(backup),'-c:a','libvorbis','-b:a',str(rate),str(target)],check=True)
            if target.stat().st_size < before:target.replace(p)
            else:target.unlink()
        raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(p),'-f','f32le','-ac','1','-ar','22050','-'])
        data=np.frombuffer(raw,np.float32)
        diff=abs(float(data[-1]-data[0]));local=float(np.sqrt(np.mean(np.diff(data)**2)))
        report.append({'path':str(p.relative_to(ROOT)),'seconds':duration,'bytes':p.stat().st_size,
            'boundary_jump':round(diff,6),'typical_sample_delta_rms':round(local,6),
            'listening_required':True})
out=ROOT/'build/review-results/audio-loop-report.json';out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(json.dumps(report,indent=2)+'\n')
print(f'{len(report)} tracks checked; {sum(r["bytes"] for r in report)/1024**2:.1f} MiB')
