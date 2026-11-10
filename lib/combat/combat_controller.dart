import 'dart:math' as math;

import '../entities/player.dart';
import '../input/player_intent.dart';
import '../world/stage.dart';
import 'combat_target.dart';
import 'weapons.dart';

class CombatController {
  CombatController({required this.inventory, required this.intent, this.onCue});

  final WeaponInventory inventory;
  final PlayerIntent intent;
  final void Function(String cue, double strength)? onCue;

  AttackPhase phase = AttackPhase.ready;
  double _phaseTime = 0;
  bool _hitApplied = false;
  WeaponDefinition? _attack;

  double get readiness {
    final weapon = _attack;
    if (phase == AttackPhase.ready || weapon == null) return 1;
    if (phase != AttackPhase.recovery) return 0;
    return (_phaseTime / weapon.recovery).clamp(0.0, 1.0);
  }

  void reset({bool refill = true}) {
    phase = AttackPhase.ready;
    _phaseTime = 0;
    _hitApplied = false;
    _attack = null;
    if (refill) inventory.refill();
  }

  void update(double dt, Player player, Stage? stage) {
    final slot = intent.consumeWeaponSlotRequest();
    if (slot != null) inventory.select(slot);
    if (intent.consumeCycleWeaponRequest()) inventory.cycle();

    if (phase == AttackPhase.ready && intent.consumeAttackRequest()) {
      _begin(player);
    }
    if (phase == AttackPhase.ready || _attack == null) {
      player.setCombatAttack(null, 0);
      return;
    }
    if (player.isDead || player.isRagdoll || intent.isScripted) {
      reset(refill: false);
      player.setCombatAttack(null, 0);
      return;
    }

    _phaseTime += dt;
    final weapon = _attack!;
    final duration = switch (phase) {
      AttackPhase.windup => weapon.windup,
      AttackPhase.active => weapon.active,
      AttackPhase.recovery => weapon.recovery,
      AttackPhase.ready => 1.0,
    };
    player.setCombatAttack(
      weapon.family,
      (phase.index + (_phaseTime / duration).clamp(0.0, 1.0)) / 3,
    );

    if (phase == AttackPhase.active && !_hitApplied && stage != null) {
      _hitApplied = true;
      _applyHit(player, stage, weapon);
    }
    if (_phaseTime < duration) return;
    _phaseTime = 0;
    switch (phase) {
      case AttackPhase.windup:
        phase = AttackPhase.active;
      case AttackPhase.active:
        phase = AttackPhase.recovery;
      case AttackPhase.recovery:
        phase = AttackPhase.ready;
        _attack = null;
        player.setCombatAttack(null, 0);
      case AttackPhase.ready:
        break;
    }
  }

  void _begin(Player player) {
    final weapon = inventory.active;
    if (weapon == null || player.isDead || player.isRagdoll) return;
    if (!inventory.spend()) {
      onCue?.call('empty', .2);
      return;
    }
    _attack = weapon;
    phase = AttackPhase.windup;
    _phaseTime = 0;
    _hitApplied = false;
    onCue?.call(weapon.isRanged ? 'throw' : 'slash', .25);
  }

  void _applyHit(Player player, Stage stage, WeaponDefinition weapon) {
    if (weapon.family == WeaponFamily.smokeBomb) {
      stage.combatConcealment = 2.6 + weapon.tier * .55;
      onCue?.call('smoke', .3);
    }
    final origin = player.body.position;
    final candidates =
        stage.descendants().whereType<CombatTarget>().where((target) {
          if (!target.canReceiveCombatHit) return false;
          final delta = target.combatPosition - origin;
          if (delta.y.abs() > 2.2) return false;
          if (weapon.isArea) return delta.length <= weapon.range;
          return delta.x * player.facing > -.15 && delta.length <= weapon.range;
        }).toList()..sort(
          (a, b) => (a.combatPosition - origin).length2.compareTo(
            (b.combatPosition - origin).length2,
          ),
        );
    if (candidates.isEmpty) return;

    final count = weapon.isArea ? math.min(4, candidates.length) : 1;
    for (final target in candidates.take(count)) {
      final telegraph = target is CombatTelegraph
          ? target as CombatTelegraph
          : null;
      final parry =
          weapon.family == WeaponFamily.katana &&
          (telegraph?.isTelegraphing ?? false);
      target.receiveCombatHit(
        CombatHit(
          posture:
              weapon.posture *
              (parry ? 1.8 : 1) *
              (weapon.family == WeaponFamily.claws && !player.isOnGround
                  ? 1.35
                  : 1),
          direction: weapon.family == WeaponFamily.kusarigama
              ? -player.facing
              : player.facing,
          stunSeconds: (0.55 + weapon.tier * .18) * (parry ? 1.7 : 1),
        ),
      );
      if (parry) onCue?.call('parry', .65);
    }
  }
}
