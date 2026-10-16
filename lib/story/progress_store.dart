import 'package:shared_preferences/shared_preferences.dart';

/// The furthest chapter the boy has reached, kept between runs so the
/// title can offer to continue, and so the chapter list knows what is
/// unlocked. Nothing else is saved: inside a chapter, death costs only the
/// way back from the last checkpoint.
class ProgressStore {
  /// Kept in memory only, for tests and the proving ground.
  ProgressStore.memory([this._reached = 0]) : _prefs = null;

  ProgressStore._(this._prefs, this._reached);

  /// Reads the saved progress from the device.
  static Future<ProgressStore> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return ProgressStore._(prefs, prefs.getInt(_key) ?? 0);
    } catch (_) {
      // No storage (an odd platform, a broken plugin): play on unsaved.
      return ProgressStore.memory();
    }
  }

  static const String _key = 'umbra.reachedChapter';

  final SharedPreferences? _prefs;
  int _reached;

  /// The index (from 0) of the furthest chapter started.
  int get reached => _reached;

  /// Records that chapter [index] has been started.
  Future<void> reach(int index) async {
    if (index <= _reached) return;
    _reached = index;
    await _prefs?.setInt(_key, index);
  }
}
