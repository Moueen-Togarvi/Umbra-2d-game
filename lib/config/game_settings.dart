import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences, independent of chapter progress and physics tuning.
class GameSettings extends ChangeNotifier {
  // Keep the public constructor argument readable while storage remains private.
  // ignore: prefer_initializing_formals
  GameSettings({SharedPreferences? preferences}) : _preferences = preferences {
    brightness = _read('brightness', 1, 0.8, 1.3);
    atmosphere = _read('atmosphere', 0.65, 0, 1);
    controlsScale = _read('controlsScale', 1, 0.8, 1.3);
    controlsOpacity = _read('controlsOpacity', 0.7, 0.3, 1);
    ambience = _read('ambience', 0.65, 0, 1);
    effects = _read('effects', 0.8, 0, 1);
    music = _read('music', 0.6, 0, 1);
    final Object? musicFlag = _preferences?.get('umbra.settings.musicOn');
    final Object? soundFlag = _preferences?.get('umbra.settings.soundOn');
    musicOn = musicFlag is bool ? musicFlag : true;
    soundOn = soundFlag is bool ? soundFlag : true;
    final vibrationFlag = _preferences?.get('umbra.settings.vibration');
    vibration = vibrationFlag is bool ? vibrationFlag : true;
    cameraShake = _preferences?.getBool('umbra.settings.cameraShake') ?? true;
    leftHanded = _preferences?.getBool('umbra.settings.leftHanded') ?? false;
    reducedMotion =
        _preferences?.getBool('umbra.settings.reducedMotion') ?? false;
    tutorialComplete =
        _preferences?.getBool('umbra.tutorial.complete') ?? false;
    controlPositions = _readControlPositions();
  }

  final SharedPreferences? _preferences;
  late double brightness, atmosphere, controlsScale, controlsOpacity;
  late double ambience, effects, music;

  /// Music on or off, and all sound on or off (the speaker).
  late bool musicOn, soundOn, vibration;
  late bool cameraShake, leftHanded;
  late bool reducedMotion;
  late bool tutorialComplete;

  late Map<String, Offset> controlPositions;

  static const _controlPositionsKey = 'umbra.settings.controlPositions';

  Map<String, Offset> _readControlPositions() {
    final raw = _preferences?.getString(_controlPositionsKey);
    if (raw == null) return {};
    try {
      final values = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in values.entries)
          if (entry.value is List &&
              (entry.value as List).length == 2 &&
              entry.value[0] is num &&
              entry.value[1] is num &&
              (entry.value[0] as num).isFinite &&
              (entry.value[1] as num).isFinite)
            entry.key: Offset(
              (entry.value[0] as num).toDouble().clamp(0.0, 1.0),
              (entry.value[1] as num).toDouble().clamp(0.0, 1.0),
            ),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> saveControlPositions(Map<String, Offset> positions) async {
    controlPositions = {
      for (final entry in positions.entries)
        entry.key: Offset(
          entry.value.dx.clamp(0.0, 1.0),
          entry.value.dy.clamp(0.0, 1.0),
        ),
    };
    final value = jsonEncode({
      for (final entry in controlPositions.entries)
        entry.key: [entry.value.dx, entry.value.dy],
    });
    await _store(() => _preferences?.setString(_controlPositionsKey, value));
    notifyListeners();
  }

  Future<void> resetControlPositions() async {
    controlPositions = {};
    await _store(() => _preferences?.remove(_controlPositionsKey));
    notifyListeners();
  }

  Future<void> completeTutorial() async {
    if (tutorialComplete) return;
    tutorialComplete = true;
    await _store(() => _preferences?.setBool('umbra.tutorial.complete', true));
    notifyListeners();
  }

  double _read(String key, double fallback, double min, double max) {
    final value = _preferences?.get('umbra.settings.$key');
    return value is num && value.isFinite
        ? value.toDouble().clamp(min, max)
        : fallback;
  }

  Future<void> _save(String key, double value) async {
    try {
      await _preferences?.setDouble('umbra.settings.$key', value);
    } catch (error) {
      if (kDebugMode) debugPrint('Settings could not be saved: $error');
    }
  }

  void set(String key, double value) {
    if (!value.isFinite) return;
    final next = switch (key) {
      'brightness' => value.clamp(0.8, 1.3),
      'controlsScale' => value.clamp(0.8, 1.3),
      'controlsOpacity' => value.clamp(0.3, 1.0),
      'atmosphere' ||
      'ambience' ||
      'effects' ||
      'music' => value.clamp(0.0, 1.0),
      _ => throw ArgumentError.value(key, 'key'),
    };
    switch (key) {
      case 'brightness':
        brightness = next;
      case 'atmosphere':
        atmosphere = next;
      case 'controlsScale':
        controlsScale = next;
      case 'controlsOpacity':
        controlsOpacity = next;
      case 'ambience':
        ambience = next;
      case 'effects':
        effects = next;
      case 'music':
        music = next;
    }
    _save(key, next);
    notifyListeners();
  }

  /// Turns the music ([key] `musicOn`) or all sound (`soundOn`) on or off.
  void setFlag(String key, bool value) {
    switch (key) {
      case 'musicOn':
        musicOn = value;
      case 'soundOn':
        soundOn = value;
      case 'vibration':
        vibration = value;
      case 'cameraShake':
        cameraShake = value;
      case 'leftHanded':
        leftHanded = value;
      case 'reducedMotion':
        reducedMotion = value;
      default:
        throw ArgumentError.value(key, 'key');
    }
    _store(() => _preferences?.setBool('umbra.settings.$key', value));
    notifyListeners();
  }

  Future<void> _store(Future<bool>? Function() write) async {
    try {
      await write();
    } catch (error) {
      if (kDebugMode) debugPrint('Settings could not be saved: $error');
    }
  }

  /// Restore preferences only; campaign progress has separate storage.
  Future<void> reset() async {
    final defaults = GameSettings();
    brightness = defaults.brightness;
    atmosphere = defaults.atmosphere;
    controlsScale = defaults.controlsScale;
    controlsOpacity = defaults.controlsOpacity;
    ambience = defaults.ambience;
    effects = defaults.effects;
    music = defaults.music;
    musicOn = defaults.musicOn;
    soundOn = defaults.soundOn;
    vibration = defaults.vibration;
    cameraShake = defaults.cameraShake;
    leftHanded = defaults.leftHanded;
    reducedMotion = defaults.reducedMotion;
    controlPositions = {};
    notifyListeners();
    for (final key in _preferences?.getKeys().toList() ?? <String>[]) {
      if (key.startsWith('umbra.settings.')) {
        await _store(() => _preferences?.remove(key));
      }
    }
  }

  static Future<GameSettings> load() async {
    try {
      return GameSettings(preferences: await SharedPreferences.getInstance());
    } catch (_) {
      return GameSettings();
    }
  }
}
