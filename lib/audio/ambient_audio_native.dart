import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../config/game_settings.dart';
import 'sound_bank.dart';

/// The game's sound, unlocked by a gesture: the wind, a loop for the place,
/// the music (the menu's, the one the player picked for play, the chase's,
/// and the piece under the credits), and the effects.
///
/// The player's settings rule it: all sound on or off (the speaker), music
/// on or off, and how loud the music, the ambience and the effects are.
///
/// Every effect is a recording with several takes (see [SoundBank]); each
/// time it plays one is picked at random, never the same twice running,
/// a little louder or softer, and from the side it happened on.
class AmbientAudio {
  AmbientAudio({required this.settings, required this.outputEnabled});
  final GameSettings settings;
  final bool outputEnabled;

  /// All sound on (the speaker setting).
  bool get enabled => settings.soundOn;
  bool _wasEnabled = true;
  bool _paused = false, _loading = false, _ready = false, _disposed = false;

  final _Loop _wind = _Loop(0.45), _bed = _Loop(0.55);
  final _Loop _score = _Loop(0.8, isMusic: true);
  AudioPlayer? _music;
  String? _musicName;
  final Map<String, List<AudioPlayer>> _takes = {};
  final Map<String, int> _lastTake = {};
  final Map<AudioPlayer, Future<void>> _pending = {};
  int _effectEpoch = 0;
  final math.Random _random = math.Random();

  /// How strong the wind is here, 0–1 (indoors it is only heard faintly).
  double windLevel = 1;

  Iterable<_Loop> get _loops => [_wind, _bed, _score];

  Future<void> unlock() async {
    if (!outputEnabled || _loading || _disposed) return;
    if (_ready) {
      if (enabled && !_paused) await _resumeLoops();
      return;
    }
    _loading = true;
    await _guard(() async {
      await AudioPlayer.global.ensureInitialized();
      // Every player mixes with the others. By default each one asks Android
      // for the audio focus when it starts, and the one that loses it is
      // paused for good: every footstep silenced the music, the wind and the
      // footstep before it.
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            audioFocus: AndroidAudioFocus.none,
            usageType: AndroidUsageType.game,
            contentType: AndroidContentType.sonification,
          ),
          iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
        ),
      );
      // The music and the loops first, so the menu's music starts at once;
      // the effects load behind it.
      for (final loop in _loops) {
        await loop.player.setReleaseMode(ReleaseMode.loop);
      }
      final music = _music = AudioPlayer();
      await music.setReleaseMode(ReleaseMode.stop);
      _wind.want = 'wind';
      _wasEnabled = enabled;
      _ready = true;
      await updateMix();
      // Short effects go through Android's low-latency pool, so a footstep
      // lands with the foot.
      final bool pool =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      for (final MapEntry(key: name, value: count)
          in SoundBank.effects.entries) {
        final List<AudioPlayer> takes = [];
        // In a browser every player opens its own audio context. Keep all
        // the outdoor footsteps, three of each other surface's (so a run
        // never falls into a two-step rhythm), and two of everything else.
        final takeCount = !kIsWeb || name == 'step_run'
            ? count
            : math.min(count, name.startsWith('step_') ? 3 : 2);
        for (var i = 1; i <= takeCount; i++) {
          if (_disposed) return;
          final voice = AudioPlayer();
          if (pool && !SoundBank.long.contains(name)) {
            await voice.setPlayerMode(PlayerMode.lowLatency);
          }
          await voice.setReleaseMode(ReleaseMode.stop);
          await voice.setSource(AssetSource(SoundBank.effect(name, i)));
          takes.add(voice);
        }
        // Heard only once every take is ready.
        _takes[name] = takes;
      }
    });
    _loading = false;
  }

  /// Fades the loops towards what is wanted; call each frame.
  void update(double dt) {
    if (!_ready || _disposed) return;
    for (final loop in _loops) {
      final double level = _loopLevel(loop);
      unawaited(_guard(() => loop.update(dt, level, _gainOf(loop))));
    }
  }

  double _loopLevel(_Loop loop) {
    if (loop == _wind) return windLevel;
    // The piece under the credits takes over from the looping music.
    if (loop == _score) return _musicName == null ? 1 : 0;
    return 0.65;
  }

  double get _gain => enabled && !_paused ? settings.ambience : 0;

  /// How loud the music is: none with music or all sound off.
  double get _musicGain =>
      enabled && !_paused && settings.musicOn ? settings.music : 0;

  double _gainOf(_Loop loop) => loop.isMusic ? _musicGain : _gain;

  /// Brings the sound in line with the settings: call when they change.
  Future<void> updateMix() async {
    if (!_ready || _disposed) return;
    if (enabled != _wasEnabled) {
      // The speaker switched: everything stops or starts again.
      _wasEnabled = enabled;
      if (!enabled) _effectEpoch++;
      await _guard(() async {
        for (final loop in _loops) {
          if (enabled && !_paused && loop.name != null) {
            await loop.player.resume();
          } else {
            await loop.player.pause();
          }
        }
        if (_musicName != null) {
          enabled && !_paused ? await _music?.resume() : await _music?.pause();
        }
      });
    }
    await _guard(() async {
      for (final loop in _loops) {
        await loop.applyVolume(_loopLevel(loop), _gainOf(loop));
      }
      await _music?.setVolume(_musicGain);
    });
  }

  /// Plays a take of [name] at [weight] (0–1), [pan] from the left (−1)
  /// to the right (1).
  void effect(String name, double weight, [double pan = 0]) {
    final List<AudioPlayer>? takes = _takes[name];
    if (_paused ||
        _disposed ||
        !enabled ||
        settings.effects == 0 ||
        takes == null ||
        takes.isEmpty) {
      return;
    }
    int i = _random.nextInt(takes.length);
    if (takes.length > 1 && i == _lastTake[name]) i = (i + 1) % takes.length;
    // Pick a free voice first. If platform commands are briefly delayed,
    // serialize on that voice instead of silently discarding a footstrike.
    for (var offset = 0; offset < takes.length; offset++) {
      final candidate = (i + offset) % takes.length;
      if (!_pending.containsKey(takes[candidate])) {
        i = candidate;
        break;
      }
    }
    _lastTake[name] = i;
    final AudioPlayer voice = takes[i];
    final previous = _pending[voice];
    final epoch = _effectEpoch;
    final double volume =
        (weight * settings.effects * (0.94 + 0.06 * _random.nextDouble()))
            .clamp(0.0, 1.0);
    late final Future<void> playback;
    playback =
        _guard(() async {
          if (previous != null) await previous;
          if (_disposed || _paused || !enabled || epoch != _effectEpoch) return;
          // Stop resets to zero without waiting for a browser seeked event.
          // Seeking an already stopped HTML player can stall until timeout.
          await voice.stop();
          await voice.setVolume(volume);
          await voice.setBalance(pan.clamp(-0.9, 0.9));
          if (_disposed || _paused || !enabled || epoch != _effectEpoch) return;
          await voice.resume();
        }).whenComplete(() {
          if (identical(_pending[voice], playback)) _pending.remove(voice);
        });
    _pending[voice] = playback;
    unawaited(playback);
  }

  /// Sets the loop for the place ([name] in SoundBank.loops, or null for
  /// none); the old one fades out and the new one in.
  void bed(String? name) => _bed.want = name;

  /// Sets the looping music ([name] in SoundBank: the menu's, a background,
  /// the chase's), or none with null; it crossfades from the last.
  void score(String? name) => _score.want = name;

  /// Plays the piece [name] once through (the music under the credits),
  /// or stops it with null.
  Future<void> music(String? name) async {
    final AudioPlayer? player = _music;
    if (!_ready || player == null || name == _musicName) return;
    _musicName = name;
    await _guard(() async {
      await player.stop();
      if (name == null) return;
      await player.setSource(AssetSource(SoundBank.music(name)));
      await player.setVolume(_musicGain);
      if (enabled && !_paused) await player.resume();
    });
  }

  void cancelEffects() {
    _effectEpoch++;
    if (!_ready) return;
    for (final takes in _takes.values) {
      for (final voice in takes) {
        unawaited(_guard(voice.stop));
      }
    }
  }

  Future<void> pause() async {
    _paused = true;
    _effectEpoch++;
    if (!_ready) return;
    await _guard(() async {
      for (final loop in _loops) {
        await loop.player.pause();
      }
      await _music?.pause();
      for (final takes in _takes.values) {
        for (final voice in takes) {
          await voice.stop();
        }
      }
    });
  }

  Future<void> resume() async {
    _paused = false;
    if (_ready && enabled) {
      await _resumeLoops();
      if (_musicName != null) await _guard(() async => _music?.resume());
    }
  }

  Future<void> _resumeLoops() async {
    await _guard(() async {
      for (final loop in _loops) {
        if (loop.name != null) await loop.player.resume();
      }
    });
  }

  /// The speaker: all sound off, or on again (the M key).
  Future<void> toggle() async {
    settings.setFlag('soundOn', !enabled);
    if (!_ready) await unlock();
  }

  Future<void> dispose() async {
    _disposed = true;
    _effectEpoch++;
    _ready = false;
    await _guard(() async {
      for (final loop in _loops) {
        await loop.dispose();
      }
      await _music?.dispose();
      for (final takes in _takes.values) {
        for (final voice in takes) {
          await voice.dispose();
        }
      }
      _takes.clear();
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (kDebugMode && !_disposed) debugPrint('Umbra audio: $error');
    }
  }
}

/// A looping sound that fades out before it changes and in after.
class _Loop {
  _Loop(this.mix, {this.isMusic = false});
  final bool isMusic;

  /// Its share of the ambience volume.
  final double mix;
  AudioPlayer? _player;
  AudioPlayer get player => _player ??= AudioPlayer();
  Future<void> dispose() async => _player?.dispose();

  /// What is playing, and what should be.
  String? name, want;

  /// How far faded in, 0–1.
  double _fade = 0;
  double _heard = -1;
  bool _switching = false;

  /// Switched while silent: set, but not yet playing.
  bool _waiting = false;

  Future<void> update(double dt, double level, double gain) async {
    if (_switching) return;
    if (want != name) {
      // Out first; then the next loop.
      _fade = math.max(0, _fade - dt / 1.6);
      if (_fade > 0 && name != null) return applyVolume(level, gain);
      _switching = true;
      try {
        name = want;
        await player.stop();
        final String? next = name;
        if (next != null) {
          await player.setSource(
            AssetSource(isMusic ? SoundBank.music(next) : SoundBank.loop(next)),
          );
          await player.setVolume(0);
          _heard = 0;
          _waiting = gain <= 0;
          if (!_waiting) _start();
        }
      } finally {
        _switching = false;
      }
      return;
    }
    if (name == null) return;
    if (_waiting && gain > 0) {
      _waiting = false;
      _start();
    }
    _fade = math.min(1, _fade + dt / 2.4);
    return applyVolume(level, gain);
  }

  /// Starts it playing without waiting for the platform to say it has:
  /// a browser that cannot reach an audio device never does, and the next
  /// change of music must not wait behind it.
  void _start() => unawaited(
    player.resume().catchError((Object error) {
      if (kDebugMode) debugPrint('Umbra audio: $error');
    }),
  );

  Future<void> applyVolume(double level, double gain) async {
    final double volume = mix * level * gain * _fade;
    // Only when it is heard to change: each call crosses to the platform.
    if ((volume - _heard).abs() < 0.01) return;
    _heard = volume;
    await player.setVolume(volume);
  }
}
