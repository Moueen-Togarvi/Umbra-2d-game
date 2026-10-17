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
  final Map<String, AudioPlayer> _voices = {};
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
      for (final name in ['step', 'land', 'rope', 'drag', 'water']) {
        if (_disposed) return;
        final voice = _voices[name] = AudioPlayer();
        await voice.setReleaseMode(ReleaseMode.stop);
        await voice.setSource(AssetSource('audio/$name.wav'));
      }
      if (_disposed) return;
      _ready = true;
      await updateMix();
      if (enabled && !_paused) await wind.resume();
    });
    _loading = false;
  }

  Future<void> updateMix() async {
    if (!_ready || _disposed) return;
    await _guard(() async {
      await _wind?.setVolume(enabled ? settings.ambience * 0.45 : 0);
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

  Future<void> pause() async {
    _paused = true;
    if (!_ready) return;
    await _guard(() async {
      await _wind?.pause();
      for (final voice in _voices.values) {
        await voice.stop();
      }
    });
  }

  Future<void> resume() async {
    _paused = false;
    if (_ready && enabled) await _guard(() async => _wind?.resume());
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
