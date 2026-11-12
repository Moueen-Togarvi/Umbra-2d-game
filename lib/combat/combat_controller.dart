import 'dart:math' as math;

import 'package:flame/components.dart';

import '../entities/player.dart';
import '../input/player_intent.dart';
import '../world/stage.dart';
import 'combat_target.dart';
import 'projectile.dart';
import 'weapons.dart';

/// Turns the slash and throw buttons into attacks: a short wind-up, the
/// moment that strikes, then a recovery before the next.
class CombatController {
  CombatController({
    required this.kit,
    required this.intent,
    this.onCue,
    this.onKill,
  });

  final CombatKit kit;
  final PlayerIntent intent;

  /// A sound and how strongly it is felt (0–1).
  final void Function(String cue, double strength)? onCue;

  /// Something died to a blow: the game holds the frame for a moment.
  final void Function(Vector2 at)? onKill;

  AttackPhase phase = AttackPhase.ready;
  AttackKind? kind;
  double _phaseTime = 0;
  bool _struck = false;

  /// The slash's arc on screen, radians: from up and behind him, over and
  /// down to in front of his knees.
  static const double arcFrom = -2.3, arcTo = .75;

  /// 0 while an attack runs, rising to 1 as it recovers.
  double get readiness {
    final current = kind;
    if (phase == AttackPhase.ready || current == null) return 1;
    if (phase != AttackPhase.recovery) return 0;
    return (_phaseTime / AttackTiming.recovery(current)).clamp(0.0, 1.0);
  }

  void reset({bool refill = true}) {
    phase = AttackPhase.ready;
    kind = null;
    _phaseTime = 0;
    _struck = false;
    if (refill) kit.refill();
  }

  void update(double dt, Player player, Stage? stage) {
    final wantsSlash = intent.consumeAttackRequest();
    final wantsThrow = intent.consumeThrowRequest();
    if (phase == AttackPhase.ready) {
      if (wantsSlash && kit.hasSword) {
        _begin(player, AttackKind.slash);
      } else if (wantsThrow && kit.hasShuriken) {
        if (kit.spendStar()) {
          _begin(player, AttackKind.throwStar);
        } else {
          onCue?.call('empty', .2);
        }
      }
    }
    final current = kind;
    if (phase == AttackPhase.ready || current == null) {
      player.setCombatAttack(null, 0);
      return;
    }
    if (player.isDead || player.isRagdoll || intent.isScripted) {
      reset(refill: false);
      player.setCombatAttack(null, 0);
      return;
    }

    _phaseTime += dt;
    final duration = switch (phase) {
      AttackPhase.windup => AttackTiming.windup(current),
      AttackPhase.active => AttackTiming.active(current),
      AttackPhase.recovery => AttackTiming.recovery(current),
      AttackPhase.ready => 1.0,
    };
    player.setCombatAttack(
      current,
      (phase.index - 1 + (_phaseTime / duration).clamp(0.0, 1.0)) / 3,
    );

    if (phase == AttackPhase.active && !_struck && stage != null) {
      _struck = true;
      current == AttackKind.slash
          ? _slash(player, stage)
          : _throw(player, stage);
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
        kind = null;
        player.setCombatAttack(null, 0);
      case AttackPhase.ready:
        break;
    }
  }

  void _begin(Player player, AttackKind next) {
    if (player.isDead || player.isRagdoll) return;
    kind = next;
    phase = AttackPhase.windup;
    _phaseTime = 0;
    _struck = false;
    onCue?.call(next == AttackKind.slash ? 'slash' : 'throw', .25);
  }

  /// Where the arm swings from, in world metres.
  static Vector2 shoulderOf(Player player) =>
      player.body.position + Vector2(player.facing * .04, -.32);

  void _slash(Player player, Stage stage) {
    final facing = player.facing;
    final shoulder = shoulderOf(player);
    stage.combatFx?.slash(shoulder, facing, .92, arcFrom, arcTo);
    // A half step into the cut.
    player.body.linearVelocity += Vector2(facing * .9, 0);

    final origin = player.body.position;
    final hits = stage.descendants().whereType<CombatTarget>().where((target) {
      if (!target.canReceiveCombatHit) return false;
      final delta = target.combatPosition - origin;
      if (delta.y.abs() > 1.6) return false;
      return delta.x * facing > -.25 &&
          delta.length <= AttackTiming.slashReach;
    }).toList();
    for (final target in hits) {
      _strike(target, facing, stage);
    }
  }

  void _throw(Player player, Stage stage) {
    final facing = player.facing;
    final hand = shoulderOf(player) + Vector2(facing * .35, -.05);
    stage.add(
      Shuriken(
        from: hand,
        direction: facing,
        world: player.body.world,
        stage: stage,
        onHit: (target, killed) => _landed(target, facing, killed),
      ),
    );
  }

  void _strike(CombatTarget target, double facing, Stage stage) {
    final killed = target.killedByHit;
    target.receiveCombatHit(CombatHit(direction: facing));
    stage.combatFx?.sparks(target.combatPosition, facing);
    _landed(target, facing, killed);
  }

  void _landed(CombatTarget target, double facing, bool killed) {
    onCue?.call(killed ? 'kill' : 'hit', killed ? .8 : .5);
    if (killed) onKill?.call(target.combatPosition);
  }

  /// The arm's angle at [progress] (0–1 over the whole attack).
  static double swingAngle(double progress) {
    // Wind-up pulls back past the start; the strike sweeps fast; recovery
    // settles the arm down in front.
    final p = progress.clamp(0.0, 1.0);
    if (p < 1 / 3) return arcFrom - .35 * math.sin(p * 3 * math.pi / 2);
    if (p < 2 / 3) {
      final t = (p - 1 / 3) * 3;
      return (arcFrom - .35) + (arcTo + .35 - arcFrom) * (1 - (1 - t) * (1 - t));
    }
    final t = (p - 2 / 3) * 3;
    return arcTo + (.25 - arcTo) * t * t;
  }
}
