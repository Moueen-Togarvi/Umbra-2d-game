import '../story/progress_store.dart';

enum WeaponFamily {
  katana,
  shuriken,
  kunai,
  bow,
  smokeBomb,
  kusarigama,
  spear,
  bombs,
  twinDaggers,
  claws,
}

enum AttackPhase { ready, windup, active, recovery }

class WeaponDefinition {
  const WeaponDefinition({
    required this.family,
    required this.tier,
    required this.name,
    required this.description,
    required this.range,
    required this.windup,
    required this.active,
    required this.recovery,
    required this.posture,
    required this.maxAmmo,
  });

  final WeaponFamily family;
  final int tier;
  final String name, description;
  final double range, windup, active, recovery, posture;
  final int maxAmmo;

  bool get usesAmmo => maxAmmo > 0;
  bool get isArea =>
      family == WeaponFamily.smokeBomb || family == WeaponFamily.bombs;
  bool get isRanged => switch (family) {
    WeaponFamily.shuriken ||
    WeaponFamily.kunai ||
    WeaponFamily.bow ||
    WeaponFamily.smokeBomb ||
    WeaponFamily.kusarigama ||
    WeaponFamily.bombs => true,
    _ => false,
  };
}

abstract final class WeaponCatalog {
  static const _names = <WeaponFamily, List<String>>{
    WeaponFamily.katana: [
      'Broken Katana',
      'Tempered Katana',
      'Shadow Katana',
      'Dawn Katana',
    ],
    WeaponFamily.shuriken: [
      'Rusted Shuriken',
      'Weighted Shuriken',
      'Wind Shuriken',
      'Eclipse Shuriken',
    ],
    WeaponFamily.kunai: [
      'Bone Kunai',
      'Steel Kunai',
      'Venom Kunai',
      'Phantom Kunai',
    ],
    WeaponFamily.bow: ['Hunter Bow', 'Recurve Bow', 'Silent Bow', 'Moon Bow'],
    WeaponFamily.smokeBomb: [
      'Ash Smoke',
      'Dense Smoke',
      'Blind Smoke',
      'Shadow Smoke',
    ],
    WeaponFamily.kusarigama: [
      'Rope Sickle',
      'Iron Chain',
      'Hooked Chain',
      'Wraith Chain',
    ],
    WeaponFamily.spear: [
      'Bamboo Spear',
      'Iron Spear',
      'Piercing Spear',
      'Storm Spear',
    ],
    WeaponFamily.bombs: [
      'Clay Bomb',
      'Flash Bomb',
      'Fire Bomb',
      'Thunder Bomb',
    ],
    WeaponFamily.twinDaggers: [
      'Twin Shards',
      'Twin Blades',
      'Shadow Twins',
      'Dawn Twins',
    ],
    WeaponFamily.claws: [
      'Hand Claws',
      'Iron Claws',
      'Silent Claws',
      'Night Claws',
    ],
  };

  static const _descriptions = <WeaponFamily, String>{
    WeaponFamily.katana: 'Balanced close strike and timed parry.',
    WeaponFamily.shuriken: 'A fast ranged interrupt.',
    WeaponFamily.kunai: 'Throw from range or stun from shadow.',
    WeaponFamily.bow: 'A patient, precise charged shot.',
    WeaponFamily.smokeBomb: 'Break sight and escape unseen.',
    WeaponFamily.kusarigama: 'Pull a hunter off balance.',
    WeaponFamily.spear: 'Long reach with heavy posture damage.',
    WeaponFamily.bombs: 'A loud area stun for a planned escape.',
    WeaponFamily.twinDaggers: 'Two quick strikes at dangerous range.',
    WeaponFamily.claws: 'A fast aerial and close-range flurry.',
  };

  static WeaponDefinition forChapter(int chapterIndex) {
    final family =
        WeaponFamily.values[chapterIndex % WeaponFamily.values.length];
    return definition(family, chapterIndex ~/ 10 + 1);
  }

  static WeaponDefinition definition(WeaponFamily family, int tier) {
    final t = tier.clamp(1, 4);
    final base = switch (family) {
      WeaponFamily.katana => (1.55, .13, .12, .32, 1.0, 0),
      WeaponFamily.shuriken => (7.0, .09, .06, .28, .62, 3),
      WeaponFamily.kunai => (6.0, .11, .06, .30, .78, 3),
      WeaponFamily.bow => (10.0, .34, .08, .42, 1.15, 3),
      WeaponFamily.smokeBomb => (3.5, .18, .10, .48, 1.35, 2),
      WeaponFamily.kusarigama => (4.2, .24, .12, .48, 1.45, 2),
      WeaponFamily.spear => (2.5, .22, .14, .46, 1.55, 0),
      WeaponFamily.bombs => (5.0, .28, .10, .55, 1.8, 2),
      WeaponFamily.twinDaggers => (1.15, .08, .15, .28, 1.1, 0),
      WeaponFamily.claws => (1.05, .07, .17, .26, 1.2, 0),
    };
    final ammo = base.$6 == 0 ? 0 : base.$6 + (t >= 2 ? 1 : 0);
    return WeaponDefinition(
      family: family,
      tier: t,
      name: _names[family]![t - 1],
      description: _descriptions[family]!,
      range: base.$1 + (t - 1) * .12,
      windup: base.$2,
      active: base.$3,
      recovery: (base.$4 - (t - 1) * .025).clamp(.2, 1),
      posture: base.$5 + (t - 1) * .18,
      maxAmmo: ammo,
    );
  }

  static String familyLabel(WeaponFamily family) => switch (family) {
    WeaponFamily.smokeBomb => 'Smoke Bomb',
    WeaponFamily.twinDaggers => 'Twin Daggers',
    _ => '${family.name[0].toUpperCase()}${family.name.substring(1)}',
  };
}

class WeaponInventory {
  WeaponInventory({
    Map<WeaponFamily, int>? tiers,
    List<WeaponFamily?>? equipped,
    this.activeSlot = 0,
  }) : tiers = {...?tiers},
       equipped = List<WeaponFamily?>.of(equipped ?? const [null, null, null]) {
    while (this.equipped.length < 3) {
      this.equipped.add(null);
    }
    if (this.equipped.length > 3) {
      this.equipped.removeRange(3, this.equipped.length);
    }
    activeSlot = activeSlot.clamp(0, 2);
    refill();
  }

  factory WeaponInventory.fromProgress(ProgressStore progress) {
    WeaponFamily? parse(String? value) {
      if (value == null) return null;
      return WeaponFamily.values.where((f) => f.name == value).firstOrNull;
    }

    return WeaponInventory(
      tiers: {
        for (final entry in progress.weaponTiers.entries)
          ?parse(entry.key): entry.value.clamp(1, 4),
      },
      equipped: [for (final value in progress.equippedWeapons) parse(value)],
      activeSlot: progress.activeWeaponSlot,
    );
  }

  final Map<WeaponFamily, int> tiers;
  final List<WeaponFamily?> equipped;
  final Map<WeaponFamily, int> ammo = {};
  int activeSlot;

  WeaponFamily? get activeFamily => equipped[activeSlot];
  WeaponDefinition? get active => activeFamily == null
      ? null
      : WeaponCatalog.definition(activeFamily!, tiers[activeFamily!] ?? 1);

  bool get hasAny => tiers.isNotEmpty;
  int ammoFor(WeaponFamily family) => ammo[family] ?? 0;

  void unlock(WeaponDefinition weapon, {int? replaceSlot}) {
    final previous = tiers[weapon.family] ?? 0;
    tiers[weapon.family] = weapon.tier > previous ? weapon.tier : previous;
    final existing = equipped.indexOf(weapon.family);
    if (existing >= 0) {
      activeSlot = existing;
    } else {
      final empty = equipped.indexOf(null);
      final slot = empty >= 0 ? empty : replaceSlot;
      if (slot != null && slot >= 0 && slot < 3) {
        equipped[slot] = weapon.family;
        activeSlot = slot;
      }
    }
    final resolved = WeaponCatalog.definition(
      weapon.family,
      tiers[weapon.family]!,
    );
    if (resolved.usesAmmo) ammo[weapon.family] = resolved.maxAmmo;
  }

  void equip(WeaponFamily family, int slot) {
    if (!tiers.containsKey(family) || slot < 0 || slot > 2) return;
    final old = equipped.indexOf(family);
    if (old >= 0) equipped[old] = equipped[slot];
    equipped[slot] = family;
    activeSlot = slot;
  }

  void select(int slot) {
    if (slot >= 0 && slot < 3 && equipped[slot] != null) activeSlot = slot;
  }

  void cycle() {
    for (var step = 1; step <= 3; step++) {
      final slot = (activeSlot + step) % 3;
      if (equipped[slot] != null) {
        activeSlot = slot;
        return;
      }
    }
  }

  bool spend() {
    final weapon = active;
    if (weapon == null || !weapon.usesAmmo) return weapon != null;
    final left = ammoFor(weapon.family);
    if (left <= 0) return false;
    ammo[weapon.family] = left - 1;
    return true;
  }

  void refill() {
    for (final entry in tiers.entries) {
      final weapon = WeaponCatalog.definition(entry.key, entry.value);
      if (weapon.usesAmmo) ammo[entry.key] = weapon.maxAmmo;
    }
  }

  Future<void> save(ProgressStore progress, {int? collectedChapter}) =>
      progress.saveWeaponState(
        tiers: {for (final entry in tiers.entries) entry.key.name: entry.value},
        equipped: [for (final family in equipped) family?.name],
        activeSlot: activeSlot,
        collectedChapter: collectedChapter,
      );
}
