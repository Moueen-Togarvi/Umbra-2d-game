"""Publish the 60 unmodified Flutter review captures after capture_chapters_test."""
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/review-results/all-backgrounds'
OUT.mkdir(parents=True, exist_ok=True)
chapters = []
for manifest in sorted((ROOT / 'build/chapters-preview/backgrounds').glob('*/manifest.json')):
    areas = json.loads(manifest.read_text())
    assert len(areas) == 4
    chapters.append((manifest.parent.name, areas))
assert len(chapters) == 15, 'Capture all 15 chapters first'
nav, sections = [], []
for directory, areas in chapters:
    n, title = areas[0]['chapter'], html.escape(areas[0]['title'])
    nav.append(f'<a href="#ch{n}">{n:02d} {title}</a>')
    figures = []
    for area in areas:
        src = f'../../chapters-preview/backgrounds/{directory}/{area["image"]}'
        name = html.escape(area['name'])
        figures.append(f'<figure><a href="{src}" target="_blank"><img src="{src}" alt="{title} — {name}" loading="lazy" width="1600" height="720"></a><figcaption><b>{area["area"]:02d} / {name}</b><span>In-game capture · x {area["x"]:.1f} m</span></figcaption></figure>')
    atlas = f'../../../assets/images/backgrounds/chapter_{n:02d}.png'
    sections.append(f'<section id="ch{n}"><header><h2>{n:02d} / {title}</h2><a href="{atlas}" target="_blank">Background artwork ↗</a></header><div class="grid">{"".join(figures)}</div></section>')
page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Umbra — all 15 chapter backgrounds</title><style>
:root{color-scheme:dark;font-family:system-ui,sans-serif;background:#111;color:#e5e5e5}*{box-sizing:border-box}body{margin:0;padding:38px;max-width:1800px;margin:auto}a{color:#ddd;text-underline-offset:4px}h1{font:42px Georgia,serif;margin:15px 0}p{color:#aaa;line-height:1.7;max-width:850px}.eyebrow{font-size:11px;letter-spacing:3px;color:#aaa}.links{display:flex;flex-wrap:wrap;gap:10px;margin:24px 0}.links a{border:1px solid #555;padding:12px 18px;text-decoration:none}nav{display:flex;gap:8px;flex-wrap:wrap;margin:28px 0 45px}nav a{font-size:12px;border:1px solid #333;padding:8px;text-decoration:none}section{margin:0 0 46px;scroll-margin:24px}header{display:flex;justify-content:space-between;align-items:center;gap:20px}header a{font-size:12px}h2{font-size:20px;font-weight:500}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}figure{margin:0;background:#191919;border:1px solid #303030}img{width:100%;height:auto;display:block}figcaption{padding:14px;display:flex;justify-content:space-between;gap:10px;font-size:12px}figcaption b{font-weight:500}figcaption span{color:#999}body.overview .grid{grid-template-columns:repeat(4,minmax(0,1fr));gap:10px}body.overview figcaption{display:block}body.overview figcaption span{display:none}body.overview section{margin-bottom:20px}button{background:#222;border:1px solid #555;padding:12px 18px;color:#ddd;cursor:pointer}footer{border-top:1px solid #333;padding:25px 0;font-size:13px;color:#aaa}@media(max-width:760px){body{padding:20px}.grid,body.overview .grid{grid-template-columns:1fr}h1{font-size:32px}figcaption{display:block}figcaption span{display:block;margin-top:7px}}
</style><div class="eyebrow">UMBRA / BACKGROUNDS APPLIED</div><h1>15 chapters. 60 places.</h1><p>Four distinct backgrounds in every chapter, with gentle camera panning and gradual transitions. These are frozen frames rendered by the actual Flutter game. The hero, terrain colors and physical level layout are preserved.</p><div class="links"><a href="../../web/" target="_blank">Play updated game ↗</a><button onclick="document.body.classList.toggle('overview')">Compact overview</button></div><nav>'''
page += ''.join(nav) + '</nav>' + ''.join(sections)
page += '<footer>Background artwork is generated original art. Captures use test-only camera/player positioning to inspect each location; they are not a recorded playthrough. Backgrounds contain no collisions. Existing moving objects, weather, lights and gameplay remain live in the game.</footer></html>'
(OUT / 'index.html').write_text(page)
print(OUT / 'index.html')
