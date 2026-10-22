import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'package:web/web.dart' as web;
import '../config/game_settings.dart';
import 'sound_bank.dart';

/// All browser sound shares one context. Long tracks stream; only SFX decode.
class AmbientAudio {
  AmbientAudio({required this.settings, required this.outputEnabled});
  final GameSettings settings;
  final bool outputEnabled;
  bool get enabled => settings.soundOn;
  bool _paused = false, _disposed = false;
  web.AudioContext? _context;
  final _random = math.Random();
  final _lastTake = <String, int>{};
  final _buffers = <String, Future<web.AudioBuffer>>{};
  final _voices = <_Voice>[];
  final _tracks = <String, _Track>{};
  int _epoch = 0;
  String? _bed, _score, _ending;
  double _clock = 0;
  int get activeVoices => _voices.length;
  static const maxVoices = 12;

  Future<void> unlock() async {
    if (!outputEnabled || _disposed) return;
    _context ??= web.AudioContext();
    if (!_paused) {
      try {
        await _context!.resume().toDart;
      } catch (_) {}
    }
    update(0);
  }

  void bed(String? name) => _bed = name;
  void score(String? name) => _score = name;
  Future<void> music(String? name) async {
    if (_ending == name) return;
    _ending = name;
    _setTrack(
      'ending',
      name == null ? null : SoundBank.music(name),
      loop: false,
    );
  }

  void update(double dt) {
    if (_context == null || _disposed) return;
    _clock += dt;
    _setTrack('bed', _bed == null ? null : SoundBank.loop(_bed!));
    _setTrack(
      'score',
      _ending != null || _score == null ? null : SoundBank.music(_score!),
    );
    if (_ending != null) {
      _setTrack('ending', SoundBank.music(_ending!), loop: false);
    }
    for (final entry in _tracks.entries) {
      final track = entry.value;
      final isMusic = entry.key == 'score' || entry.key == 'ending';
      final gain = !enabled || _paused
          ? 0.0
          : isMusic
          ? (settings.musicOn ? settings.music : 0.0)
          : settings.ambience * .36;
      track.update(dt, gain, enabled && !_paused);
    }
  }

  void _setTrack(String slot, String? path, {bool loop = true}) {
    final context = _context;
    if (context == null) return;
    final track = _tracks.putIfAbsent(slot, () => _Track(context));
    track.want = path;
    track.loop = loop;
  }

  Future<web.AudioBuffer> _load(String path) =>
      _buffers.putIfAbsent(path, () async {
        try {
          final response = await web.window
              .fetch('assets/assets/$path'.toJS)
              .toDart;
          if (!response.ok) {
            throw StateError('Audio HTTP ${response.status}: $path');
          }
          final bytes = await response.arrayBuffer().toDart;
          return await _context!.decodeAudioData(bytes).toDart;
        } catch (_) {
          _buffers.remove(path);
          rethrow;
        }
      });

  void effect(String name, double weight, [double pan = 0]) {
    final count = SoundBank.effects[name];
    if (_context == null ||
        _paused ||
        _disposed ||
        !enabled ||
        settings.effects == 0 ||
        count == null ||
        weight <= .02) {
      return;
    }
    var take = _random.nextInt(count) + 1;
    if (count > 1 && _lastTake[name] == take) take = take % count + 1;
    _lastTake[name] = take;
    final epoch = _epoch;
    final requested = _clock;
    final priority = name == 'vampire_step'
        ? 2
        : name.startsWith('step_')
        ? 3
        : 1;
    unawaited(
      _load(SoundBank.effect(name, take))
          .then((buffer) {
            if (_disposed ||
                _paused ||
                !enabled ||
                epoch != _epoch ||
                _clock - requested > .2) {
              return;
            }
            if (_voices.length >= maxVoices) {
              var victim = _voices.first;
              for (final v in _voices) {
                if (v.priority < victim.priority) {
                  victim = v;
                }
              }
              if (victim.priority > priority) return;
              victim.stop();
              _voices.remove(victim);
            }
            final context = _context!;
            final source = context.createBufferSource()..buffer = buffer;
            final gain = context.createGain();
            gain.gain.value =
                (weight * settings.effects * (.94 + .06 * _random.nextDouble()))
                    .clamp(0, 1);
            final panner = context.createStereoPanner()
              ..pan.value = pan.clamp(-.9, .9);
            source.connect(gain);
            gain.connect(panner);
            panner.connect(context.destination);
            final voice = _Voice(source, gain, panner, priority);
            _voices.add(voice);
            source.onended = ((web.Event _) {
              voice.dispose();
              _voices.remove(voice);
            }).toJS;
            source.start();
          })
          .catchError((Object _) {}),
    );
  }

  Future<void> updateMix() async {
    if (!enabled || settings.effects == 0) _stopEffects();
    update(0);
  }

  void cancelEffects() => _stopEffects();
  void _stopEffects() {
    _epoch++;
    for (final voice in _voices.toList()) {
      voice.stop();
    }
    _voices.clear();
  }

  Future<void> pause() async {
    _paused = true;
    _stopEffects();
    for (final track in _tracks.values) {
      track.audio.pause();
    }
    try {
      await _context?.suspend().toDart;
    } catch (_) {}
  }

  Future<void> resume() async {
    _paused = false;
    await unlock();
    await updateMix();
  }

  Future<void> toggle() async {
    settings.setFlag('soundOn', !enabled);
    await updateMix();
  }

  Future<void> dispose() async {
    _disposed = true;
    _stopEffects();
    for (final track in _tracks.values) {
      track.dispose();
    }
    _tracks.clear();
    _buffers.clear();
    try {
      await _context?.close().toDart;
    } catch (_) {}
  }
}

class _Voice {
  _Voice(this.source, this.gain, this.pan, this.priority);
  final web.AudioBufferSourceNode source;
  final web.GainNode gain;
  final web.StereoPannerNode pan;
  final int priority;
  bool disposed = false;
  void stop() {
    try {
      source.stop();
    } catch (_) {}
    dispose();
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    source.disconnect();
    gain.disconnect();
    pan.disconnect();
  }
}

class _Track {
  _Track(web.AudioContext context)
    : audio = web.HTMLAudioElement(),
      gain = context.createGain() {
    audio.preload = 'auto';
    source = context.createMediaElementSource(audio);
    source.connect(gain);
    gain.connect(context.destination);
    gain.gain.value = 0;
  }
  final web.HTMLAudioElement audio;
  final web.GainNode gain;
  late final web.MediaElementAudioSourceNode source;
  String? want, current;
  bool loop = true, _starting = false;
  double fade = 0;
  void update(double dt, double volume, bool playing) {
    if (current != want) {
      fade = math.max(0, fade - dt / .7);
      if (fade == 0 || current == null) {
        audio.pause();
        current = want;
        if (current == null) {
          audio.removeAttribute('src');
          audio.load();
        } else {
          audio.src = 'assets/assets/$current';
          audio.loop = loop;
          audio.load();
        }
      }
    } else {
      fade = math.min(1, fade + dt / 1.2);
    }
    gain.gain.value = volume * fade;
    if (!playing || volume == 0) {
      audio.pause();
      return;
    }
    if (current != null && audio.paused && !audio.ended && !_starting) {
      _starting = true;
      unawaited(
        audio
            .play()
            .toDart
            .catchError((Object _) => null)
            .whenComplete(() => _starting = false),
      );
    }
  }

  void dispose() {
    audio.pause();
    audio.removeAttribute('src');
    audio.load();
    source.disconnect();
    gain.disconnect();
  }
}
