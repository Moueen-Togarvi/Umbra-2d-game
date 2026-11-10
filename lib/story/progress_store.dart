import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../chapters/campaign_catalog.dart';

/// One atomic, versioned record. Checkpoints restore authored safe states.
class ProgressStore {
  ProgressStore.memory([this._reached = 0])
    : _prefs = null,
      _current = _reached,
      weaponTiers = {},
      equippedWeapons = [null, null, null],
      activeWeaponSlot = 0,
      weaponPickups = {};
  ProgressStore._(
    this._prefs,
    this._reached,
    this._current,
    this.checkpoint, {
    required this.weaponTiers,
    required this.equippedWeapons,
    required this.activeWeaponSlot,
    required this.weaponPickups,
  });
  final SharedPreferences? _prefs;
  static const key = 'umbra.campaign.v3';
  static const backupKey = 'umbra.campaign.v3.backup';
  static const _legacyKey = 'umbra.campaign.v2';
  static const _legacyBackupKey = 'umbra.campaign.v2.backup';
  bool saveFailed = false;
  int _reached, _current;
  String? checkpoint;
  Map<String, int> weaponTiers;
  List<String?> equippedWeapons;
  int activeWeaponSlot;
  Set<int> weaponPickups;
  Future<void> _pending = Future.value();
  int get reached => _reached;
  int get current => _current;
  bool get canContinue => _current > 0 || checkpoint != null;

  static Future<ProgressStore> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final recordKey in [key, backupKey, _legacyKey, _legacyBackupKey]) {
        final raw = prefs.getString(recordKey);
        if (raw != null) {
          try {
            final data = jsonDecode(raw) as Map<String, dynamic>;
            final reached = CampaignCatalog.indexOf(data['furthest'] as String);
            final current = CampaignCatalog.indexOf(data['chapter'] as String);
            final version = data['version'];
            if ((version == 2 || version == 3) &&
                reached >= 0 &&
                current >= 0 &&
                current <= reached) {
              final migratedTiers = <String, int>{};
              final migratedPickups = <int>{};
              if (version == 2) {
                for (var chapter = 0; chapter <= reached; chapter++) {
                  const families = [
                    'katana',
                    'shuriken',
                    'kunai',
                    'bow',
                    'smokeBomb',
                    'kusarigama',
                    'spear',
                    'bombs',
                    'twinDaggers',
                    'claws',
                  ];
                  migratedTiers[families[chapter % 10]] = chapter ~/ 10 + 1;
                  migratedPickups.add(chapter);
                }
              }
              final tiersRaw = data['weapons'];
              final slotsRaw = data['equipped'];
              final pickupsRaw = data['pickups'];
              final store = ProgressStore._(
                prefs,
                reached,
                current,
                data['checkpoint'] as String?,
                weaponTiers: version == 3 && tiersRaw is Map
                    ? {
                        for (final entry in tiersRaw.entries)
                          if (entry.key is String && entry.value is num)
                            entry.key as String: (entry.value as num)
                                .toInt()
                                .clamp(1, 4),
                      }
                    : migratedTiers,
                equippedWeapons: version == 3 && slotsRaw is List
                    ? [
                        for (var i = 0; i < 3; i++)
                          i < slotsRaw.length && slotsRaw[i] is String
                              ? slotsRaw[i] as String
                              : null,
                      ]
                    : [
                        ...migratedTiers.keys.take(3),
                        ...List<String?>.filled(
                          (3 - migratedTiers.length).clamp(0, 3),
                          null,
                        ),
                      ],
                activeWeaponSlot:
                    (data['activeWeaponSlot'] as num?)?.toInt().clamp(0, 2) ??
                    0,
                weaponPickups: version == 3 && pickupsRaw is List
                    ? {
                        for (final value in pickupsRaw)
                          if (value is num && value >= 0 && value < 40)
                            value.toInt(),
                      }
                    : migratedPickups,
              );
              if (version == 2) await store._save();
              return store;
            }
          } catch (_) {
            /* Recover using the untouched legacy record. */
          }
        }
      }
      final old = prefs.getInt('umbra.reachedChapter') ?? 0;
      final migrated = CampaignCatalog.migrateIndex(old);
      final store = ProgressStore._(
        prefs,
        migrated,
        migrated,
        null,
        weaponTiers: {},
        equippedWeapons: [null, null, null],
        activeWeaponSlot: 0,
        weaponPickups: {},
      );
      await store._save();
      return store;
    } catch (_) {
      return ProgressStore.memory();
    }
  }

  Future<void> _save() {
    final value = jsonEncode({
      'version': 3,
      'furthest': CampaignCatalog.ids[_reached],
      'chapter': CampaignCatalog.ids[_current],
      'checkpoint': checkpoint,
      'weapons': weaponTiers,
      'equipped': equippedWeapons,
      'activeWeaponSlot': activeWeaponSlot,
      'pickups': weaponPickups.toList()..sort(),
    });
    _pending = _pending.then((_) async {
      if (_prefs == null) return;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          if (!await _prefs.setString(key, value)) {
            throw StateError('Progress write failed');
          }
          saveFailed = false;
          await _prefs.setString(backupKey, value);
          return;
        } catch (_) {
          saveFailed = true;
          if (attempt < 2) {
            await Future<void>.delayed(
              Duration(milliseconds: 100 * (attempt + 1)),
            );
          }
        }
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

  Future<void> saveWeaponState({
    required Map<String, int> tiers,
    required List<String?> equipped,
    required int activeSlot,
    int? collectedChapter,
  }) {
    weaponTiers = {
      for (final entry in tiers.entries) entry.key: entry.value.clamp(1, 4),
    };
    equippedWeapons = [
      for (var i = 0; i < 3; i++) i < equipped.length ? equipped[i] : null,
    ];
    activeWeaponSlot = activeSlot.clamp(0, 2);
    if (collectedChapter != null) weaponPickups.add(collectedChapter);
    return _save();
  }
}
