#!/usr/bin/env python3
"""Build playable audio-direction demos without changing runtime game assets."""

from __future__ import annotations

import math
import subprocess
import wave
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build" / "audio-review"
SR = 44_100
RNG = np.random.default_rng(4107)


def decode(path: Path, duration: float | None = None) -> np.ndarray:
    command = [
        "ffmpeg", "-v", "error", "-i", str(path),
        "-f", "f32le", "-acodec", "pcm_f32le", "-ac", "2", "-ar", str(SR),
    ]
    if duration is not None:
        command[6:6] = ["-t", str(duration)]
    command.append("pipe:1")
    raw = subprocess.run(command, check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()


def fit(audio: np.ndarray, seconds: float) -> np.ndarray:
    count = int(seconds * SR)
    if len(audio) >= count:
        return audio[:count].copy()
    repeats = math.ceil(count / len(audio))
    return np.tile(audio, (repeats, 1))[:count].copy()


def rms_normalize(audio: np.ndarray, db: float = -23.0) -> np.ndarray:
    rms = float(np.sqrt(np.mean(np.square(audio)) + 1e-12))
    target = 10 ** (db / 20)
    return audio * min(target / rms, 8.0)


def fade(audio: np.ndarray, seconds: float = 0.35) -> np.ndarray:
    n = min(int(seconds * SR), len(audio) // 2)
    ramp = np.linspace(0, 1, n, dtype=np.float32)[:, None]
    audio[:n] *= ramp
    audio[-n:] *= ramp[::-1]
    return audio


def pan(mono: np.ndarray, amount: float) -> np.ndarray:
    left = math.sqrt((1 - amount) * 0.5)
    right = math.sqrt((1 + amount) * 0.5)
    return np.column_stack((mono * left, mono * right))


def tone(freq: float, seconds: float, gain: float, *, phase: float = 0.0,
         harmonics: tuple[float, ...] = (1.0, 0.24, 0.08)) -> np.ndarray:
    t = np.arange(int(seconds * SR), dtype=np.float64) / SR
    mono = np.zeros_like(t)
    for index, weight in enumerate(harmonics, start=1):
        mono += weight * np.sin(2 * np.pi * freq * index * t + phase / index)
    mono /= sum(harmonics)
    return (mono * gain).astype(np.float32)


def pad(freqs: tuple[float, ...], seconds: float, gain: float) -> np.ndarray:
    t = np.arange(int(seconds * SR), dtype=np.float64) / SR
    mono = np.zeros_like(t)
    for i, freq in enumerate(freqs):
        drift = 0.18 * np.sin(2 * np.pi * (0.025 + i * 0.004) * t)
        phase = 2 * np.pi * freq * t + drift
        mono += np.sin(phase) + 0.16 * np.sin(phase * 2.003)
    mono /= len(freqs) * 1.16
    envelope = np.minimum(t / 3.5, 1) * np.minimum((seconds - t) / 3.5, 1)
    return (mono * envelope * gain).astype(np.float32)


def lowpassed_noise(seconds: float, gain: float, window: int = 1600) -> np.ndarray:
    raw = RNG.normal(0, 1, int(seconds * SR) + window).astype(np.float32)
    kernel = np.ones(window, dtype=np.float32) / window
    smooth = np.convolve(raw, kernel, mode="valid")[:int(seconds * SR)]
    smooth /= max(np.max(np.abs(smooth)), 1e-6)
    return smooth * gain


def bell_note(freq: float, seconds: float, gain: float) -> np.ndarray:
    t = np.arange(int(seconds * SR), dtype=np.float64) / SR
    envelope = np.exp(-t * 1.55) * np.minimum(t * 35, 1)
    mono = (
        np.sin(2 * np.pi * freq * t)
        + 0.42 * np.sin(2 * np.pi * freq * 2.01 * t)
        + 0.13 * np.sin(2 * np.pi * freq * 3.96 * t)
    ) / 1.55
    return (mono * envelope * gain).astype(np.float32)


def place(track: np.ndarray, sound: np.ndarray, start: float, pan_amount: float = 0.0) -> None:
    stereo = pan(sound, pan_amount) if sound.ndim == 1 else sound
    begin = int(start * SR)
    end = min(begin + len(stereo), len(track))
    if end > begin:
        track[begin:end] += stereo[:end - begin]


def limiter(audio: np.ndarray, peak: float = 0.88) -> np.ndarray:
    audio = np.tanh(audio * 1.15) / np.tanh(1.15)
    maximum = float(np.max(np.abs(audio)))
    if maximum > peak:
        audio *= peak / maximum
    return audio.astype(np.float32)


def write_mp3(name: str, audio: np.ndarray) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    wav_path = OUT / f"{name}.wav"
    mp3_path = OUT / f"{name}.mp3"
    data = (limiter(audio) * 32767).astype("<i2")
    with wave.open(str(wav_path), "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(data.tobytes())
    subprocess.run([
        "ffmpeg", "-y", "-v", "error", "-i", str(wav_path),
        "-codec:a", "libmp3lame", "-b:a", "192k", str(mp3_path),
    ], check=True)
    wav_path.unlink()


def music_a() -> np.ndarray:
    seconds = 36.0
    track = np.zeros((int(seconds * SR), 2), dtype=np.float32)
    wind = rms_normalize(fit(decode(ROOT / "assets/audio/loops/wind.ogg"), seconds), -35)
    drone = rms_normalize(fit(decode(ROOT / "assets/audio/music/drone_night.ogg"), seconds), -31)
    track += wind * 0.55 + drone * 0.72
    place(track, pan(pad((36.71, 55.0, 73.42), seconds, 0.105), -0.1), 0)
    for start, note, position in [(6.0, 293.66, -0.38), (15.0, 220.0, 0.32), (24.0, 261.63, -0.12), (31.0, 146.83, 0.25)]:
        place(track, bell_note(note, 4.8, 0.12), start, position)
    return fade(track, 1.8)


def music_b() -> np.ndarray:
    seconds = 36.0
    track = np.zeros((int(seconds * SR), 2), dtype=np.float32)
    cave = rms_normalize(fit(decode(ROOT / "assets/audio/loops/cave.ogg"), seconds), -38)
    track += cave * 0.42
    chords = [
        (0, (73.42, 110.0, 146.83)),
        (9, (58.27, 87.31, 116.54)),
        (18, (87.31, 130.81, 174.61)),
        (27, (65.41, 98.0, 130.81)),
    ]
    for start, chord in chords:
        place(track, pad(chord, 10.5, 0.15), start)
    melody = [(3, 293.66), (7, 349.23), (12, 261.63), (16, 220.0),
              (21, 261.63), (25, 293.66), (30, 220.0), (33, 146.83)]
    for i, (start, note) in enumerate(melody):
        place(track, bell_note(note, 3.5, 0.095), start, -0.25 if i % 2 else 0.25)
    return fade(track, 1.6)


def music_c() -> np.ndarray:
    seconds = 36.0
    track = np.zeros((int(seconds * SR), 2), dtype=np.float32)
    dread = rms_normalize(fit(decode(ROOT / "assets/audio/music/drone_dread.ogg"), seconds), -30)
    track += dread * 0.78
    place(track, pad((41.2, 43.7, 61.8), seconds, 0.13), 0)
    breath = lowpassed_noise(seconds, 0.075, 520)
    modulation = (0.45 + 0.55 * np.sin(np.arange(len(breath)) / SR * 2 * np.pi * 0.11))
    place(track, breath * modulation, 0, 0.25)
    for start in (7.5, 15.5, 23.5, 30.0):
        hit = tone(42.0, 1.8, 0.30, harmonics=(1.0, 0.35))
        hit *= np.exp(-np.arange(len(hit)) / SR * 3.0)
        place(track, hit, start)
    return fade(track, 1.4)


def make_reel(name: str, paths: list[Path], *, clip: float = 2.2, silence: float = 0.55,
              target_db: float = -20.0) -> None:
    parts: list[np.ndarray] = []
    gap = np.zeros((int(silence * SR), 2), dtype=np.float32)
    for path in paths:
        audio = decode(path)
        audio = fade(rms_normalize(audio[:int(clip * SR)], target_db), 0.06)
        parts.extend([audio, gap.copy()])
    write_mp3(name, np.concatenate(parts, axis=0))


def ambience_medley(name: str, layers: list[tuple[Path, Path | None]]) -> None:
    parts: list[np.ndarray] = []
    for ambient, music in layers:
        section = rms_normalize(fit(decode(ambient), 7.5), -28) * 0.72
        if music:
            section += rms_normalize(fit(decode(music), 7.5), -33) * 0.62
        parts.append(fade(section, 0.45))
    write_mp3(name, np.concatenate(parts, axis=0))


def vampire_demo(name: str, mode: str) -> None:
    seconds = 18.0
    track = np.zeros((int(seconds * SR), 2), dtype=np.float32)
    dread = rms_normalize(fit(decode(ROOT / "assets/audio/music/drone_dread.ogg"), seconds), -38)
    track += dread * 0.35
    hover_gain = {"subtle": 0.052, "predator": 0.082, "horror": 0.11}[mode]
    hover = lowpassed_noise(seconds, hover_gain, 340 if mode == "horror" else 780)
    lfo = 0.55 + 0.45 * np.sin(np.arange(len(hover)) / SR * 2 * np.pi * (0.18 if mode == "subtle" else 0.31))
    place(track, hover * lfo, 0, -0.1)
    if mode == "subtle":
        place(track, bell_note(164.81, 4.2, 0.055), 7.0, 0.32)
    elif mode == "predator":
        place(track, bell_note(82.41, 3.2, 0.12), 5.0, -0.3)
        shriek = rms_normalize(decode(ROOT / "assets/audio/sfx/shriek_2.wav")[:int(2.0 * SR)], -22)
        place(track, shriek * 0.42, 11.5, 0.35)
    else:
        shriek = rms_normalize(decode(ROOT / "assets/audio/sfx/shriek_4.wav")[:int(2.8 * SR)], -20)
        place(track, shriek * 0.62, 9.2, 0.1)
        hit = tone(38.0, 2.5, 0.34, harmonics=(1.0, 0.5, 0.2))
        hit *= np.exp(-np.arange(len(hit)) / SR * 2.6)
        place(track, hit, 12.0)
    # Audition all three identities at comparable loudness. Runtime mixing can
    # make the subtle version quieter after the artistic direction is chosen.
    write_mp3(name, fade(rms_normalize(track, -28.5), 0.8))


def main() -> None:
    write_mp3("music_A_minimal_cinematic", rms_normalize(music_a(), -25.5))
    write_mp3("music_B_emotional_dark", rms_normalize(music_b(), -25.5))
    write_mp3("music_C_horror_cinematic", rms_normalize(music_c(), -25.5))

    make_reel("hero_movement_sfx", [
        ROOT / "assets/audio/sfx/step_grass_1.wav",
        ROOT / "assets/audio/sfx/step_stone_2.wav",
        ROOT / "assets/audio/sfx/step_wood_3.wav",
        ROOT / "assets/audio/sfx/step_water_2.wav",
        ROOT / "assets/audio/sfx/land_2.wav",
        ROOT / "assets/audio/sfx/land_5.wav",
    ], clip=1.35, silence=0.65)
    make_reel("physics_environment_sfx", [
        ROOT / "assets/audio/sfx/drag_1.wav",
        ROOT / "assets/audio/sfx/wood_3.wav",
        ROOT / "assets/audio/sfx/rope_2.wav",
        ROOT / "assets/audio/sfx/chain_3.wav",
        ROOT / "assets/audio/sfx/gate_2.wav",
        ROOT / "assets/audio/sfx/gear_4.wav",
        ROOT / "assets/audio/sfx/splash_3.wav",
        ROOT / "assets/audio/sfx/thunder_2.ogg",
    ], clip=2.0, silence=0.6)

    ambience_medley("chapters_01_05_ambience", [
        (ROOT / "assets/audio/loops/wind.ogg", None),
        (ROOT / "assets/audio/loops/wind.ogg", ROOT / "assets/audio/music/drone_night.ogg"),
        (ROOT / "assets/audio/loops/cave.ogg", ROOT / "assets/audio/music/drone_cave.ogg"),
        (ROOT / "assets/audio/loops/cave.ogg", None),
        (ROOT / "assets/audio/loops/dungeon.ogg", ROOT / "assets/audio/music/drone_dread.ogg"),
    ])
    ambience_medley("chapters_06_10_ambience", [
        (ROOT / "assets/audio/loops/cave.ogg", ROOT / "assets/audio/music/drone_dread.ogg"),
        (ROOT / "assets/audio/loops/wind.ogg", ROOT / "assets/audio/music/drone_castle.ogg"),
        (ROOT / "assets/audio/loops/dungeon.ogg", ROOT / "assets/audio/music/drone_castle.ogg"),
        (ROOT / "assets/audio/loops/wind.ogg", ROOT / "assets/audio/music/drone_dread.ogg"),
        (ROOT / "assets/audio/loops/clockwork.ogg", ROOT / "assets/audio/music/drone_castle.ogg"),
    ])
    ambience_medley("chapters_11_15_ambience", [
        (ROOT / "assets/audio/loops/dungeon.ogg", ROOT / "assets/audio/music/drone_dread.ogg"),
        (ROOT / "assets/audio/loops/river.ogg", None),
        (ROOT / "assets/audio/loops/wind.ogg", ROOT / "assets/audio/music/drone_castle.ogg"),
        (ROOT / "assets/audio/loops/rain.ogg", None),
        (ROOT / "assets/audio/loops/birds.ogg", ROOT / "assets/audio/music/ending_c.ogg"),
    ])

    vampire_demo("vampire_A_subtle_presence", "subtle")
    vampire_demo("vampire_B_predator", "predator")
    vampire_demo("vampire_C_full_horror", "horror")


if __name__ == "__main__":
    main()
