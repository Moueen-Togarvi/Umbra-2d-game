import 'package:flame/components.dart';

/// One cut or one star. [direction] is the way it was travelling (−1 or 1).
class CombatHit {
  const CombatHit({required this.direction});

  final double direction;
}

abstract interface class CombatTarget {
  Vector2 get combatPosition;
  bool get canReceiveCombatHit;

  /// Whether a hit now ends it (a story chaser only staggers).
  bool get killedByHit;
  void receiveCombatHit(CombatHit hit);
}

/// A target that warns before it strikes: the boy's prompts read it.
abstract interface class CombatTelegraph {
  bool get isTelegraphing;
}
