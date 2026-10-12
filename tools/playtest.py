#!/usr/bin/env python3
"""Play the level start to finish in a real browser and report what happened.

The native test runner cannot build forge2d on this machine, so the game is
verified on a web build in headed Chrome (headless renders at ~1 FPS, which
breaks jumps). Build with the debug readout first:

    flutter build web --release --dart-define=UMBRA_DEBUG=true
    python3 tools/playtest.py out_dir            # full autopilot run
    python3 tools/playtest.py out_dir --tour     # just a few stills

The debug HUD paints the player's x, y and grounded state as bars in the
top-left corner of the frame; this reads them back out of screenshots.
"""
import io, pathlib, subprocess, sys, time
from PIL import Image
from playwright.sync_api import sync_playwright

OUT = pathlib.Path(sys.argv[1]); OUT.mkdir(parents=True, exist_ok=True)
TOUR = "--tour" in sys.argv
W, H = 1600, 720
LEVEL_W, LEVEL_H = 64.0, 12.0

# World x at which to press jump for each pit and log, left to right.
JUMP_AT = [13.5, 18.1, 29.6, 35.2, 44.6, 49.6]
SHOTS_AT = [8, 17, 28, 34, 44, 56]


def read_state(pg):
    im = Image.open(io.BytesIO(pg.screenshot(clip={"x": 0, "y": 0, "width": W, "height": 12}))).convert("L")
    def bar(row):
        n = 0
        for x in range(W):
            if im.getpixel((x, row)) > 128: n = x + 1
            else: break
        return n
    x = bar(1) / W * LEVEL_W
    y = bar(5) / W * LEVEL_H
    g = im.getpixel((3, 9)) > 128
    return x, y, g


def wait_for_game(pg):
    for _ in range(60):
        time.sleep(1)
        px = Image.open(io.BytesIO(pg.screenshot())).convert("L").getpixel((60, H - 20))
        if px < 40: return
    raise SystemExit("game never showed the ground")


srv = subprocess.Popen(["python3", "-m", "http.server", "8765", "--bind", "127.0.0.1"], cwd="build/web",
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(1)
log = []
try:
    with sync_playwright() as p:
        b = p.chromium.launch(headless=False, channel="chrome")
        pg = b.new_page(viewport={"width": W, "height": H})
        pg.goto("http://127.0.0.1:8765/")
        wait_for_game(pg)
        time.sleep(1.5); pg.mouse.click(W // 2, H // 2); time.sleep(0.5)

        if TOUR:
            pg.screenshot(path=str(OUT / "s0.png"))
            pg.keyboard.down("d"); time.sleep(3.2); pg.keyboard.up("d"); time.sleep(1.2)
            pg.screenshot(path=str(OUT / "s1.png"))
            b.close(); raise SystemExit

        x, y, g = read_state(pg); log.append(f"spawn x={x:.2f} y={y:.2f} grounded={g}")
        fps = pg.evaluate("() => new Promise(r => { let n = 0; const t0 = performance.now(); const f = () => { n++; if (performance.now() - t0 < 2000) requestAnimationFrame(f); else r(n / 2); }; requestAnimationFrame(f); })")
        log.append(f"browser fps ~{fps:.0f}")

        # Standing jump: apex and airtime.
        pg.keyboard.press("w"); top = y; t0 = time.time(); air = 0
        while time.time() - t0 < 1.5:
            _, yy, gg = read_state(pg); top = min(top, yy)
            if not gg: air = time.time() - t0
        log.append(f"standing jump: apex {y - top:.2f} m, airtime {air:.2f} s")

        # Poll latency, to lead the jump presses.
        t0 = time.time(); read_state(pg); lat = time.time() - t0
        lead = lat * 3.2
        log.append(f"poll latency {lat*1000:.0f} ms -> jump lead {lead:.2f} m")

        pending = [j - lead for j in JUMP_AT]; shots = list(SHOTS_AT)
        deaths = 0; last_x = x; t0 = time.time(); trace = []
        pg.keyboard.down("d")
        while time.time() - t0 < 60:
            x, y, g = read_state(pg); t = time.time() - t0
            trace.append(f"{t:5.2f} x={x:6.2f} y={y:5.2f} g={int(g)}")
            if x < last_x - 5:
                deaths += 1; log.append(f"  respawned near x={x:.1f} (was {last_x:.1f}) at t={t:.1f}")
                pending = [j - lead for j in JUMP_AT if j - lead > x]
            last_x = x
            if pending and x >= pending[0]:
                pg.keyboard.press("w"); log.append(f"  jump at x={x:.2f} t={t:.1f} grounded={g}"); pending.pop(0)
            safe = (not pending) or (pending[0] - x > 6.0)
            if shots and x >= shots[0] and safe:
                pg.screenshot(path=str(OUT / f"x{shots[0]:02d}.png")); shots.pop(0)
            if x > 63: break
        pg.keyboard.up("d")
        pg.screenshot(path=str(OUT / "final.png"))
        log.append(f"final x={x:.2f} y={y:.2f} grounded={g} deaths={deaths} time={time.time()-t0:.1f}s")
        (OUT / "trace.txt").write_text("\n".join(trace))
        b.close()
finally:
    srv.terminate()
print("\n".join(log))
