"""Publish the 60 unmodified Flutter review captures after capture_chapters_test."""
import html
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/review-results/all-backgrounds'
OUT.mkdir(parents=True, exist_ok=True)
chapters = []
for manifest in sorted((ROOT / 'build/chapters-preview/backgrounds').glob('*/manifest.json')):
    areas = json.loads(manifest.read_text())
    assert len(areas) == 4
    chapters.append((manifest.parent.name, areas))
assert len(chapters) == 40, 'Capture all 40 chapters first'
nav, sections = [], []
for directory, areas in chapters:
    n, title = areas[0]['chapter'], html.escape(areas[0]['title'])
    nav.append(f'<a href="#ch{n}">{n:02d} {title}</a>')
    figures = []
    for area in areas:
        src = f'../../chapters-preview/backgrounds/{directory}/{area["image"]}'
        name = html.escape(area['name'])
        figures.append(f'<figure><a href="{src}" target="_blank"><img src="{src}" alt="{title} — {name}" loading="lazy" width="1600" height="720"></a><figcaption><b>{area["area"]:02d} / {name}</b><span>In-game capture · x {area["x"]:.1f} m</span></figcaption></figure>')
    atlas = '../../../assets/images/backgrounds/' + json.loads((ROOT / 'tools/campaign40.json').read_text())[n - 1]['id'] + '.webp'
    sections.append(f'<section id="ch{n}"><header><h2>{n:02d} / {title}</h2><a href="{atlas}" target="_blank">Background artwork ↗</a></header><div class="grid">{"".join(figures)}</div></section>')
page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Umbra — all 40 chapter backgrounds</title><style>
:root{color-scheme:dark;font-family:system-ui,sans-serif;background:#111;color:#e5e5e5}*{box-sizing:border-box}body{margin:0;padding:38px;max-width:1800px;margin:auto}a{color:#ddd;text-underline-offset:4px}h1{font:42px Georgia,serif;margin:15px 0}p{color:#aaa;line-height:1.7;max-width:850px}.eyebrow{font-size:11px;letter-spacing:3px;color:#aaa}.links{display:flex;flex-wrap:wrap;gap:10px;margin:24px 0}.links a{border:1px solid #555;padding:12px 18px;text-decoration:none}nav{display:flex;gap:8px;flex-wrap:wrap;margin:28px 0 45px}nav a{font-size:12px;border:1px solid #333;padding:8px;text-decoration:none}section{margin:0 0 46px;scroll-margin:24px}header{display:flex;justify-content:space-between;align-items:center;gap:20px}header a{font-size:12px}h2{font-size:20px;font-weight:500}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}figure{margin:0;background:#191919;border:1px solid #303030}img{width:100%;height:auto;display:block}figcaption{padding:14px;display:flex;justify-content:space-between;gap:10px;font-size:12px}figcaption b{font-weight:500}figcaption span{color:#999}body.overview .grid{grid-template-columns:repeat(4,minmax(0,1fr));gap:10px}body.overview figcaption{display:block}body.overview figcaption span{display:none}body.overview section{margin-bottom:20px}button{background:#222;border:1px solid #555;padding:12px 18px;color:#ddd;cursor:pointer}footer{border-top:1px solid #333;padding:25px 0;font-size:13px;color:#aaa}@media(max-width:760px){body{padding:20px}.grid,body.overview .grid{grid-template-columns:1fr}h1{font-size:32px}figcaption{display:block}figcaption span{display:block;margin-top:7px}}
</style><div class="eyebrow">UMBRA / BACKGROUNDS APPLIED</div><h1>40 chapters. 160 places.</h1><p>Four distinct backgrounds in every chapter, with gentle camera panning and gradual transitions. These are frozen frames rendered by the actual Flutter game. The hero, terrain colors and physical level layout are preserved.</p><div class="links"><a href="../../mother-preview/" target="_blank">Play updated game ↗</a><button onclick="document.body.classList.toggle('overview')">Compact overview</button></div><nav>'''
page += ''.join(nav) + '</nav>' + ''.join(sections)
page += '<footer>Background artwork is generated original art. Captures use test-only camera/player positioning to inspect each location; they are not a recorded playthrough. Backgrounds contain no collisions. Existing moving objects, weather, lights and gameplay remain live in the game.</footer></html>'
(OUT / 'index.html').write_text(page)
character_files = [
    ('Mother — reference portrait, one reach', '../../chapters-preview/characters/mother_doorway.png'),
    ('Mother — arm lowered after the single gesture', '../../chapters-preview/characters/mother_rested.png'),
    ('Vampire — in the game beside the unchanged hero', '../../chapters-preview/characters/vampire_scene.png'),
    ('Animated character renderers — enlarged', '../../chapters-preview/review/figures.png'),
]
character_page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Umbra — mother and vampire applied</title><style>body{background:#111;color:#ddd;font:16px system-ui;margin:32px auto;padding:0 24px;max-width:1400px}h1{font:38px Georgia}p{color:#aaa;line-height:1.7}a{color:#ddd}img{width:100%;height:auto;display:block;border:1px solid #333}section{margin:40px 0}h2{font-size:19px;font-weight:500}nav{display:flex;gap:24px;flex-wrap:wrap}small{color:#999}</style><h1>Mother & vampire — applied in game</h1><p>Mother uses the approved portrait as a transparent cutout with one shoulder-driven reach, then rests. She keeps her bun, shawl and long dress; the vampire has the swept hair, high collar, tailored coat and claws. The hero boy is unchanged.</p><nav><a href="../../mother-preview/">Play updated game</a><a href="index.html">All 60 chapter backgrounds</a><a href="changed-files.txt">Changed files</a><a href="tests.txt">Test log</a></nav>'''
for title, src in character_files:
    if (OUT / src).exists():
        character_page += f'<section><h2>{html.escape(title)}</h2><a href="{src}"><img src="{src}" alt="{html.escape(title)}"></a></section>'
character_page += '<small>Actual Flutter renders. Close-up camera positioning is used for inspection. Mother is isolated from the reference using imagegen and her arm moves once. Vampire artwork uses separate parts reconstructed from its reference. Movement follows the game state.</small></html>'
(OUT / 'characters.html').write_text(character_page)
page = page.replace('<button onclick=', '<a href="characters.html">Mother & vampire screenshots ↗</a><button onclick=', 1)
(OUT / 'index.html').write_text(page)
files = subprocess.check_output(['git', 'diff', '--name-only'], cwd=ROOT, text=True).splitlines()
files += subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard'], cwd=ROOT, text=True).splitlines()
(OUT / 'changed-files.txt').write_text('\n'.join(sorted(set(files))) + '\n')
for source, target in [('final-tests.log', 'tests.txt'), ('final-analysis.log', 'analysis.txt'), ('mother-web.log', 'web-build.txt'), ('final-captures.log', 'captures.txt'), ('mother-final-capture.log', 'mother-captures.txt')]:
    if (ROOT / 'build' / source).exists():
        shutil.copyfile(ROOT / 'build' / source, OUT / target)
print(OUT / 'index.html')
