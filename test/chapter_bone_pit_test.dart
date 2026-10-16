import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/bone_pit.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/config/game_config.dart';

import 'support/campaign.dart';

void main() {
  testWidgets('a barrel floats, dips and tips under him', (tester) async {
    final game = await bootCampaign(tester);
    final pit = await enterChapter<BonePitChapter>(tester, game, 5);
    final barrel = pit.barrels[2];
    for (var i = 0; i < 120; i++) {
      game.update(1 / 60);
    }
    final Vector2 start = barrel.body.position.clone();
    expect(start.y - 0.45, lessThan(pit.pool.level), reason: 'afloat');
    // On its end: it dips and leans that way, and he stays on.
    pit.player.teleportTo(Vector2(start.x + 0.5, start.y - 0.45 - 0.66));
    double leaned = 0;
    for (var i = 0; i < 90; i++) {
      game.update(1 / 60);
      if (barrel.body.angle.abs() > leaned) leaned = barrel.body.angle.abs();
    }
    expect(barrel.body.position.y, greaterThan(start.y + 0.04));
    expect(leaned, greaterThan(0.05));
    expect(pit.player.isDead, isFalse);
  });

  testWidgets('chapter six: over the barrels, through the drained chamber, '
      'and up the shaft ahead of the water', (tester) async {
    final game = await bootCampaign(tester);
    final pit = await enterChapter<BonePitChapter>(tester, game, 5);
    final player = pit.player;
    final intent = game.intent;
    final jumped = <String>{};
    var hops = 0;
    var climbed = 0;
    var raced = false;
    double reached = 0;
    double cooldown = 0;
    double standing = 0;
    double? target;
    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    for (var i = 0; i < 60 * 200 && !pit.isComplete; i++) {
      final double x = player.body.position.x;
      final double feet = player.body.position.y + GameConfig.playerHeight / 2;
      final bool grounded = player.isOnGround;
      final mode = player.interactions.mode;
      double axis = 1;
      cooldown -= 1 / 60;
      standing = grounded ? standing + 1 / 60 : 0;
      if (!intent.isScripted) {
        // The barrels: on and off each without stopping.
        if (grounded && x > 24.75 && x < 25 && !jumped.contains('pool')) {
          jump('pool');
        }
        if (grounded && x > 25 && x < 38.0) {
          // Balance on top of the barrel underfoot; hop when the next one
          // is in reach.
          final sorted = [...pit.barrels]
            ..sort((a, b) => a.body.position.x.compareTo(b.body.position.x));
          final under = sorted
              .where((b) => (b.body.position.x - x).abs() < 1.3)
              .firstOrNull;
          final next = sorted
              .where((b) => b.body.position.x > x + 1.3)
              .firstOrNull;
          final double ahead = next == null
              ? BonePitChapter.barrelsRight + 0.6 - x
              : next.body.position.x - x;
          final bool steady =
              under == null || under.body.linearVelocity.y.abs() < 0.25;
          // From the front of the barrel he stands on.
          final bool forward = under == null || x > under.body.position.x + 0.5;
          if (cooldown <= 0 &&
              steady &&
              forward &&
              standing > 0.2 &&
              ahead > 1.4 &&
              ahead < 2.8) {
            target = next?.body.position.x;
            hops++;
            cooldown = 0.35;
            jump('hop');
          } else if (under != null) {
            final double off = under.body.position.x + 0.6 - x;
            axis = off.abs() > 0.06 ? off.sign * 0.5 : 0;
          }
        }
        if (jumped.contains('hop') && !grounded && x > 25 && x < 38.0) {
          // Aim for the top of the barrel he is jumping to.
          axis = target == null ? 1 : ((target - x) * 1.5).clamp(-1.0, 1.0);
        }
        // The drain, then down into the chamber once it is low.
        if (grounded && x > 50.1 && x < 50.6 && !jumped.contains('drain')) {
          jump('drain');
        }
        if (x > 52.3 && x < 54 && pit.chamber.level < floorLevel - 0.5) {
          axis = 0;
        }
        // The shaft: under each ledge's edge, facing it, jump and climb.
        if (x > BonePitChapter.shaftLeft && x < BonePitChapter.shaftRight) {
          raced |= pit.shaft.level < floorLevel - 1;
          if (mode == InteractionMode.hanging ||
              mode == InteractionMode.climbing) {
            axis = player.facing;
          } else if (grounded) {
            final (double stand, double face) = feet > 9
                ? (96.1, 1.0)
                : feet > 7
                ? (97.3, -1.0)
                : feet > 5.2
                ? (96.1, 1.0)
                : (100.6, 1.0);
            final double off = stand - x;
            if (off.abs() > 0.08) {
              axis = off.sign * (off.abs() > 0.4 ? 1 : 0.4);
            } else if (player.facing != face) {
              axis = face * 0.3;
            } else if (cooldown <= 0) {
              axis = face;
              climbed++;
              cooldown = 1.0;
              jump('climb');
            } else {
              axis = 0;
            }
          } else {
            axis = player.facing;
          }
        }
        if (grounded && x > 119.6 && x < 120.2 && !jumped.contains('log')) {
          jump('log');
        }
      }
      intent.setKeyboardState(axis: axis);
      game.update(1 / 60);
      if (player.isDead) {
        fail(
          'died at x=${x.toStringAsFixed(2)} feet=${feet.toStringAsFixed(2)} '
          'after $jumped, $hops hops, $climbed climbs; chamber '
          '${pit.chamber.level.toStringAsFixed(2)} shaft '
          '${pit.shaft.level.toStringAsFixed(2)}',
        );
      }
      if (x > reached) reached = x;
    }
    intent.setKeyboardState(axis: 0);
    expect(
      pit.isComplete,
      isTrue,
      reason:
          'stopped at x=${player.body.position.x.toStringAsFixed(2)} '
          'y=${player.body.position.y.toStringAsFixed(2)} '
          '(furthest ${reached.toStringAsFixed(1)}) after $jumped; '
          '$climbed climbs; mode ${player.interactions.mode.name} grounded '
          '${player.isOnGround} state ${player.state.name} v ${player.velocity} '
          'enabled ${player.body.isEnabled} awake ${player.body.isAwake} '
          'ragdoll? ${player.cameraPosition}; barrels '
          '${pit.barrels.map((b) => '${b.body.position.x.toStringAsFixed(2)},${b.body.position.y.toStringAsFixed(2)}').join(' ')}; drain '
          '${pit.drain.pressed} chamber ${pit.chamber.level.toStringAsFixed(2)}; shaft '
          '${pit.shaft.level.toStringAsFixed(2)}',
    );
    expect(hops, greaterThanOrEqualTo(3));
    expect(raced, isTrue, reason: 'the water rose behind him');
  });
}

const double floorLevel = BonePitChapter.floor;
