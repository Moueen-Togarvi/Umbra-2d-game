#!/usr/bin/env python3
"""Play the start of the level in real Chrome, record it, and measure FPS.

The in-app browser pane and headless Chromium barely run the frame loop, so
this drives a headed Chrome through Playwright on a release web build:

    flutter build web --release
    python3 tools/playtest.py build/limbo-preview/browser

It serves build/web, holds and taps keys on a fixed script (run, push the
crate, jump the logs and the first pit), saves a screenshot each second and
a .webm video of the whole run, and reports the measured frame rate and any
console errors.
"""
import json
import pathlib
import subprocess
import sys
import time

from playwright.sync_api import sync_playwright

OUT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/limbo-preview/browser")
OUT.mkdir(parents=True, exist_ok=True)
W, H = 1280, 576
PORT = 8765

# (seconds from start, action, key). "down"/"up" hold and release; "tap" is
# a short press. The boy always runs, so the script only steers and jumps.
SCRIPT = [
    (0.0, "down", "d"),
    (1.15, "tap", "w"),  # over the light crate
    (2.45, "tap", "w"),  # onto the heavy crate
    (3.25, "tap", "w"),  # down the far side and on
    (4.05, "tap", "w"),  # the first pit
    (5.45, "tap", "w"),  # the log
    (8.0, "up", "d"),
    (9.5, "down", "a"),
    (10.4, "up", "a"),
    (11.0, "tap", "w"),
    (12.5, None, None),
]

FPS_JS = """() => new Promise(r => { let n = 0; const t0 = performance.now();
  const f = () => { n++; if (performance.now() - t0 < 2000) requestAnimationFrame(f);
  else r(n / ((performance.now() - t0) / 1000)); }; requestAnimationFrame(f); })"""


def main():
    server = subprocess.Popen(
        ["python3", "-m", "http.server", str(PORT), "--bind", "127.0.0.1"],
        cwd="build/web",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    report = {"console_errors": []}
    try:
        time.sleep(1)
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=False, channel="chrome")
            context = browser.new_context(
                viewport={"width": W, "height": H},
                record_video_dir=str(OUT),
                record_video_size={"width": W, "height": H},
            )
            page = context.new_page()
            page.on(
                "console",
                lambda m: report["console_errors"].append(m.text)
                if m.type == "error"
                else None,
            )
            page.goto(f"http://127.0.0.1:{PORT}/")
            page.wait_for_selector("flt-glass-pane, flutter-view", timeout=60000)
            time.sleep(4)  # engine start, Box2D WASM, fog layers baking
            page.mouse.click(W // 2, H // 3)
            report["fps_idle"] = page.evaluate(FPS_JS)

            start = time.time()
            shot = 0
            for at, action, key in SCRIPT:
                while time.time() - start < at:
                    if time.time() - start >= shot:
                        page.screenshot(path=str(OUT / f"t{shot:02d}.png"))
                        shot += 1
                    time.sleep(0.01)
                if action == "down":
                    page.keyboard.down(key)
                elif action == "up":
                    page.keyboard.up(key)
                elif action == "tap":
                    page.keyboard.press(key)
            page.keyboard.down("d")
            report["fps_running"] = page.evaluate(FPS_JS)
            page.keyboard.up("d")
            video = page.video.path() if page.video else None
            context.close()
            browser.close()
            if video:
                target = OUT / "gameplay.webm"
                pathlib.Path(video).replace(target)
                report["video"] = str(target)
    finally:
        server.terminate()
    (OUT / "report.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
