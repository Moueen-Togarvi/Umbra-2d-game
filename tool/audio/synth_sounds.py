#!/usr/bin/env python3
"""Effects made from nothing (no recordings): tones and shaped noise.

    python3 tool/audio/synth_sounds.py

Writes assets/audio/sfx/NAME_N.wav for every effect in SYNTH, then
lib/audio/sound_bank.dart again (through build_sounds.write_bank, which
lists these too). Needs ffmpeg and numpy.
"""
import numpy as np

import build_sounds as b

SR = b.SR


def seconds(n):
    return np.arange(int(n * SR)) / SR


def swell(t, rise, fall):
    """Up over [rise] seconds, then down to nothing by the end."""
    n = t.size
    up = np.clip(t / rise, 0, 1)
    down = np.clip((t[-1] - t) / fall, 0, 1)
    return np.sin(up * np.pi / 2) ** 2 * down ** 2 if n else t


def checkpoint(take):
    """A held breath let out: a low, soft swell of air with two quiet
    tones under it, as if the place had noticed him. Never a chime."""
    rng = np.random.default_rng(100 + take)
    t = seconds(1.5)
    st = (0, -2)[take - 1]
    k = 2 ** (st / 12)
    air = b.filtered(rng.standard_normal(t.size), low=900 * k, high=220 * k)
    tone = (np.sin(2 * np.pi * 110 * k * t) * 0.6 +
            np.sin(2 * np.pi * 164.8 * k * t + 0.4) * 0.35 +
            np.sin(2 * np.pi * 220 * k * t + 1.1) * 0.12)
    # The tones breathe a little, not a steady hum.
    tone *= 1 + 0.15 * np.sin(2 * np.pi * 3.1 * t)
    x = (air * 0.55 + tone * 0.45) * swell(t, 0.45, 1.0)
    return b.reverb(x, 'cave', 0.35)


def _env(t, attack, decay):
    """A fast rise over [attack] seconds, then an exponential fall."""
    return np.clip(t / attack, 0, 1) * np.exp(-np.maximum(t - attack, 0) / decay)


def _sweep(rng, t, f0, f1, width=0.5):
    """Noise through a band that slides from f0 to f1 Hz: air being cut."""
    noise = rng.standard_normal(t.size)
    out = np.zeros_like(noise)
    # Short overlapping blocks, each filtered to its own band.
    block = 1024
    for start in range(0, t.size, block // 2):
        seg = noise[start:start + block]
        if seg.size < 32:
            break
        f = f0 + (f1 - f0) * (start / t.size)
        win = np.hanning(seg.size)
        out[start:start + seg.size] += b.filtered(seg, low=f * (1 + width), high=f * (1 - width / 2)) * win
    return out


def slash(take):
    """A short blade through the air: a rising-then-falling hiss with a thin
    ring of steel under it."""
    rng = np.random.default_rng(300 + take)
    t = seconds(0.32)
    k = (1.0, 1.12, 0.9)[take - 1]
    air = _sweep(rng, t, 900 * k, 4200 * k) * swell(t, 0.07, 0.22)
    ring = np.sin(2 * np.pi * 2350 * k * t) * _env(t, 0.004, 0.05) * 0.18
    return air + ring


def throw(take):
    """A star leaving the hand: a quick whip of air that flutters as it
    spins away."""
    rng = np.random.default_rng(400 + take)
    t = seconds(0.3)
    k = (1.0, 1.15)[take - 1]
    air = _sweep(rng, t, 2600 * k, 1500 * k, 0.4) * swell(t, 0.03, 0.25)
    flutter = 0.6 + 0.4 * np.sin(2 * np.pi * 38 * t) ** 2
    return air * flutter


def hit(take):
    """A blow landing: a dull thud and a short crack on top."""
    rng = np.random.default_rng(500 + take)
    t = seconds(0.35)
    k = (1.0, 0.85)[take - 1]
    thud = np.sin(2 * np.pi * (85 * k) * t * (1 - 0.4 * t)) * _env(t, 0.003, 0.08)
    crack = b.filtered(rng.standard_normal(t.size), low=3500, high=600) * _env(t, 0.001, 0.02)
    return thud * 0.8 + crack * 0.6


def kill(take):
    """A vampire cut down: the blow, a low drop, and a long dry hiss as he
    crumbles to ash."""
    rng = np.random.default_rng(600 + take)
    t = seconds(1.2)
    k = (1.0, 0.9)[take - 1]
    blow = hit(take)
    boom = np.sin(2 * np.pi * 55 * k * t * (1 - 0.25 * t)) * _env(t, 0.006, 0.25)
    ash = b.filtered(rng.standard_normal(t.size), low=7000, high=1800)
    ash *= swell(t, 0.25, 0.8) * (0.7 + 0.3 * rng.random(t.size))
    x = boom * 0.7 + ash * 0.35
    x[:blow.size] += blow
    return b.reverb(x, 'hall', 0.25)


def dash(take):
    """A burst of speed: a low gust that rushes past."""
    rng = np.random.default_rng(700 + take)
    t = seconds(0.32)
    k = (1.0, 1.1)[take - 1]
    gust = _sweep(rng, t, 500 * k, 1400 * k, 0.7) * swell(t, 0.05, 0.24)
    return gust


SYNTH = {
    # name: (takes, loudness dB RMS, maker)
    'checkpoint': (2, -31, checkpoint),
    'slash': (3, -24, slash),
    'throw': (2, -27, throw),
    'hit': (2, -22, hit),
    'kill': (2, -21, kill),
    'dash': (2, -27, dash),
}


def counts():
    return {name: takes for name, (takes, _, _) in SYNTH.items()}


def main():
    out = b.ROOT / 'assets/audio/sfx'
    for name, (takes, target, make) in SYNTH.items():
        for i in range(1, takes + 1):
            # Short enough for Android's low-latency pool.
            x = b.level(b.fade(b.cut(make(i), 0, 2.2), 0.01, 0.6), target)
            b.save(x, out / f'{name}_{i}.wav', 'wav')
        print(f'{name}: {takes} takes')
    b.write_bank({name: len(spec[0]) for name, spec in b.EFFECTS.items()})


if __name__ == '__main__':
    main()
