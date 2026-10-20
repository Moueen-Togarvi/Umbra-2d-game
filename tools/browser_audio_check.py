import json
from pathlib import Path
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
 b=p.chromium.launch(headless=True)
 page=b.new_page()
 page.add_init_script('window.contextCount=0;const AC=window.AudioContext;window.AudioContext=class extends AC{constructor(...a){super(...a);window.contextCount++;}}')
 errors=[]
 page.on('pageerror',lambda e:errors.append(str(e)))
 page.goto('http://127.0.0.1:8766/')
 page.wait_for_load_state('networkidle',timeout=60000)
 page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()')
 page.get_by_role('button',name='Run audio checks',exact=True).click()
 page.get_by_text('"passed":',exact=False).wait_for(timeout=30000)
 text=page.locator('body').inner_text()
 print(text)
 result=json.loads(text[text.index('{'):text.rindex('}')+1])
 result['contexts']=page.evaluate('window.contextCount');result['errors']=errors
 Path('build/review-results/browser/audio-stress.json').write_text(json.dumps(result,indent=2)+'\n')
 assert result['passed'] and result['contexts']==1 and not errors,result
 b.close()
