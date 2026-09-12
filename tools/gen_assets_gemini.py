#!/usr/bin/env python3
"""Generate Limbo-style parallax layers with the Gemini image API."""
import base64, json, os, sys, urllib.request, urllib.error, pathlib

KEY = open(os.path.expanduser("~/gemini api key.txt")).read().strip()
OUT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "raw")
OUT.mkdir(parents=True, exist_ok=True)
MODEL = os.environ.get("GEN_MODEL", "gemini-3-pro-image")
URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent"


def generate(name, prompt, aspect="16:9", size="2K"):
    dest = OUT / f"{name}.png"
    if dest.exists():
        print(f"  skip {name} (exists)")
        return True
    body = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "responseModalities": ["IMAGE"],
            "imageConfig": {"aspectRatio": aspect, "imageSize": size},
        },
    }
    req = urllib.request.Request(
        URL,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "x-goog-api-key": KEY},
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        print(f"  FAIL {name}: {e.code} {e.read()[:400]}")
        return False
    except Exception as e:
        print(f"  FAIL {name}: {e}")
        return False

    for cand in data.get("candidates", []):
        for part in cand.get("content", {}).get("parts", []):
            inline = part.get("inlineData") or part.get("inline_data")
            if inline:
                dest.write_bytes(base64.b64decode(inline["data"]))
                print(f"  ok   {name}  ({dest.stat().st_size // 1024} KB)")
                return True
    print(f"  FAIL {name}: no image in response {json.dumps(data)[:300]}")
    return False


if __name__ == "__main__":
    specs = json.load(open(sys.argv[2]))
    ok = 0
    for s in specs:
        print(f"[{s['name']}]")
        if generate(s["name"], s["prompt"], s.get("aspect", "16:9"), s.get("size", "2K")):
            ok += 1
    print(f"\n{ok}/{len(specs)} generated")
