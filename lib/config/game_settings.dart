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
    final Object? track = _preferences?.get('umbra.settings.background');
    musicOn = musicFlag is bool ? musicFlag : true;
    soundOn = soundFlag is bool ? soundFlag : true;
    background = track is String ? track : defaultBackground;
    final vibrationFlag = _preferences?.get('umbra.settings.vibration');
    vibration = vibrationFlag is bool ? vibrationFlag : true;
  }

  /// The music under play until the player picks another.
  static const String defaultBackground = 'bg_descent';

  final SharedPreferences? _preferences;
  late double brightness, atmosphere, controlsScale, controlsOpacity;
  late double ambience, effects, music;

  /// Music on or off, and all sound on or off (the speaker).
  late bool musicOn, soundOn, vibration;

  /// The music under play: one of the backgrounds in the sound bank.
  late String background;

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
      default:
        throw ArgumentError.value(key, 'key');
    }
    _store(() => _preferences?.setBool('umbra.settings.$key', value));
    notifyListeners();
  }

  /// Picks the music under play.
  void setBackground(String id) {
    if (id == background) return;
    background = id;
    _store(() => _preferences?.setString('umbra.settings.background', id));
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
    background = defaults.background;
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
