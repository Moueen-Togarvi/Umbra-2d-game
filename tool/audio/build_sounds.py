#!/usr/bin/env python3
"""Build the game's sound from CC0 recordings and the approved AI running take.

The sources are free (CC0) packs from kenney.nl and opengameart.org; see
assets/audio/CREDITS.md for each one. Unpack them into one folder and run:

    python3 tool/audio/build_sounds.py <sources>

Rebuild only the approved running footfalls (no external packs required):

    python3 tool/audio/build_sounds.py --running-only
    python3 tool/audio/build_sounds.py --locomotion-and-score

Every effect gets several takes (different recordings, or the same one
pitched a little apart), trimmed, levelled to a loudness, and given the
echo of the place it belongs to (a stone hall, a cave). Loops are cut to a
length and crossfaded end into start so they never click. It writes:

    assets/audio/sfx/NAME_N.wav     one-shot effects, mono 32 kHz
    assets/audio/loops/NAME.ogg     the beds under the wind
    assets/audio/music/NAME.ogg     drones and pieces
    lib/audio/sound_bank.dart       the list the game loads

Needs ffmpeg and numpy.
"""
import pathlib
import subprocess
import sys

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
SR = 44100
RNG = np.random.default_rng(7)


# --- Reading and writing ------------------------------------------------------

def find(src, name):
    bundled = pathlib.Path(name)
    if bundled.is_absolute():
        if not bundled.is_file():
            sys.exit(f'missing source: {name}')
        return bundled
    hits = sorted(p for p in src.rglob(name) if '__MACOSX' not in p.parts)
    if not hits:
        sys.exit(f'missing source: {name}')
    return hits[0]


def load(path, channels=1):
    raw = subprocess.run(
        ['ffmpeg', '-v', 'quiet', '-i', str(path), '-ac', str(channels),
         '-ar', str(SR), '-f', 'f32le', '-'],
        capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    return x.reshape(-1, channels).T if channels > 1 else x


def save(x, path, kind):
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.clip(x, -1, 1).astype(np.float32)
    channels = 1 if data.ndim == 1 else data.shape[0]
    raw = data.T.tobytes() if channels > 1 else data.tobytes()
    codec = (['-ar', '32000', '-c:a', 'pcm_s16le'] if kind == 'wav'
             else ['-c:a', 'libvorbis', '-b:a',
                   '64000' if kind == 'loop' else '80000'])
    subprocess.run(
        ['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR),
         '-ac', str(channels), '-i', '-', *codec, str(path)],
        input=raw, check=True)


# --- Shaping -------------------------------------------------------------------

def mono(x):
    return x.mean(axis=0) if x.ndim > 1 else x


def cut(x, start=None, end=None):
    a = int((start or 0) * SR)
    b = int(end * SR) if end is not None else x.shape[-1]
    return x[..., a:b]


def trim_silence(x, floor=-45):
    """Drops the quiet before the sound starts and after it has died."""
    env = np.abs(mono(x))
    loud = np.nonzero(env > np.max(env) * 10 ** (floor / 20))[0]
    if len(loud) == 0:
        return x
    a = max(0, loud[0] - int(0.004 * SR))
    b = min(env.size, loud[-1] + int(0.05 * SR))
    return x[..., a:b]


def pitch(x, semitones):
    """Resampled: higher is shorter, as a smaller thing would sound."""
    if not semitones:
        return x
    k = 2 ** (semitones / 12)
    n = x.shape[-1]
    t = np.arange(0, n - 1, k)
    if x.ndim == 1:
        return np.interp(t, np.arange(n), x)
    return np.stack([np.interp(t, np.arange(n), c) for c in x])


def filtered(x, low=None, high=None):
    """A gentle low-pass at [low] Hz and high-pass at [high] Hz."""
    if not low and not high:
        return x
    n = x.shape[-1]
    f = np.fft.rfftfreq(n, 1 / SR)
    h = np.ones_like(f)
    if low:
        h /= np.sqrt(1 + (f / low) ** 4)
    if high:
        h *= 1 / np.sqrt(1 + (high / np.maximum(f, 1)) ** 4)
    return np.fft.irfft(np.fft.rfft(x, axis=-1) * h, n, axis=-1)


ROOMS = {
    # name: (seconds to die away, darkness Hz, first reflections s)
    'room': (0.5, 6000, [0.011, 0.019, 0.027]),
    'hall': (1.9, 4200, [0.023, 0.037, 0.051, 0.068]),
    'cave': (2.8, 2600, [0.031, 0.047, 0.083, 0.11]),
    'far': (4.5, 1400, [0.06, 0.13]),
}


def impulse(room):
    rt, dark, taps = ROOMS[room]
    n = int(rt * 1.2 * SR)
    t = np.arange(n) / SR
    tail = RNG.standard_normal(n) * np.exp(-6.91 * t / rt)
    tail[: int(0.012 * SR)] = 0
    tail = filtered(tail, low=dark)
    for i, d in enumerate(taps):
        tail[int(d * SR)] += 0.5 * (0.8 ** i) * (1 if i % 2 else -1)
    return tail / np.sqrt(np.sum(tail ** 2))


def reverb(x, room, wet):
    if not room or not wet:
        return x
    ir = impulse(room)
    n = x.shape[-1] + ir.size
    m = 1 << (n - 1).bit_length()
    w = np.fft.irfft(np.fft.rfft(x, m, axis=-1) * np.fft.rfft(ir, m), m, axis=-1)[..., :n]
    dry = np.zeros_like(w)
    dry[..., : x.shape[-1]] = x
    out = dry + wet * w
    return trim_silence(out, floor=-60)


def fade(x, start=0.003, end=0.03):
    n = x.shape[-1]
    a, b = min(int(start * SR), n // 2), min(int(end * SR), n // 2)
    env = np.ones(n)
    if a:
        env[:a] = np.linspace(0, 1, a)
    if b:
        env[n - b:] = np.linspace(1, 0, b) ** 2
    return x * env


def level(x, target):
    """Brings the loud part of [x] to [target] dB RMS, peaks under −1 dB."""
    m = mono(x)
    hop = int(0.02 * SR)
    frames = np.array([np.sqrt(np.mean(m[i:i + hop] ** 2))
                       for i in range(0, max(1, m.size - hop), hop)])
    loud = frames[frames > frames.max() * 0.25] if frames.size else frames
    rms = np.sqrt(np.mean(loud ** 2)) if loud.size else 1e-9
    x = x * (10 ** (target / 20) / max(rms, 1e-9))
    peak = np.max(np.abs(x))
    return x * min(1, 10 ** (-1 / 20) / peak)


def seamless(x, length, cross=1.5):
    """[length] seconds that loop without a seam: the bit after the end is
    faded into the start."""
    n, c = int(length * SR), int(cross * SR)
    x = x[..., : n + c]
    if x.shape[-1] < n + c:
        sys.exit('loop source too short')
    t = np.linspace(0, np.pi / 2, c)
    out = x[..., :n].copy()
    out[..., :c] = x[..., :c] * np.sin(t) + x[..., n:n + c] * np.cos(t)
    return out


# --- What is made from what -----------------------------------------------------

def take(file, start=None, end=None, st=0, low=None, high=None, layer=None,
         max_len=None):
    return dict(file=file, start=start, end=end, st=st, low=low, high=high,
                layer=layer or [], max_len=max_len)


def steps(sources, room=None, wet=0, low=None, under=None):
    """Six takes of a footstep: each recording, then the first ones again
    pitched a little apart, all short (a running step must not smear into
    the next), the rumble cut, and as loud as the recorded running step."""
    length = 0.35 if under else 0.45
    out = [take(f, high=80, low=low, max_len=length) for f in sources]
    pitches = (0.7, -0.7)
    for i in range(6 - len(out)):
        out.append(take(sources[i % len(sources)], st=pitches[i % 2], high=80,
                        low=low, max_len=length))
    for t in out:
        t['under'] = under
    return (out, STEP_LOUDNESS, room, wet)


# How loud every footstep is (dB RMS), the same on every surface.
STEP_LOUDNESS = -24


K = 'kenney_impact-sounds/'
EFFECTS = {
    # name: (takes, loudness dB RMS, room, wet)
    # Six distinct foot impacts from the approved ElevenLabs take #3, at
    # their own pitch; no material, cloth, voice or room layers. Out of
    # doors and in the caves.
    'step_run': ([take(str(ROOT / 'assets/design/audio/elevenlabs_running_take_3.opus'),
                       start=at - 0.05, end=at + 0.17)
                  for at in (2.930, 3.230, 3.550, 3.815, 4.150, 4.405)],
                 STEP_LOUDNESS, None, 0),
    # On stone floors, on wood and in water; elsewhere the step is
    # step_run.
    'step_stone': steps([f'footstep_concrete_00{i}.ogg' for i in range(5)],
                        'hall', 0.16, low=7000),
    'step_wood': steps([f'footstep_wood_00{i}.ogg' for i in range(5)]),
    # Wading: the slosh of a real splash, dull and short, with the step on
    # the bottom under it.
    'step_water': steps([f'splash_{i}.ogg' for i in ('04', '08', '06', '10', '02')],
                        low=4500, under='step_run'),
    'land': ([take(f'impactSoft_heavy_00{i}.ogg', low=2500) for i in range(5)],
             -19, None, 0),
    'rope': ([take('creak1.ogg', st=4), take('creak2.ogg', st=3),
              take('creak1.ogg', st=1)], -30, None, 0),
    'drag': ([take('rolling.ogg', 0, 0.55, st=-7, low=1800),
              take('rolling.ogg', 0.45, 1.0, st=-7, low=1800),
              take('rolling.ogg', 0.2, 0.75, st=-5, low=1800)], -26, None, 0),
    'tick': ([take(f'ticking clock - tick{i}.wav') for i in (1, 2, 3, 4)],
             -24, 'hall', 0.2),
    'gear': ([take('mechanical1.wav', st=-4), take('clank1.wav', st=-4),
              take('rattle1.wav', st=-3), take('mechanical2.wav', st=-5)],
             -21, 'hall', 0.3),
    'hammer': ([take(f'impactBell_heavy_00{i}.ogg', st=-3) for i in range(3)],
               -18, 'hall', 0.4),
    'bell': ([take('gong_02.ogg', st=-5), take('gong_01.ogg', st=-8),
              take('impactBell_heavy_001.ogg', st=-9)], -16, 'far', 0.5),
    'gate': ([take('metal_slam_01.ogg', st=-5,
                   layer=[('impactSoft_heavy_001.ogg', 0)]),
              take('slam_03.ogg', st=-5,
                   layer=[('impactSoft_heavy_003.ogg', 0)]),
              take('impactMetal_heavy_000.ogg', st=-4,
                   layer=[('impactSoft_heavy_000.ogg', 0)])], -14, 'hall', 0.35),
    'chain': ([take('chain_01.ogg', st=-2), take('chain_02.ogg', st=-2),
               take('chain_03.ogg', st=-2),
               take('winch - Marker #5.wav', 0, 1.2)], -23, None, 0),
    'wood': ([take('wood_breaking_01.ogg', st=-2,
                   layer=[('impactWood_heavy_000.ogg', 0)]),
              take('wood_breaking_02.ogg', st=-3,
                   layer=[('impactWood_heavy_001.ogg', 0)]),
              take('wood_falling_01.ogg', st=-2),
              take('bfh1_wood_breaking_01.ogg', st=-2)], -16, 'room', 0.25),
    'fire': ([take('spell_fire_03.ogg'), take('spell_fire_04.ogg'),
              take('fire-1.wav', 0, 1.6)], -22, None, 0),
    'burn': ([take('spell_fire_01.ogg', st=-3, layer=[('fire-1.wav', -6)]),
              take('spell_fire_02.ogg', st=-3, layer=[('fire-1.wav', -6)])],
             -20, None, 0),
    'shriek': ([take('scream_01.ogg', st=-4), take('scream_02.ogg', st=-3),
                take('monster_01.ogg', st=-3),
                take('creature_roar_03.ogg', st=-2)], -17, 'cave', 0.3),
    'thunder': ([take('rain-thunder.ogg', 20.5, 34, low=3000),
                 take('explosion.ogg', st=-11, low=900)], -14, 'far', 0.6),
    'splash': ([take(f'splash_{i}.ogg') for i in ('04', '08', '06', '10', '02')],
               -19, None, 0),
    'rumble': ([take('cave_in_-_starninjas_0.ogg', low=2500),
                take('stones_01.ogg', st=-5), take('stones_03.ogg', st=-5)],
               -16, 'cave', 0.3),
    'heartbeat': ([take('heartbeat_slow_reverb.wav', low=900),
                   take('heartbeat.mp3_.flac', 0, 1.1, low=900)], -15, None, 0),
    'creak': ([take('creak1.ogg', st=-2), take('creak2.ogg', st=-2),
               take('creak3.ogg', st=-3), take('tree_creak.flac', 0, 1.6)],
              -22, None, 0),
}

# Too long for Android's low-latency pool; played through the media player.
LONG = ['bell', 'heartbeat', 'rumble', 'thunder']

LOOPS = {
    # name: (file, start, seconds, loudness, low-pass)
    'wind': ('wind1.wav', 2, 30, -27, 5000),
    'rain': ('1.ogg', 0, 24, -24, 9000),
    'river': ('sfx100v2_loop_water_03.ogg', 0, 8, -25, 7000),
    'cave': ('atmosbasement.mp3_.flac', 0, 18, -30, None),
    'dungeon': ('dungeon_ambient_1_0.ogg', 4, 40, -28, 3000),
    'clockwork': ('sfx100v2_loop_machine_01.ogg', 0, 6, -30, 900),
    'birds': ('birds-isaiah658_0.ogg', 0, 28, -28, None),
}

# The music. The menu, the chase and the ending are fixed; the player picks
# the music under play from BACKGROUNDS. Each loop is cut from the body of
# the piece (from [start] of the way in) and crossfaded end into start.
# (id, file, title, artist, licence, start)
BACKGROUNDS = [
    ('bg_tragic', 'ambientmain_0.ogg', 'Tragic ambient main menu', 'HaelDB',
     'CC0', 0),
    ('bg_decoherence', 'sb_decoherence.mp3', 'Decoherence', 'Scott Buckley',
     'CC-BY 4.0', 0.2),
    ('bg_descent', 'descent.mp3', 'Descent', 'Scott Buckley', 'CC-BY 4.0', 0.1),
    ('bg_solitude', 'sb_insearchofsolitude.mp3', 'In Search Of Solitude',
     'Scott Buckley', 'CC-BY 4.0', 0.2),
    ('bg_distant_sun', 'sb_monomyth_1_thedistantsun.mp3', 'The Distant Sun',
     'Scott Buckley', 'CC-BY 4.0', 0.15),
    ('bg_creepy_forest', 'forest.ogg', 'Creepy Forest', 'HaelDB', 'CC0', 0.1),
    # (saved under a name without brackets, which a search would read as a pattern)
    ('bg_wastelands', 'post_apocalyptic_wastelands.ogg',
     'Post Apocalyptic Wastelands', 'Juhani Junkala', 'CC0', 0.1),
    ('bg_tomb', 'Forgoten_tombs_1.mp3', 'Forgotten tomb ambience', 'kindland',
     'CC0', 0.1),
    ('bg_overshadow', 'overshadow_0.mp3', 'Overshadow', 'cinameng', 'CC0', 0),
]
# The menu plays the first background; the chase and the ending are their own.
MENU = 'bg_tragic'
CHASE = ('chase', 'EyesInTheVoid.mp3', 0.45)
ENDING = ('ending', '155 November_snow-33_tape_leveled.mp3', 0.08, 60)
LOOP_SECONDS = 180
MUSIC_LOUDNESS = -20


# --- Building -------------------------------------------------------------------

def build_take(src, t, room, wet, target):
    x = mono(load(find(src, t['file'])))
    x = cut(x, t['start'], t['end'])
    x = trim_silence(x)
    if t.get('under'):
        # The step under it, as already built (it comes first in EFFECTS).
        under = ROOT / f"assets/audio/sfx/{t['under']}_1.wav"
        t = dict(t, layer=[*t['layer'], (str(under), -7)])
    for name, gain in t['layer']:
        y = trim_silence(mono(load(find(src, name)))) * 10 ** (gain / 20)
        y = y / max(np.max(np.abs(y)), 1e-9) * np.max(np.abs(x))
        n = max(x.size, y.size)
        x = np.pad(x, (0, n - x.size)) + np.pad(y, (0, n - y.size))
    x = pitch(x, t['st'])
    x = filtered(x, t['low'], t['high'])
    x = fade(x)
    x = reverb(x, room, wet)
    if t['max_len']:
        x = x[..., : int(t['max_len'] * SR)]
        return fade(level(x, target), 0.001, 0.12)
    return fade(level(x, target), 0.001, 0.08)


def polish_steps(out):
    """The footsteps already built, made the way [steps] makes them, for
    when the source packs are not to hand: each recorded take cut short,
    the rumble cut, levelled with the others, and pitched copies added to
    make six."""
    for name in ('step_stone', 'step_wood', 'step_water'):
        takes = EFFECTS[name][0]
        # Water is made from the splashes (built from the same recordings).
        source = 'splash' if name == 'step_water' else name
        recorded = [load(out / f'sfx/{source}_{i}.wav')
                    for i, t in enumerate(takes, 1) if t['st'] == 0]
        for i, t in enumerate(takes, 1):
            x = pitch(recorded[(i - 1) % len(recorded)], t['st'])
            x = filtered(trim_silence(x), t['low'], high=80)
            x = x[: int(t['max_len'] * SR)]
            if t['under']:
                y = trim_silence(load(out / f"sfx/{t['under']}_{(i - 1) % 6 + 1}.wav"))
                y = y / max(np.max(np.abs(y)), 1e-9) * np.max(np.abs(x)) * 0.45
                n = max(x.size, y.size)
                x = np.pad(x, (0, n - x.size)) + np.pad(y, (0, n - y.size))
            save(fade(level(x, STEP_LOUDNESS), 0.001, 0.12),
                 out / f'sfx/{name}_{i}.wav', 'wav')
        print(f'{name}: {len(takes)} takes, polished')


def music_loop(src, file, start):
    """[LOOP_SECONDS] of the piece from [start] of the way in, looping; a
    short piece whole."""
    x = load(find(src, file), channels=2)
    duration = x.shape[-1] / SR
    begin = duration * start
    seconds = min(LOOP_SECONDS, duration - begin - 3)
    if seconds < 40:
        begin, seconds = 0, duration - 3
    return level(seamless(cut(x, begin), seconds, cross=3), MUSIC_LOUDNESS)


def build_music(src, out):
    for old in (out / 'music').glob('*'):
        old.unlink()
    for name, file, _, _, _, start in BACKGROUNDS:
        save(music_loop(src, file, start), out / f'music/{name}.ogg', 'bgm')
        print(f'music {name}')
    name, file, start = CHASE
    save(music_loop(src, file, start), out / f'music/{name}.ogg', 'bgm')
    print(f'music {name}')
    name, file, start, seconds = ENDING
    x = load(find(src, file), channels=2)
    x = cut(x, x.shape[-1] / SR * start, x.shape[-1] / SR * start + seconds)
    save(level(fade(x, 1.0, 6), MUSIC_LOUDNESS), out / f'music/{name}.ogg', 'music')
    print(f'music {name}')


def main():
    out = ROOT / 'assets/audio'
    if len(sys.argv) == 3 and sys.argv[1] == '--music':
        # Only the music, from a folder of the downloaded pieces.
        build_music(pathlib.Path(sys.argv[2]), out)
        write_bank({name: len(spec[0]) for name, spec in EFFECTS.items()})
        return
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = pathlib.Path(sys.argv[1])
    if sys.argv[1] == '--polish-steps':
        polish_steps(out)
        for gone in ('step_grass', 'step_gravel'):
            for old in (out / 'sfx').glob(f'{gone}_*'):
                old.unlink()
        write_bank({name: len(spec[0]) for name, spec in EFFECTS.items()})
        return
    if sys.argv[1] == '--running-only':
        takes, target, room, wet = EFFECTS['step_run']
        for i, t in enumerate(takes, 1):
            save(build_take(ROOT, t, room, wet, target),
                 out / f'sfx/step_run_{i}.wav', 'wav')
        write_bank({name: len(spec[0]) for name, spec in EFFECTS.items()})
        print(f'step_run: {len(takes)} takes from approved take #3')
        return
    for kind in ('sfx', 'loops', 'music'):
        for old in (out / kind).glob('*'):
            old.unlink()
    counts = {}
    for name, (takes, target, room, wet) in EFFECTS.items():
        for i, t in enumerate(takes, 1):
            # The long ones compressed: they play through the media player.
            ext = 'ogg' if name in LONG else 'wav'
            save(build_take(src, t, room, wet, target),
                 out / f'sfx/{name}_{i}.{ext}', 'music' if name in LONG else 'wav')
        counts[name] = len(takes)
        print(f'{name}: {len(takes)} takes')
    for name, (file, start, seconds, target, low) in LOOPS.items():
        x = mono(load(find(src, file)))
        x = cut(x, start)
        x = filtered(x, low)
        save(level(seamless(x, seconds), target), out / f'loops/{name}.ogg', 'loop')
        print(f'loop {name}')
    build_music(src, out)
    write_bank(counts)


def build_vampire_foley():
    import subprocess
    for i in range(1, 4):
        for name, source, filters in [
            ('vampire_step', f'step_stone_{i}.wav', 'asetrate=25600,aresample=32000,lowpass=f=1700,volume=0.85'),
            ('vampire_cloth', f'drag_{i}.wav', 'highpass=f=600,lowpass=f=4500,volume=0.35,afade=t=out:st=0.25:d=0.15')]:
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i',
                str(ROOT / 'assets/audio/sfx' / source), '-af', filters,
                '-ar', '32000', '-ac', '1', '-t', '0.55',
                str(ROOT / 'assets/audio/sfx' / f'{name}_{i}.wav')], check=True)


def write_bank(counts):
    build_vampire_foley()
    counts = dict(counts, vampire_step=3, vampire_cloth=3)
    effects = '\n'.join(f"    '{k}': {v}," for k, v in counts.items())
    long = ', '.join(f"'{k}'" for k in LONG)
    loops = ', '.join(f"'{k}'" for k in LOOPS)
    backgrounds = '\n'.join(
        f"    ('{i}', '{title}', '{artist}')," for i, _, title, artist, _, _ in BACKGROUNDS)
    (ROOT / 'lib/audio/sound_bank.dart').write_text(f"""// Written by tool/audio/build_sounds.py; do not edit by hand.

/// Every sound the game has, under assets/audio/.
abstract final class SoundBank {{
  /// Each one-shot effect and how many takes it has.
  static const Map<String, int> effects = {{
{effects}
  }};

  /// Effects too long for Android's low-latency pool.
  static const Set<String> long = {{{long}}};

  /// The loops: the wind and the beds under it.
  static const List<String> loops = [{loops}];

  /// The music the player can pick to play under the game: id, title and
  /// who made it.
  static const List<(String, String, String)> backgrounds = [
{backgrounds}
  ];

  /// The fixed music: on the main menu, in a chase, under the credits.
  static const String menu = '{MENU}', chase = '{CHASE[0]}', ending = '{ENDING[0]}';

  static String effect(String name, int take) =>
      'audio/sfx/${{name}}_$take.${{long.contains(name) ? 'ogg' : 'wav'}}';
  static String loop(String name) => 'audio/loops/$name.ogg';
  static String music(String name) => 'audio/music/$name.ogg';
}}
""")


if __name__ == '__main__':
    main()
