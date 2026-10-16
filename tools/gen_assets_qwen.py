#!/usr/bin/env python3
"""Generate silhouette art with Alibaba Model Studio and save PNGs.

usage: gen_assets_qwen.py <out_dir> <specs.json> [--only name,name]

The key is read from ~/"alibaba cloud qwe 3.8.txt" (or $DASHSCOPE_API_KEY)
and is never printed. Models are tried in order (override with
$GEN_MODELS, comma separated); one that answers with a quota, billing or
permission error is dropped for the rest of the run and the next is used.
Images that already exist are skipped, so a re-run costs no quota.

Qwen-Image models answer synchronously; Wan models are asynchronous tasks
that are polled until they finish.
"""
import json, os, pathlib, re, sys, time, urllib.request, urllib.error


def load_key():
    k = os.environ.get("DASHSCOPE_API_KEY")
    if k:
        return k
    txt = open(os.path.expanduser("~/alibaba cloud qwe 3.8.txt")).read()
    return re.search(r"sk-\S+", txt).group(0)


KEY = load_key()
HOST = os.environ.get("DASHSCOPE_HOST", "dashscope-intl.aliyuncs.com")
MODELS = os.environ.get(
    "GEN_MODELS",
    "wan2.2-t2i-plus,wan2.2-t2i-flash,wanx2.1-t2i-plus,wanx2.1-t2i-turbo,qwen-image-plus,qwen-image",
).split(",")
QWEN_URL = f"https://{HOST}/api/v1/services/aigc/multimodal-generation/generation"
WAN_URL = f"https://{HOST}/api/v1/services/aigc/text2image/image-synthesis"
TASK_URL = f"https://{HOST}/api/v1/tasks/"
DEAD = set()


class ModelUnavailable(Exception):
    pass


def _call(url, body=None, extra=None):
    headers = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}
    headers.update(extra or {})
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        text = e.read()[:400].decode("utf8", "replace")
        if e.code in (400, 401, 403, 404) and re.search(
            r"quota|Quota|Arrearage|AccessDenied|not support|Unpurchased|FreeTier|InvalidApiKey|Model.*not|model_not|not exist",
            text,
        ):
            raise ModelUnavailable(f"HTTP {e.code}: {text}")
        raise RuntimeError(f"HTTP {e.code}: {text}")


def _wan_size(size):
    # Wan accepts 512–1440 px a side: scale the requested size into range.
    w, h = (int(v) for v in size.split("*"))
    scale = min(1440 / max(w, h), 1.0)
    return f"{int(w * scale) // 16 * 16}*{int(h * scale) // 16 * 16}"


def _qwen(model, prompt, negative, size):
    params = {"size": size, "n": 1, "prompt_extend": False, "watermark": False}
    if negative:
        params["negative_prompt"] = negative
    body = {
        "model": model,
        "input": {"messages": [{"role": "user", "content": [{"text": prompt}]}]},
        "parameters": params,
    }
    d = _call(QWEN_URL, body)
    return d["output"]["choices"][0]["message"]["content"][0]["image"]


def _wan(model, prompt, negative, size):
    body = {
        "model": model,
        "input": {"prompt": prompt, **({"negative_prompt": negative} if negative else {})},
        "parameters": {"size": _wan_size(size), "n": 1, "prompt_extend": False, "watermark": False},
    }
    d = _call(WAN_URL, body, {"X-DashScope-Async": "enable"})
    task = d["output"]["task_id"]
    for _ in range(120):
        time.sleep(4)
        t = _call(TASK_URL + task)
        status = t["output"]["task_status"]
        if status == "SUCCEEDED":
            return t["output"]["results"][0]["url"]
        if status in ("FAILED", "CANCELED", "UNKNOWN"):
            message = json.dumps(t["output"])[:300]
            if re.search(r"quota|Quota|Arrearage", message):
                raise ModelUnavailable(message)
            raise RuntimeError(message)
    raise RuntimeError("timed out waiting for the task")


def generate(spec, out):
    name = spec["name"]
    dest = out / f"{name}.png"
    if dest.exists():
        print(f"  skip {name}")
        return True
    for model in MODELS:
        if model in DEAD:
            continue
        for attempt in range(3):
            try:
                caller = _wan if model.startswith("wan") else _qwen
                url = caller(model, spec["prompt"], spec.get("negative", ""), spec.get("size", "1664*928"))
                with urllib.request.urlopen(url, timeout=300) as r:
                    dest.write_bytes(r.read())
                print(f"  ok   {name} via {model} ({dest.stat().st_size // 1024} KB)")
                return True
            except ModelUnavailable as e:
                print(f"  --   {model} unavailable: {str(e)[:160]}")
                DEAD.add(model)
                break
            except Exception as e:
                print(f"  ERR  {name} via {model}: {str(e)[:200]}")
                time.sleep(5 * (attempt + 1))
    print(f"  FAIL {name}")
    return False


if __name__ == "__main__":
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    specs = json.load(open(sys.argv[2]))
    if "--only" in sys.argv:
        wanted = set(sys.argv[sys.argv.index("--only") + 1].split(","))
        specs = [s for s in specs if s["name"] in wanted]
    ok = sum(generate(s, out) for s in specs)
    print(f"\n{ok}/{len(specs)} generated")
