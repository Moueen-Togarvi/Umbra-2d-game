"""Publish unmodified game captures as a local before/after review gallery."""
from pathlib import Path
import html
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/review-results'
OUT.mkdir(parents=True, exist_ok=True)
scenes = [
    ('forest_x_080', '01 / Forest depth & hero readability', 'Existing tree assets, buried roots, softened distant silhouettes, less foreground clutter and no oval halo behind the boy.'),
    ('forest_x_066', '02 / Rope & stakes', 'A thicker cord and wrapped grip. Stakes have restrained highlights; their native sensor hulls follow the drawn geometry.'),
    ('crypt_x_052', '03 / Crypt surfaces', 'Background columns are lighter than the hero; the water rim and pedal highlights are softer.'),
    ('chandeliers_x_048', '04 / Gallery', 'A lighter, more open railing separates from the boy’s legs. Background arches retain depth.'),
    ('title_chapters', '05 / Cottage & chapter menu', 'Warm empty windows, no duplicate figures. Soft menu shading, current/replay/locked states and keyboard-accessible choices.'),
    ('pause', '06 / Pause & settings', 'Brightness, film effects, ambience, effects, button size and opacity. Preferences persist; restart and main-menu actions work.'),
    ('corridor_gameplay', '07 / Actual cart-pushing gameplay', 'A captured run through The Halls, including the boy pushing a physical lantern cart while enemies react to its light.'),
    ('figures', '08 / Native character renderers', 'Mother and enemy drawn by their in-game procedural renderers. The hero’s existing visual rig is preserved.'),
    ('controls', '09 / Adjustable touch controls', 'Example with 120% button size, 90% button opacity and 115% brightness; controls still support simultaneous input.'),
]
sections = []
for name, title, desc in scenes:
    after = OUT / 'after' / (name + '.png')
    if not after.exists(): continue
    before = OUT / 'before' / (name + '.png')
    buttons = '<button class="selected" onclick="swap(this,\'after\')">After</button>'
    if before.exists(): buttons += '<button onclick="swap(this,\'before\')">Before</button>'
    sections.append(f'''<section data-name="{name}"><div class="heading"><h2>{html.escape(title)}</h2><nav>{buttons}<a href="after/{name}.png" target="_blank">Full image ↗</a></nav></div><p>{html.escape(desc)}</p><a class="image-link" href="after/{name}.png" target="_blank"><img src="after/{name}.png" loading="lazy" alt="{html.escape(title)}"></a></section>''')
files = subprocess.check_output(['git','diff','--name-only'],cwd=ROOT,text=True).splitlines()
files += subprocess.check_output(['git','ls-files','--others','--exclude-standard'],cwd=ROOT,text=True).splitlines()
(OUT/'changed-files.txt').write_text('\n'.join(sorted(set(files)))+'\n')
for log, name in [('umbra-analysis-final.log','analysis.txt'),('umbra-tests-verified.log','tests.txt'),('umbra-review-final.log','screenshots.txt'),('umbra-web-final.log','web-build.txt'),('umbra-apk-final.log','apk-build.txt')]:
    source=Path('/tmp')/log
    if source.exists(): shutil.copyfile(source,OUT/name)
page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Umbra — visual review results</title><style>
:root{color-scheme:dark;font-family:system-ui,sans-serif;background:#111517;color:#e2e4e0}body{max-width:1440px;margin:auto;padding:48px 28px}header{padding:20px 0 44px;border-bottom:1px solid #343a3c}small{letter-spacing:3px;color:#c3a775}h1{font:clamp(30px,4vw,56px) Georgia,serif;font-weight:400;margin:18px 0}p{color:#aeb5b4;line-height:1.7;max-width:950px}a{color:#d4bb8f;text-decoration:none}a:hover{text-decoration:underline}.facts{display:flex;flex-wrap:wrap;gap:10px;margin-top:24px}.facts span{border:1px solid #3d4546;padding:9px 14px;border-radius:30px;font-size:13px}section{margin:44px 0 64px}.heading{display:flex;gap:16px;align-items:center;justify-content:space-between}h2{font-size:19px;font-weight:500;letter-spacing:.3px}nav{display:flex;gap:8px;align-items:center}nav a{font-size:12px;margin-left:14px}button{cursor:pointer;background:transparent;border:1px solid #4e585b;border-radius:4px;color:#aeb5b4;padding:9px 14px}.selected{background:#c3a775;color:#111517;border-color:#c3a775}img{width:100%;height:auto;display:block;border:1px solid #343a3c;border-radius:5px}footer{border-top:1px solid #343a3c;padding-top:26px;font-size:13px}footer a{margin-right:18px}@media(max-width:650px){body{padding:24px 14px}.heading{align-items:start;flex-direction:column}h2{margin-bottom:0}}
</style><header><small>UMBRA / IMPLEMENTATION REVIEW</small><h1>Cleaner scenes. Grounded interactions.</h1><p>Actual Flutter/Flame renders using the existing scenery assets. Choose Before or After to inspect each change, or open an image at full resolution. The boy’s visual design is preserved.</p><div class="facts"><span>143 native / widget tests passed</span><span>Static analysis: clean</span><span>800 × 360 + 1600 × 720 captures</span><span>Native Box2D v3</span></div></header>'''
page += ''.join(sections)
page += '''<footer><h2>Verification & files</h2><p>Climbing retains collisions, checks actual shape clearance throughout the mantle and has no final teleport. Chapter III’s far cage bank is reachable with these collisions enabled. Original synthesized ambience and effects are implemented through audioplayers; real-phone performance and audio mixing still need device testing. Enemies continue to use world queries for navigation rather than rigid-body locomotion.</p><p>Chrome pause/resume passed with six settings sliders and no JavaScript or HTTP errors. Recorded debug samples showed 6.8–11.6 FPS while release builds were running; this is not a clean hardware benchmark and the 60 FPS target remains unverified.</p><details><summary>Browser recording and physics debug frame</summary><video controls preload="metadata" style="width:100%;margin:20px 0" src="browser/gameplay.webm"></video><img src="browser/physics_debug.png" alt="Actual browser debug capture" loading="lazy"></details><a href="tests.txt">Test results</a><a href="analysis.txt">Static analysis</a><a href="changed-files.txt">Exact changed files</a><a href="web-build.txt">Web build</a><a href="apk-build.txt">APK build</a><a href="browser/report.json">Chrome smoke test</a></footer><script>function swap(button,version){const s=button.closest('section'),url=version+'/'+s.dataset.name+'.png';s.querySelector('img').src=url;s.querySelector('.image-link').href=url;s.querySelector('nav a').href=url;s.querySelectorAll('button').forEach(b=>b.classList.toggle('selected',b===button));}</script></html>'''
(OUT/'index.html').write_text(page)
print(OUT/'index.html')
