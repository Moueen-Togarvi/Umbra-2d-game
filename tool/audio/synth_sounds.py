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


SYNTH = {
    # name: (takes, loudness dB RMS, maker)
    'checkpoint': (2, -31, checkpoint),
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
