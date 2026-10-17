"""Generate the story's original sounds: mono PCM, synthesized here, no
recordings. One-shot effects (bells, gates, fire, thunder, a vampire's
shriek...), seamless loops for each place (rain, clockwork, running water,
dawn birds, the dungeon) and a short piece of music for the credits.

    python3 tool/audio/generate_story.py
"""
from pathlib import Path
import wave

import numpy as np

OUT = Path(__file__).resolve().parents[2] / 'assets/audio'
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050
rng = np.random.default_rng(1715)


def t_of(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def noise(seconds):
    return rng.uniform(-1, 1, int(seconds * RATE))


def lowpass(x, cutoff):
    """One-pole low-pass; cutoff may be a number or an array (a sweep)."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = np.exp(-2 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = a[i] * acc + (1 - a[i]) * x[i]
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, low, high):
    return lowpass(highpass(x, low), high)


def decay(t, rate):
    return np.exp(-rate * t)


def partials(t, freqs, decays, amps):
    out = np.zeros_like(t)
    for f, d, a in zip(freqs, decays, amps):
        out += a * np.sin(2 * np.pi * f * t) * np.exp(-d * t)
    return out


def echo(x, delay, feedback, mix, repeats=6):
    out = x.copy()
    d = int(delay * RATE)
    g = 1.0
    for k in range(1, repeats + 1):
        g *= feedback
        if d * k >= len(x):
            break
        out[d * k:] += x[:len(x) - d * k] * g * mix
    return out


def write(name, x, peak=0.8, fade=0.008, loop=False):
    x = np.asarray(x, dtype=float)
    if loop:
        # A seamless loop: the last second laid over the first.
        n = int(min(1.0, len(x) / 4) * RATE)
        ramp = np.linspace(0, 1, n)
        head = x[:n] * ramp + x[-n:] * (1 - ramp)
        x = np.concatenate([head, x[n:-n]])
    else:
        n = max(1, int(fade * RATE))
        x[:n] *= np.linspace(0, 1, n)
        x[-n:] *= np.linspace(1, 0, n)
    m = np.max(np.abs(x)) or 1
    pcm = (x / m * peak * 32760).astype('<i2')
    with wave.open(str(OUT / f'{name}.wav'), 'wb') as f:
        f.setparams((1, 2, RATE, len(pcm), 'NONE', 'not compressed'))
        f.writeframes(pcm.tobytes())
    print(f'  {name:10s} {len(pcm) / RATE:5.2f} s')


# --- One-shot effects ------------------------------------------------------

def tick():
    t = t_of(0.09)
    click = bandpass(noise(0.09), 1800, 5200) * decay(t, 90)
    body = np.sin(2 * np.pi * 1250 * t) * decay(t, 70) * 0.5
    return click + body


def gear():
    t = t_of(0.8)
    thud = np.sin(2 * np.pi * (70 - 20 * t) * t) * decay(t, 9)
    ring = partials(t, [182, 413, 871, 1290], [6, 9, 13, 18], [0.35, 0.28, 0.2, 0.12])
    grind = bandpass(noise(0.8), 300, 1600) * decay(t, 6) * 0.35
    return thud + ring + grind


def hammer():
    t = t_of(0.75)
    swoosh = bandpass(noise(0.75), 200, 900) * np.exp(-((t - 0.18) / 0.09) ** 2) * 0.7
    hit = np.where(t > 0.24, np.sin(2 * np.pi * 52 * (t - 0.24)) * decay(np.maximum(t - 0.24, 0), 10), 0)
    clank = np.where(t > 0.24, partials(np.maximum(t - 0.24, 0), [240, 610, 1020], [12, 16, 22], [0.4, 0.3, 0.2]), 0)
    return swoosh + hit + clank


def bell():
    t = t_of(5.0)
    f0 = 196.0
    ratios = [0.5, 1.0, 1.183, 1.506, 2.0, 2.514, 2.662, 3.011, 4.166]
    decays = [0.35, 0.55, 0.8, 0.9, 1.1, 1.5, 1.7, 2.1, 3.0]
    amps = [0.55, 0.9, 0.5, 0.45, 0.4, 0.25, 0.2, 0.15, 0.08]
    strike = bandpass(noise(5.0), 800, 3000) * decay(t, 40) * 0.3
    return partials(t, [f0 * r for r in ratios], decays, amps) + strike


def gate():
    t = t_of(1.5)
    thud = np.sin(2 * np.pi * (48 - 12 * t) * t) * decay(t, 6) * 1.2
    clang = partials(t, [297, 718, 1123, 1680], [4, 6, 9, 12], [0.45, 0.35, 0.25, 0.15])
    rattle = bandpass(noise(1.5), 900, 4000) * decay(t, 5) * 0.25 * (1 + np.sin(2 * np.pi * 23 * t)) / 2
    return thud + clang + rattle


def chain():
    t = t_of(0.8)
    out = np.zeros_like(t)
    for start in np.sort(rng.uniform(0, 0.6, 9)):
        s = np.maximum(t - start, 0)
        f = rng.uniform(1800, 3600)
        out += np.where(t > start, np.sin(2 * np.pi * f * s) * decay(s, 45), 0) * rng.uniform(0.4, 1)
    return out + bandpass(noise(0.8), 2000, 6000) * 0.08 * np.sin(np.pi * t / 0.8)


def wood():
    t = t_of(0.7)
    crack = highpass(noise(0.7), 1500) * decay(t, 35) * 1.2
    splinter = bandpass(noise(0.7), 600, 2500) * decay(t, 9) * 0.35
    body = np.sin(2 * np.pi * (140 - 60 * t) * t) * decay(t, 8) * 0.6
    return crack + splinter + body


def fire():
    t = t_of(1.4)
    sweep = 300 + 2800 * np.minimum(t / 0.5, 1)
    whoosh = lowpass(noise(1.4), sweep) * np.sin(np.pi * np.minimum(t / 1.4, 1)) * 1.4
    return whoosh + crackles(1.4, 18) * 0.5


def crackles(seconds, count):
    t = t_of(seconds)
    out = np.zeros_like(t)
    for start in rng.uniform(0, seconds - 0.05, count):
        s = np.maximum(t - start, 0)
        out += np.where(t > start, rng.uniform(-1, 1, len(t)) * decay(s, 300), 0) * rng.uniform(0.3, 1)
    return out


def burn():
    t = t_of(2.4)
    hiss = highpass(noise(2.4), 2500) * (0.6 * decay(t, 0.9)) * 0.6
    roar = lowpass(noise(2.4), 500) * decay(t, 1.2) * 0.8
    return hiss + roar + crackles(2.4, 30) * 0.7


def shriek():
    t = t_of(1.4)
    f = 980 - 380 * t / 1.4 + 18 * np.sin(2 * np.pi * 9 * t)
    phase = 2 * np.pi * np.cumsum(f) / RATE
    tone = (np.sin(phase) + 0.5 * np.sin(2 * phase + 0.4) + 0.3 * np.sin(3.02 * phase)) / 1.8
    rasp = bandpass(noise(1.4), 1200, 4500) * 0.45
    env = np.minimum(t / 0.06, 1) * decay(t, 1.6)
    return (tone + rasp) * env


def thunder():
    t = t_of(4.5)
    crack = highpass(noise(4.5), 1200) * decay(t, 18) * 0.8
    rumble = lowpass(noise(4.5), 120 + 80 * decay(t, 1)) * 6
    swell = np.minimum(t / 0.3, 1) * decay(t, 0.7) * (1 + 0.5 * np.sin(2 * np.pi * 1.7 * t))
    return crack + rumble * swell


def splash():
    t = t_of(1.0)
    body = lowpass(noise(1.0), 2400 * decay(t, 2.5) + 300) * decay(t, 3.2) * 1.6
    drops = crackles(1.0, 12) * 0.25
    return body + drops


def rumble():
    t = t_of(1.6)
    roll = lowpass(noise(1.6), 160) * 5 * np.sin(np.pi * t / 1.6)
    out = roll
    for start in rng.uniform(0, 1.3, 7):
        s = np.maximum(t - start, 0)
        out += np.where(t > start, np.sin(2 * np.pi * rng.uniform(55, 95) * s) * decay(s, 14), 0) * 0.6
    return out


def heartbeat():
    t = t_of(1.1)
    out = np.zeros_like(t)
    for start, amp in [(0.05, 1.0), (0.30, 0.7)]:
        s = np.maximum(t - start, 0)
        out += np.where(t > start, np.sin(2 * np.pi * (58 - 18 * s) * s) * decay(s, 11) * amp, 0)
    return out


def creak():
    t = t_of(1.1)
    f = 170 + 50 * np.sin(2 * np.pi * 1.3 * t) + 20 * rng.standard_normal(len(t)).cumsum() / 400
    phase = 2 * np.pi * np.cumsum(f) / RATE
    saw = 2 * ((phase / (2 * np.pi)) % 1) - 1
    grain = (np.sin(2 * np.pi * 38 * t) > 0.6).astype(float)
    tone = bandpass(saw * (0.4 + 0.6 * grain), 300, 2500)
    return tone * np.sin(np.pi * t / 1.1)


# --- Loops for each place -------------------------------------------------

def rain():
    secs = 12
    t = t_of(secs)
    hiss = bandpass(noise(secs), 900, 7000) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.11 * t))
    patter = crackles(secs, 260) * 0.35
    low = lowpass(noise(secs), 250) * 2.5
    return hiss + patter + low


def clockwork():
    secs = 8.0
    t = t_of(secs)
    out = np.zeros_like(t)
    for k in range(16):
        start = k * 0.5
        s = np.maximum(t - start, 0)
        f = 1350 if k % 2 == 0 else 980
        click = np.sin(2 * np.pi * f * s) * decay(s, 80)
        out += np.where(t > start, click, 0) * (0.9 if k % 2 == 0 else 0.7)
    hum = (np.sin(2 * np.pi * 55 * t) * 0.08 + lowpass(noise(secs), 200) * 0.6)
    return out + hum


def river():
    secs = 10
    t = t_of(secs)
    flow = bandpass(noise(secs), 250, 2200) * (0.75 + 0.25 * np.sin(2 * np.pi * 0.23 * t))
    gurgle = np.zeros_like(t)
    for start in rng.uniform(0, secs - 0.3, 40):
        s = np.maximum(t - start, 0)
        f = rng.uniform(300, 700)
        gurgle += np.where((t > start) & (s < 0.25), np.sin(2 * np.pi * (f + 900 * s) * s) * decay(s, 18), 0)
    return flow + gurgle * 0.25


def birds():
    secs = 14
    t = t_of(secs)
    air = lowpass(noise(secs), 400) * 0.8
    out = air
    for start in np.sort(rng.uniform(0, secs - 0.6, 26)):
        s = np.maximum(t - start, 0)
        notes = int(rng.integers(2, 5))
        base = rng.uniform(2400, 4200)
        for n in range(notes):
            ns = np.maximum(s - n * 0.11, 0)
            f = base * (1 + 0.25 * np.sin(2 * np.pi * 14 * ns)) + 600 * ns
            chirp = np.sin(2 * np.pi * np.cumsum(f) / RATE)
            win = np.where((s > n * 0.11) & (ns < 0.08), np.sin(np.pi * np.minimum(ns / 0.08, 1)), 0)
            out += chirp * win * rng.uniform(0.12, 0.3)
    return out


def dungeon():
    secs = 12
    t = t_of(secs)
    drone = (np.sin(2 * np.pi * 41 * t) * 0.3 + np.sin(2 * np.pi * 61.7 * t) * 0.15) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.08 * t))
    air = lowpass(noise(secs), 300) * 1.2
    drips = np.zeros_like(t)
    for start in rng.uniform(0, secs - 0.4, 9):
        s = np.maximum(t - start, 0)
        f = rng.uniform(900, 1700)
        drips += np.where(t > start, np.sin(2 * np.pi * (f + 400 * s) * s) * decay(s, 25), 0)
    return drone + air + echo(drips, 0.21, 0.5, 0.6) * 0.35


# --- Music for the credits ------------------------------------------------

def ending():
    """A slow, quiet piece: a soft organ pad under a music-box tune, in A
    minor, ending on the major chord."""
    beat = 0.75
    chords = [
        ([57, 60, 64], 4), ([53, 57, 60], 4), ([48, 52, 55], 4), ([55, 59, 62], 4),
        ([57, 60, 64], 4), ([53, 57, 60], 4), ([52, 55, 59], 4), ([57, 61, 64], 6),
    ]
    tune = [76, 74, 72, 71, 72, 74, 72, 69, 72, 71, 69, 67, 69, 72, 71, 69,
            76, 74, 72, 71, 72, 69, 67, 64, 67, 69, 71, 72, 71, 69, 68, 69]
    total = sum(b for _, b in chords) * beat + 3
    t = t_of(total)
    out = np.zeros_like(t)

    def hz(m):
        return 440 * 2 ** ((m - 69) / 12)

    at = 0.0
    for notes, beats in chords:
        dur = beats * beat
        mask = (t >= at) & (t < at + dur + 1.2)
        s = t[mask] - at
        env = np.minimum(s / 0.6, 1) * np.where(s > dur, decay(s - dur, 3), 1)
        pad = sum(np.sin(2 * np.pi * hz(n - 12) * s) + 0.35 * np.sin(2 * np.pi * hz(n) * s) for n in notes)
        out[mask] += pad * env * 0.16
        at += dur
    for i, m in enumerate(tune):
        start = i * beat
        mask = (t >= start) & (t < start + 2.5)
        s = t[mask] - start
        f = hz(m)
        box = (np.sin(2 * np.pi * f * s) + 0.3 * np.sin(2 * np.pi * 2 * f * s) + 0.12 * np.sin(2 * np.pi * 3.97 * f * s)) * decay(s, 2.6)
        out[mask] += box * 0.22
    return echo(out, 0.33, 0.45, 0.5)


EFFECTS = {
    'tick': tick, 'gear': gear, 'hammer': hammer, 'bell': bell, 'gate': gate,
    'chain': chain, 'wood': wood, 'fire': fire, 'burn': burn, 'shriek': shriek,
    'thunder': thunder, 'splash': splash, 'rumble': rumble,
    'heartbeat': heartbeat, 'creak': creak,
}
LOOPS = {
    'rain': rain, 'clockwork': clockwork, 'river': river, 'birds': birds,
    'dungeon': dungeon,
}

if __name__ == '__main__':
    for name, make in EFFECTS.items():
        write(name, make())
    for name, make in LOOPS.items():
        write(name, make(), peak=0.6, loop=True)
    write('ending', ending(), peak=0.7, fade=1.5)
