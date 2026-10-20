#!/usr/bin/env python3
"""Browser smoke/performance measurements; this is not a human playtest."""
import json, re, os
from pathlib import Path
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout
OUT=Path('build/review-results/browser');OUT.mkdir(parents=True,exist_ok=True)
GPU=os.environ.get('UMBRA_BROWSER_GPU')=='1'
PROFILE=os.environ.get('UMBRA_BROWSER_PROFILE')=='1'
IDLE=os.environ.get('UMBRA_BROWSER_IDLE')=='1'
PREFIX=('idle-' if IDLE else '')+('profile-' if PROFILE else '')+('gpu-' if GPU else '')
PROBE="""window.audioProbe={contexts:0,active:0,peak:0};const AC=window.AudioContext;window.AudioContext=class extends AC{constructor(...a){super(...a);audioProbe.contexts++;}createBufferSource(){const s=super.createBufferSource();const start=s.start.bind(s),stop=s.stop.bind(s);let live=false;const done=()=>{if(live){live=false;audioProbe.active--;}};s.start=(...a)=>{live=true;audioProbe.active++;audioProbe.peak=Math.max(audioProbe.peak,audioProbe.active);return start(...a);};s.stop=(...a)=>{done();return stop(...a);};s.addEventListener('ended',done);return s;}};
localStorage.setItem('flutter.umbra.campaign.v2',JSON.stringify(JSON.stringify({version:2,furthest:'dawn',chapter:'home',checkpoint:null})));"""
FPS="""() => new Promise(done=>{let last=performance.now(),start=last,frames=[];const tick=(t)=>{frames.push(t-last);last=t;if(t-start<3000)requestAnimationFrame(tick);else {frames.sort((a,b)=>a-b);done({fps:frames.length*1000/(t-start),medianMs:frames[Math.floor(frames.length*.5)],p95Ms:frames[Math.floor(frames.length*.95)]});}};requestAnimationFrame(tick);})"""
def activate(locator):
 locator.wait_for()
 locator.evaluate('(e)=>e.click()')

def pause_ready(page):
 page.mouse.click(480,270)
 for _ in range(40):
  page.keyboard.press('Escape')
  try:
   page.get_by_role('button',name='RESET SETTINGS',exact=True).wait_for(timeout=3000)
   return
  except PlaywrightTimeout:
   pass
 raise AssertionError('Chapter never became pausable')

report={'platform':'Linux headless Chromium, 960x540, '+('hardware GPU enabled' if GPU else 'software rendering'),'interaction':'Flutter accessibility actions and keyboard','humanPlaytest':False,'concurrentBuildsAndTests':not IDLE,'errors':[],'scenes':[]}
with sync_playwright() as p:
 b=p.chromium.launch(headless=True,channel='chromium' if GPU else None,args=['--enable-precise-memory-info','--disable-background-timer-throttling','--disable-renderer-backgrounding']+(['--enable-gpu','--use-angle=gl','--ignore-gpu-blocklist'] if GPU else []))
 page=b.new_page(viewport={'width':960,'height':540});page.set_default_timeout(60000);page.add_init_script(PROBE)
 cdp=page.context.new_cdp_session(page)
 page.on('pageerror',lambda e:report['errors'].append(str(e)))
 page.on('console',lambda m:report['errors'].append(m.text) if m.type=='error' else None)
 page.on('response',lambda r:report['errors'].append(f'HTTP {r.status} {r.url}') if r.status>=400 else None)
 page.goto('http://127.0.0.1:8765/');page.wait_for_load_state('networkidle',timeout=60000);page.wait_for_timeout(5000)
 report['renderer']=page.evaluate('''() => {const c=document.createElement('canvas'),g=c.getContext('webgl');if(!g)return 'No WebGL';const e=g.getExtension('WEBGL_debug_renderer_info');const r=e?g.getParameter(e.UNMASKED_RENDERER_WEBGL):g.getParameter(g.RENDERER);g.getExtension('WEBGL_lose_context')?.loseContext();return r;}''')
 page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()');page.wait_for_timeout(300)
 scenes=[(37,'Last Watch')] if PROFILE else [(6,'The Cage'),(25,'The Children'),(30,'Black Reservoir'),(37,'Last Watch'),(6,'The Cage'),(25,'The Children')]
 for n,title in scenes:
  activate(page.get_by_role('button',name='Chapters',exact=True));page.wait_for_timeout(300)
  rows=page.locator('body').inner_text();assert 'XL Dawn' in rows
  activate(page.get_by_role('button',name=re.compile(r' '+re.escape(title)+r' (Replay|Current)$')))
  print('Entered',title,flush=True)
  pause_ready(page)
  activate(page.get_by_role('button',name='RESUME',exact=True))
  page.get_by_role('button',name='RESUME',exact=True).wait_for(state='hidden')
  page.mouse.click(480,270);page.wait_for_timeout(3000)
  page.keyboard.down('d');page.wait_for_timeout(1000);page.keyboard.up('d')
  if IDLE:
   page.wait_for_timeout(15000)
  if PROFILE:
   cdp.send('Profiler.enable')
   cdp.send('Profiler.start')
  timing=page.evaluate(FPS)
  if PROFILE:
   cpu=cdp.send('Profiler.stop')['profile']
   (OUT/f'{PREFIX}cpu.json').write_text(json.dumps(cpu))
  before_gc=page.evaluate('performance.memory.usedJSHeapSize')
  cdp.send('HeapProfiler.collectGarbage')
  scene={'chapter':n,'timing':timing,'heapBeforeGcBytes':before_gc,'retainedHeapBytes':page.evaluate('performance.memory.usedJSHeapSize'),'audio':page.evaluate('audioProbe')}
  report['scenes'].append(scene);print(scene,flush=True)
  page.screenshot(path=str(OUT/f'{PREFIX}chapter-{n}.png'))
  pause_ready(page)
  activate(page.get_by_role('button',name='RESET SETTINGS',exact=True))
  activate(page.get_by_role('button',name='MAIN MENU',exact=True));page.get_by_role('button',name='Chapters',exact=True).wait_for();page.wait_for_timeout(15000)
 report['audio']=page.evaluate('audioProbe')
 assert report['audio']['contexts']==1
 assert report['audio']['peak']<=12
 report['settingsPreservedProgress']=page.evaluate("JSON.parse(JSON.parse(localStorage.getItem('flutter.umbra.campaign.v2'))).furthest==='dawn'")
 assert report['settingsPreservedProgress']
 b.close()
(OUT/f'{PREFIX}report.json').write_text(json.dumps(report,indent=2)+'\n')
assert not report['errors'],report['errors']
