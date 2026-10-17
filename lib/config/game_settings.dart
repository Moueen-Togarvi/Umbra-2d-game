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
  }

  final SharedPreferences? _preferences;
  late double brightness, atmosphere, controlsScale, controlsOpacity;
  late double ambience, effects;

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
      'atmosphere' || 'ambience' || 'effects' => value.clamp(0.0, 1.0),
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
    }
    _save(key, next);
    notifyListeners();
  }

  static Future<GameSettings> load() async {
    try {
      return GameSettings(preferences: await SharedPreferences.getInstance());
    } catch (_) {
      return GameSettings();
    }
  }
}
