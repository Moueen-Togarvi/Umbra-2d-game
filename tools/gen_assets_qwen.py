#!/usr/bin/env python3
"""Generate Limbo-style layers with Alibaba Model Studio (Qwen-Image) and save PNGs.

usage: gen_qwen.py <out_dir> <specs.json>
Key is read from ~/"alibaba cloud qwe 3.8.txt" (or $DASHSCOPE_API_KEY) and never printed.
"""
import json, os, pathlib, re, sys, time, urllib.request, urllib.error

def load_key():
    k = os.environ.get("DASHSCOPE_API_KEY")
    if k: return k
    txt = open(os.path.expanduser("~/alibaba cloud qwe 3.8.txt")).read()
    return re.search(r'sk-\S+', txt).group(0)

KEY = load_key()
HOST = os.environ.get("DASHSCOPE_HOST", "dashscope-intl.aliyuncs.com")
MODEL = os.environ.get("GEN_MODEL", "qwen-image-plus")
URL = f"https://{HOST}/api/v1/services/aigc/multimodal-generation/generation"

def generate(name, prompt, size, out, negative=""):
    dest = out / f"{name}.png"
    if dest.exists():
        print(f"  skip {name}"); return True
    body = {"model": MODEL,
            "input": {"messages": [{"role": "user", "content": [{"text": prompt}]}]},
            "parameters": {"size": size, "n": 1, "prompt_extend": False, "watermark": False}}
    if negative:
        body["parameters"]["negative_prompt"] = negative
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                d = json.load(r)
            url = d["output"]["choices"][0]["message"]["content"][0]["image"]
            with urllib.request.urlopen(url, timeout=300) as r:
                dest.write_bytes(r.read())
            print(f"  ok   {name} ({dest.stat().st_size//1024} KB)")
            return True
        except urllib.error.HTTPError as e:
            msg = e.read()[:300]
            print(f"  HTTP {e.code} on {name}: {msg}")
            if e.code in (429, 500, 503): time.sleep(5 * (attempt + 1)); continue
            return False
        except Exception as e:
            print(f"  ERR {name}: {e}"); time.sleep(3)
    return False

if __name__ == "__main__":
    out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    specs = json.load(open(sys.argv[2]))
    ok = sum(generate(s["name"], s["prompt"], s.get("size", "1664*928"), out, s.get("negative", "")) for s in specs)
    print(f"\n{ok}/{len(specs)} generated")
