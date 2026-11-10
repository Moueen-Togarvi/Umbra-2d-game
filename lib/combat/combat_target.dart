import 'package:flame/components.dart';

class CombatHit {
  const CombatHit({
    required this.posture,
    required this.direction,
    required this.stunSeconds,
    this.finisher = false,
  });

  final double posture, direction, stunSeconds;
  final bool finisher;
}

abstract interface class CombatTarget {
  Vector2 get combatPosition;
  bool get canReceiveCombatHit;
  bool get isCombatStunned;
  void receiveCombatHit(CombatHit hit);
}

abstract interface class CombatTelegraph {
  bool get isTelegraphing;
}
