import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../config/game_settings.dart';

/// A loop and a bounded set of reusable effect voices, unlocked by a gesture.
/// The source WAVs are original synthesized sounds (tool/audio/generate.py).
class AmbientAudio {
  AmbientAudio({required this.settings, required this.outputEnabled});
  final GameSettings settings;
  final bool outputEnabled;
  bool enabled = true;
  bool _paused = false, _loading = false, _ready = false, _disposed = false;
  AudioPlayer? _wind;
  AudioPlayer? _bed, _music;
  String? _bedName, _wantBed, _musicName;
  final Map<String, AudioPlayer> _voices = {};

  /// Every one-shot effect there is, each `assets/audio/NAME.wav`.
  static const List<String> effects = [
    'step', 'land', 'rope', 'drag', 'water', //
    'tick', 'gear', 'hammer', 'bell', 'gate', 'chain', 'wood', 'fire',
    'burn', 'shriek', 'thunder', 'splash', 'rumble', 'heartbeat', 'creak',
  ];
  final Set<String> _busy = {};

  Future<void> unlock() async {
    if (!outputEnabled || _loading || _disposed) return;
    if (_ready) {
      if (enabled && !_paused && _wind?.state != PlayerState.playing) {
        await _guard(() async => _wind?.resume());
      }
      return;
    }
    _loading = true;
    await _guard(() async {
      await AudioPlayer.global.ensureInitialized();
      if (_disposed) return;
      final wind = _wind = AudioPlayer();
      await wind.setReleaseMode(ReleaseMode.loop);
      await wind.setSource(AssetSource('audio/wind.wav'));
      for (final name in effects) {
        if (_disposed) return;
        final voice = _voices[name] = AudioPlayer();
        await voice.setReleaseMode(ReleaseMode.stop);
        await voice.setSource(AssetSource('audio/$name.wav'));
      }
      if (_disposed) return;
      final bed = _bed = AudioPlayer();
      await bed.setReleaseMode(ReleaseMode.loop);
      final music = _music = AudioPlayer();
      await music.setReleaseMode(ReleaseMode.stop);
      _ready = true;
      await updateMix();
      if (enabled && !_paused) await wind.resume();
      await _switchBed();
    });
    _loading = false;
  }

  Future<void> updateMix() async {
    if (!_ready || _disposed) return;
    await _guard(() async {
      await _wind?.setVolume(enabled ? settings.ambience * 0.45 : 0);
      await _bed?.setVolume(enabled ? settings.ambience * 0.55 : 0);
      await _music?.setVolume(enabled ? settings.ambience * 0.8 : 0);
      for (final voice in _voices.values) {
        await voice.setVolume(enabled ? settings.effects * 0.5 : 0);
      }
    });
  }

  Future<void> effect(String name, double weight) async {
    final voice = _voices[name];
    if (!_ready ||
        _paused ||
        _disposed ||
        !enabled ||
        settings.effects == 0 ||
        voice == null ||
        !_busy.add(name)) {
      return;
    }
    try {
      await _guard(() async {
        await voice.setVolume((weight * settings.effects).clamp(0, 1));
        await voice.seek(Duration.zero);
        await voice.resume();
      });
    } finally {
      _busy.remove(name);
    }
  }

  /// Sets the loop under the wind ([name] in assets/audio, or null for
  /// none). It changes once the sound is unlocked.
  Future<void> bed(String? name) async {
    _wantBed = name;
    if (_ready) await _switchBed();
  }

  Future<void> _switchBed() async {
    if (_wantBed == _bedName) return;
    final AudioPlayer? bed = _bed;
    if (bed == null) return;
    _bedName = _wantBed;
    await _guard(() async {
      await bed.stop();
      final String? name = _bedName;
      if (name == null) return;
      await bed.setSource(AssetSource('audio/$name.wav'));
      if (enabled && !_paused) await bed.resume();
    });
  }

  /// Plays the piece [name] once through (the music under the credits),
  /// or stops it with null.
  Future<void> music(String? name) async {
    final AudioPlayer? player = _music;
    if (!_ready || player == null || name == _musicName) return;
    _musicName = name;
    await _guard(() async {
      await player.stop();
      if (name == null) return;
      await player.setSource(AssetSource('audio/$name.wav'));
      if (enabled && !_paused) await player.resume();
    });
  }

  Future<void> pause() async {
    _paused = true;
    if (!_ready) return;
    await _guard(() async {
      await _wind?.pause();
      await _bed?.pause();
      await _music?.pause();
      for (final voice in _voices.values) {
        await voice.stop();
      }
    });
  }

  Future<void> resume() async {
    _paused = false;
    if (_ready && enabled) {
      await _guard(() async {
        await _wind?.resume();
        if (_bedName != null) await _bed?.resume();
        if (_musicName != null) await _music?.resume();
      });
    }
  }

  Future<void> toggle() async {
    enabled = !enabled;
    if (!_ready) {
      await unlock();
      return;
    }
    await updateMix();
    if (enabled && !_paused) {
      await _guard(() async => _wind?.resume());
    } else {
      await _guard(() async => _wind?.pause());
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _ready = false;
    await _guard(() async {
      await _wind?.dispose();
      await _bed?.dispose();
      await _music?.dispose();
      for (final voice in _voices.values.toList()) {
        await voice.dispose();
      }
      _voices.clear();
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
