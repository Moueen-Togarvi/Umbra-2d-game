import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../chapters/campaign_catalog.dart';

/// One atomic, versioned record. Checkpoints restore authored safe states.
class ProgressStore {
  ProgressStore.memory([this._reached = 0])
    : _prefs = null,
      _current = _reached;
  ProgressStore._(this._prefs, this._reached, this._current, this.checkpoint);
  final SharedPreferences? _prefs;
  static const key = 'umbra.campaign.v2';
  int _reached, _current;
  String? checkpoint;
  Future<void> _pending = Future.value();
  int get reached => _reached;
  int get current => _current;
  bool get canContinue => _current > 0 || checkpoint != null;

  static Future<ProgressStore> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw != null) {
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final reached = CampaignCatalog.indexOf(data['furthest'] as String);
          final current = CampaignCatalog.indexOf(data['chapter'] as String);
          if (data['version'] == 2 &&
              reached >= 0 &&
              current >= 0 &&
              current <= reached) {
            return ProgressStore._(
              prefs,
              reached,
              current,
              data['checkpoint'] as String?,
            );
          }
        } catch (_) {
          /* Recover using the untouched legacy record. */
        }
      }
      final old = prefs.getInt('umbra.reachedChapter') ?? 0;
      final migrated = CampaignCatalog.migrateIndex(old);
      final store = ProgressStore._(prefs, migrated, migrated, null);
      await store._save();
      return store;
    } catch (_) {
      return ProgressStore.memory();
    }
  }

  Future<void> _save() {
    final value = jsonEncode({
      'version': 2,
      'furthest': CampaignCatalog.ids[_reached],
      'chapter': CampaignCatalog.ids[_current],
      'checkpoint': checkpoint,
    });
    _pending = _pending.then((_) async {
      try {
        await _prefs?.setString(key, value);
      } catch (_) {
        /* Keep this session playable. */
      }
    });
    return _pending;
  }

  Future<void> reach(int index) {
    if (index < 0 || index >= CampaignCatalog.ids.length) return Future.value();
    if (index > _reached) _reached = index;
    return _save();
  }

  Future<void> enter(int index, {bool resume = false}) {
    if (index < 0 || index >= CampaignCatalog.ids.length) return Future.value();
    if (!resume || _current != index) checkpoint = null;
    _current = index;
    if (index > _reached) _reached = index;
    return _save();
  }

  Future<void> saveCheckpoint(String chapterId, String checkpointId) {
    if (CampaignCatalog.ids[_current] != chapterId) return Future.value();
    checkpoint = checkpointId;
    return _save();
  }
}
