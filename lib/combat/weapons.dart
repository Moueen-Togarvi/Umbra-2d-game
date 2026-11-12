import '../story/progress_store.dart';

/// The two attacks. A slash cuts whatever stands within reach in front of
/// him; a throw sends a spinning star that flies until it strikes.
enum AttackKind { slash, throwStar }

enum AttackPhase { ready, windup, active, recovery }

/// What the boy carries: a short sword and a pouch of throwing stars.
///
/// Nothing else: no tiers, slots or loadouts. Chapter 1 hands him each in
/// turn; every later chapter starts with both.
class CombatKit {
  CombatKit({this.hasSword = false, this.hasShuriken = false}) {
    refill();
  }

  /// Old saves recorded weapon tiers and chapter pickups. Any record of
  /// either means the boy got past the Chapter 1 lessons.
  factory CombatKit.fromProgress(ProgressStore progress) {
    final tiers = progress.weaponTiers.keys.toSet();
    final legacy =
        progress.weaponPickups.isNotEmpty ||
        tiers.any((name) => name != swordKey && name != shurikenKey);
    return CombatKit(
      hasSword: legacy || tiers.contains(swordKey),
      hasShuriken: legacy || tiers.contains(shurikenKey),
    );
  }

  static const swordKey = 'sword', shurikenKey = 'shuriken';
  static const int maxStars = 3;

  bool hasSword, hasShuriken;
  int stars = 0;

  bool get hasAny => hasSword || hasShuriken;

  void refill() => stars = hasShuriken ? maxStars : 0;

  bool spendStar() {
    if (!hasShuriken || stars <= 0) return false;
    stars--;
    return true;
  }

  Future<void> save(ProgressStore progress) => progress.saveWeaponState(
    tiers: {
      if (hasSword) swordKey: 1,
      if (hasShuriken) shurikenKey: 1,
    },
    equipped: const [null, null, null],
    activeSlot: 0,
    clearPickups: true,
  );
}

/// The timing of each attack, in seconds, and how far it reaches.
abstract final class AttackTiming {
  static double windup(AttackKind kind) =>
      kind == AttackKind.slash ? .08 : .10;
  static double active(AttackKind kind) =>
      kind == AttackKind.slash ? .10 : .05;
  static double recovery(AttackKind kind) =>
      kind == AttackKind.slash ? .22 : .25;

  /// How far a slash cuts, from the middle of his body.
  static const double slashReach = 1.5;

  /// How fast a thrown star flies, metres a second, and how far.
  static const double starSpeed = 14;
  static const double starRange = 14;
}
