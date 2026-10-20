#!/usr/bin/env python3
"""Create a listening aid using the actual exported loops, without re-encoding."""
import html
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
rows = json.loads((root / 'build/review-results/audio-loop-report.json').read_text())
buttons = []
for row in rows:
    path = Path(row['path'])
    if path.stem == 'ending':
        continue
    buttons.append(f'<button data-src="../../{html.escape(str(path))}">{html.escape(path.stem)}</button>')
page = '''<!doctype html><html lang="en"><meta charset="utf-8"><title>Umbra loop listening review</title>
<style>body{max-width:900px;margin:4rem auto;padding:0 24px;background:#111;color:#ddd;font:18px/1.6 system-ui}button{padding:12px;margin:5px;background:#222;color:#eee;border:1px solid #666;cursor:pointer}audio{width:100%}#status{color:#d9b96f}</style>
<h1>Listen across the loop join</h1><p>Each button starts three seconds before the exported file ends, then loops to its beginning. Use headphones and note clicks, abrupt ambience changes or musical jumps. These are listening aids, not a listening-pass result.</p>
<audio id="player" controls loop></audio><p id="status">Choose a track.</p><div>''' + ''.join(buttons) + '''</div>
<script>const player=document.querySelector('audio'),status=document.querySelector('#status');document.querySelectorAll('button').forEach(button=>button.onclick=()=>{player.pause();status.textContent=button.textContent+' — end → start';player.src=button.dataset.src;player.onloadedmetadata=()=>{player.currentTime=Math.max(0,player.duration-3);player.play().catch(e=>status.textContent=e.message);};player.load();});</script></html>'''
out = root / 'build/review-results/loop-review.html'
out.write_text(page)
print(out)
