"""Smoke-test the release Flutter build in real Chrome and save unedited frames."""
from functools import partial
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import json
import threading
import time
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/review-results/browser'
OUT.mkdir(parents=True, exist_ok=True)
class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass
server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(ROOT / 'build/web')))
threading.Thread(target=server.serve_forever, daemon=True).start()
report = {'console_errors': [], 'page_errors': [], 'audio_requests': [], 'http_errors': []}
try:
    with sync_playwright() as p:
        browser = p.chromium.launch(channel='chrome', headless=False)
        context = browser.new_context(viewport={'width': 1280, 'height': 576}, record_video_dir=str(OUT), record_video_size={'width':1280,'height':576})
        page = context.new_page()
        page.on('console', lambda msg: report['console_errors'].append(msg.text) if msg.type == 'error' else None)
        page.on('response', lambda res: report['http_errors'].append({'url':res.url,'status':res.status}) if res.status >= 400 else None)
        page.on('pageerror', lambda error: report['page_errors'].append(str(error)))
        page.on('response', lambda res: report['audio_requests'].append({'url':res.url.split('/')[-1], 'status':res.status}) if '.wav' in res.url else None)
        page.goto(f'http://127.0.0.1:{server.server_port}/')
        page.wait_for_selector('flutter-view, flt-glass-pane', timeout=60000)
        time.sleep(5)
        placeholder = page.locator('flt-semantics-placeholder')
        if placeholder.count(): placeholder.dispatch_event('click')
        page.screenshot(path=str(OUT/'loaded.png'))
        page.get_by_role('button', name='Begin', exact=True).wait_for(timeout=30000)
        page.screenshot(path=str(OUT/'title.png'))
        page.get_by_role('button', name='Begin', exact=True).click()
        time.sleep(19)
        page.keyboard.down('d')
        time.sleep(.7)
        page.keyboard.press('Space')
        time.sleep(.35)
        page.screenshot(path=str(OUT/'jump.png'))
        page.keyboard.up('d')
        time.sleep(1)
        page.keyboard.press('F1')
        time.sleep(2)
        page.screenshot(path=str(OUT/'physics_debug.png'))
        page.keyboard.press('F1')
        page.keyboard.press('Escape')
        page.get_by_text('PAUSED', exact=True).wait_for(timeout=10000)
        report['sliders'] = page.get_by_role('slider').count()
        page.screenshot(path=str(OUT/'pause.png'))
        # Flutter's scroll semantics node can cover the button's DOM box.
        # Use a real pointer click at its measured position on the canvas.
        resume = page.get_by_role('button', name='RESUME', exact=True).bounding_box()
        page.mouse.click(resume['x'] + resume['width']/2, resume['y'] + resume['height']/2)
        time.sleep(.5)
        page.screenshot(path=str(OUT/'resumed.png'))
        report['resumed'] = page.get_by_text('PAUSED', exact=True).count() == 0
        assert report['resumed'], 'Pause menu did not close after the resume click'
        assert report['sliders'] == 6, 'Expected all six settings controls'
        assert not report['page_errors'], report['page_errors']
        assert not report['http_errors'], report['http_errors']
        video = page.video.path()
        context.close()
        browser.close()
        Path(video).replace(OUT/'gameplay.webm')
finally:
    server.shutdown()
    (OUT/'report.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2), flush=True)
