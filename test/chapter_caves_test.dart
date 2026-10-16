import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/caves.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/config/game_config.dart';

import 'support/campaign.dart';

void main() {
  testWidgets('he cannot swim: in deep water he drowns', (tester) async {
    final game = await bootCampaign(tester);
    final caves = await enterChapter<CavesChapter>(tester, game, 3);
    caves.player.teleportTo(Vector2(25.5, 7.6));
    for (var i = 0; i < 60 * 4 && !caves.player.isDead; i++) {
      game.update(1 / 60);
    }
    expect(caves.player.isDead, isTrue);
  });

  testWidgets('he wades the ford slowly but safely', (tester) async {
    final game = await bootCampaign(tester);
    final caves = await enterChapter<CavesChapter>(tester, game, 3);
    final p = caves.player;
    p.teleportTo(Vector2(56, caves.groundAt(56) - 0.65));
    for (var i = 0; i < 30; i++) {
      game.update(1 / 60);
    }
    double fastest = 0;
    for (var i = 0; i < 90; i++) {
      game.intent.setKeyboardState(axis: 1);
      game.update(1 / 60);
      if (p.body.position.x < 59 && p.velocity.x > fastest) {
        fastest = p.velocity.x;
      }
    }
    game.intent.setKeyboardState(axis: 0);
    expect(p.isDead, isFalse);
    expect(fastest, lessThan(GameConfig.moveSpeedMetersPerSecond * 0.8));
    expect(fastest, greaterThan(0.8));
  });

  testWidgets('chapter four: across the pool on the crate, down the river '
      'on a log, up the cistern on the rising water', (tester) async {
    final game = await bootCampaign(tester);
    final caves = await enterChapter<CavesChapter>(tester, game, 3);
    final player = caves.player;
    final intent = game.intent;
    final jumped = <String>{};
    var floated = false, rode = false, rose = false;
    double reached = 0;
    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    for (var i = 0; i < 60 * 240 && !caves.isComplete; i++) {
      final double x = player.body.position.x;
      final double feet = player.body.position.y + GameConfig.playerHeight / 2;
      final bool grounded = player.isOnGround;
      double axis = 1;
      if (!intent.isScripted) {
        // The pool: push the crate in, wait for it, ride it over.
        final crate = caves.crate.body.position;
        if (x > 20.9 && x < 22.6 && crate.y < 7.2 && crate.x < 23.2) {
          axis = 1;
        } else if (x > 20.9 && x < 22.6 && !jumped.contains('crate')) {
          // To the lip; then, once the crate has settled close by, on.
          axis = x < 22.2 ? 0.5 : 0;
          final double gap = crate.x - x;
          final bool settled =
              caves.crate.body.angle.abs() < 0.08 &&
              caves.crate.body.linearVelocity.y.abs() < 0.3;
          if (grounded && x > 22.1 && settled && gap > 1.6 && gap < 2.2) {
            axis = 1;
            jump('crate');
          }
        }
        if (jumped.contains('crate') &&
            !jumped.contains('bank') &&
            !grounded &&
            x < 28.6) {
          // Aim for the middle of it.
          axis = (caves.crate.body.position.x - x).clamp(-1.0, 1.0);
        }
        final bool onCrate =
            grounded &&
            (x - caves.crate.body.position.x).abs() < 1.55 &&
            feet < caves.crate.body.position.y &&
            x > 22.6;
        if (onCrate && x < 28.6 && !jumped.contains('bank')) {
          floated = true;
          // Keep to the middle of it, or his weight tips it over.
          final double off = crate.x - x;
          axis = off.abs() > 0.2 ? off.sign * 0.6 : 0;
          if (crate.x + 1.5 > 27.6 && !jumped.contains('bank')) {
            axis = 1;
            jump('bank');
          }
        }
        // The river: wait for a log under the bank, ride it, leap off.
        if (x > 69.3 && x < 70.1 && !jumped.contains('log')) {
          axis = 0;
          // A log far enough out that he lands on its middle.
          final under = caves.logs.afloat.where(
            (l) => l.body.position.x > 71.7 && l.body.position.x < 72.7,
          );
          if (grounded && under.isNotEmpty) {
            axis = 1;
            jump('log');
          }
        }
        if (x > 70.4 && x < 92 && grounded && feet > 6.7) {
          rode = true;
          // Keep to the middle of the log he is on.
          final logs = caves.logs.afloat.toList()
            ..sort(
              (a, b) => (a.body.position.x - x).abs().compareTo(
                (b.body.position.x - x).abs(),
              ),
            );
          final double mid = logs.isEmpty ? x : logs.first.body.position.x;
          // Near the end, stand towards its front; otherwise its middle.
          final double spot = mid > 87.5 ? mid + 1.0 : mid;
          final double off = spot - x;
          axis = off.abs() > 0.2 ? off.sign * 0.6 : 0;
          // Close to the wall: leap for the bank.
          if (x > 90.5 && !jumped.contains('leap')) {
            axis = 1;
            jump('leap');
          }
        }
        if (x > 70.4 && x < 92 && !grounded) axis = 1;
        if (player.interactions.mode == InteractionMode.hanging) axis = 1;
        // The cistern: down, onto the crank, onto the crate, and up.
        if (x > 119.5 &&
            x < 120.2 &&
            grounded &&
            feet > 9 &&
            !jumped.contains('crank')) {
          jump('crank');
        }
        if (x > 122.0 &&
            x < 122.9 &&
            grounded &&
            feet > 8.8 &&
            caves.crank.pressed &&
            !jumped.contains('lift')) {
          jump('lift');
        }
        // After the crank, a slow approach to the crate.
        if (caves.crank.pressed &&
            !jumped.contains('lift') &&
            x > 120.5 &&
            x < 123) {
          axis = 0.45;
        }
        // Onto the crate without running off its far end.
        if (jumped.contains('lift') &&
            !jumped.contains('out') &&
            !grounded &&
            x > 122 &&
            x < 126) {
          axis = 0;
        }
        final bool onLift =
            grounded &&
            (x - caves.lift.body.position.x).abs() < 1.15 &&
            feet < caves.lift.body.position.y;
        if (onLift &&
            caves.crank.pressed &&
            caves.cistern.isSettled &&
            caves.cistern.level < 6) {
          // At the top: once it lies against the wall, hop off onto the
          // way out.
          axis = 0;
          if (caves.lift.body.position.x + 1.1 > 125.6 &&
              !jumped.contains('out')) {
            axis = 1;
            jump('out');
          }
        } else if (onLift && caves.cistern.level > 6) {
          final double off = caves.lift.body.position.x - x;
          axis = off.abs() > 0.2 ? off.sign * 0.6 : 0;
        }
        if (onLift && !caves.cistern.isSettled) {
          final double off = caves.lift.body.position.x - x;
          axis = off.abs() > 0.2 ? off.sign * 0.6 : 0;
          if (feet < 6) rose = true;
        }
        if (grounded && x > 159.6 && x < 160.2 && !jumped.contains('log2')) {
          jump('log2');
        }
      }
      intent.setKeyboardState(axis: axis);
      game.update(1 / 60);
      if (player.isDead) {
        fail(
          'died at x=${x.toStringAsFixed(2)} feet=${feet.toStringAsFixed(2)} '
          'after $jumped (crate ${caves.crate.body.position}, logs '
          '${caves.logs.afloat.map((l) => l.body.position.x.toStringAsFixed(1))})',
        );
      }
      if (x > reached) reached = x;
    }
    intent.setKeyboardState(axis: 0);
    expect(
      caves.isComplete,
      isTrue,
      reason:
          'stopped at x=${player.body.position.x.toStringAsFixed(2)} '
          'y=${player.body.position.y.toStringAsFixed(2)} '
          '(furthest ${reached.toStringAsFixed(1)}) after $jumped; '
          'cistern ${caves.cistern.level.toStringAsFixed(2)} lift ${caves.lift.body.position} '
          'a ${caves.lift.body.angle.toStringAsFixed(2)} grounded ${player.isOnGround}; logs released '
          '${caves.logs.released}, now at '
          '${caves.logs.afloat.map((l) => '${l.body.position.x.toStringAsFixed(1)},${l.body.position.y.toStringAsFixed(1)}')}',
    );
    expect(floated, isTrue, reason: 'the pool is crossed on the crate');
    expect(rode, isTrue, reason: 'the river is ridden on a log');
    expect(rose, isTrue, reason: 'the water lifts him out of the cistern');
  });

  testWidgets('a raft carries his weight and stays level under him', (
    tester,
  ) async {
    final game = await bootCampaign(tester);
    final caves = await enterChapter<CavesChapter>(tester, game, 3);
    // Float the crate in the middle of the pool, then stand him on it.
    caves.crate.body
      ..setTransform(Vector2(25.5, 7.3), caves.crate.body.rotation)
      ..linearVelocity = Vector2.zero();
    for (var i = 0; i < 240; i++) {
      game.update(1 / 60);
    }
    final double empty = caves.crate.body.position.y;
    caves.player.teleportTo(
      Vector2(caves.crate.body.position.x, empty - 0.425 - 0.66),
    );
    for (var i = 0; i < 360; i++) {
      game.update(1 / 60);
    }
    final double loaded = caves.crate.body.position.y;
    final double level = caves.pool.level;
    final double sub = (loaded + 0.45 - level).clamp(0, 0.9) * 3.0;
    final double carried = sub * caves.pool.density - 36;
    expect(caves.player.isDead, isFalse);
    expect(caves.player.isOnGround, isTrue);
    expect(loaded, greaterThan(empty + 0.1), reason: 'it rides lower');
    expect(carried, closeTo(GameConfig.playerMassKilograms, 8));
    expect(caves.crate.body.angle.abs(), lessThan(0.12));
  });
}
