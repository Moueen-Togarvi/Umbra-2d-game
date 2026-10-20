import 'support/route_pilot.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/crypt.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/story/vampire.dart';

import 'support/campaign.dart';

void main() {
  testWidgets('a chained coffin floats, then sinks under him', (tester) async {
    final game = await bootCampaign(tester);
    final crypt = await enterChapter<CryptChapter>(tester, game, 10);
    final coffin = crypt.floating[2];
    for (var i = 0; i < 120; i++) {
      driveExtension(game);
      game.update(1 / 60);
    }
    final double afloat = coffin.body.position.y;
    // Afloat: its lid above the water.
    expect(afloat - 0.31, lessThan(crypt.hall.level));
    crypt.player.teleportTo(
      Vector2(coffin.body.position.x, afloat - 0.31 - 0.66),
    );
    // It settles under him, slowly.
    for (var i = 0; i < 60 * 3; i++) {
      driveExtension(game);
      game.update(1 / 60);
    }
    expect(coffin.body.position.y, greaterThan(afloat + 0.3));
    // Off it again (a respawn), it comes back up.
    crypt.player.teleportTo(Vector2(20, crypt.groundAt(20) - 0.65));
    for (var i = 0; i < 60 * 6; i++) {
      driveExtension(game);
      game.update(1 / 60);
    }
    expect(coffin.body.position.y, closeTo(afloat, 0.12));
  });

  testWidgets('it will not cross running water', (tester) async {
    final game = await bootCampaign(tester);
    final crypt = await enterChapter<CryptChapter>(tester, game, 10);
    // Running when the tomb opens, as he would be.
    crypt.player.teleportTo(Vector2(82.4, crypt.groundAt(82.4) - 0.65));
    for (var i = 0; i < 30; i++) {
      driveExtension(game);
      game.update(1 / 60);
    }
    // Into the stream, and stand there.
    var died = false;
    for (var i = 0; i < 60 * 11; i++) {
      died |= crypt.player.isDead;
      final double x = crypt.player.body.position.x;
      game.intent.setKeyboardState(axis: x < 98.6 ? 1 : 0);
      if (crypt.player.isOnGround && x > 87.6 && x < 88.3) {
        game.intent.requestJump();
      }
      driveExtension(game);
      game.update(1 / 60);
    }
    expect(died, isFalse, reason: 'it never reached him');
    expect(crypt.tomb.x, lessThan(CryptChapter.streamLeft));
    expect(crypt.tomb.mode, VampireMode.grab);
  });

  testWidgets('chapter five: over the sinking coffins, through the drained '
      'passage, and away from the tomb across the stream', (tester) async {
    final game = await bootCampaign(tester);
    final crypt = await enterChapter<CryptChapter>(tester, game, 10);
    final player = crypt.player;
    final intent = game.intent;
    final jumped = <String>{};
    var hopped = 0;
    var waded = false, chased = false;
    double reached = 0;
    double hopCooldown = 0;
    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    for (var i = 0; i < 60 * 900 && !crypt.isComplete; i++) {
      final double x = player.body.position.x;
      final double feet = player.body.position.y + GameConfig.playerHeight / 2;
      final bool grounded = player.isOnGround;
      double axis = 1;
      hopCooldown -= 1 / 60;
      if (!intent.isScripted) {
        // The coffins: from the lip and then from each to the next,
        // without stopping.
        if (grounded && x > 26.3 && x < 27 && !jumped.contains('hall')) {
          jump('hall');
        }
        if (grounded && x > 27 && x < 41 && feet > 6.6 && hopCooldown <= 0) {
          final coffin = crypt.floating
              .where((c) => (c.body.position.x - x).abs() < 1.05)
              .firstOrNull;
          if (coffin != null && x > coffin.body.position.x + 0.35) {
            hopped++;
            hopCooldown = 0.35;
            jump('hop');
          }
        }
        // The drain: onto the pedal; then wait for the water to go.
        if (grounded && x > 50.7 && x < 51.4 && !jumped.contains('drain')) {
          jump('drain');
        }
        if (x > 52.4 && x < 54 && crypt.passage.level < 9.3) axis = 0;
        if (x > 54 && x < 68) {
          waded |= grounded && feet > 9.3;
          // Onto the stranded coffin, then up the far wall.
          final c = crypt.aground.body.position;
          if (grounded &&
              feet > 9.4 &&
              x > c.x - 1.9 &&
              x < c.x - 1.0 &&
              !jumped.contains('step')) {
            jump('step');
          }
          if (grounded &&
              feet < 9.4 &&
              x > c.x + 0.3 &&
              !jumped.contains('wall')) {
            jump('wall');
          }
        }
        if (player.interactions.mode == InteractionMode.hanging) axis = 1;
        // The hall of tombs: run, hop the coffin, into the stream.
        if (grounded && x > 87.6 && x < 88.3 && !jumped.contains('coffin')) {
          jump('coffin');
        }
        chased |= crypt.tomb.risen && !crypt.tomb.gone;
        if (grounded &&
            x > 99.6 &&
            x < 100.6 &&
            feet > 7.1 &&
            !jumped.contains('bank')) {
          jump('bank');
        }
        if (grounded && x > 127.6 && x < 128.3 && !jumped.contains('log')) {
          jump('log');
        }
      }
      intent.setKeyboardState(axis: axis);
      driveExtension(game);
      game.update(1 / 60);
      if (player.isDead) {
        fail(
          'died at x=${x.toStringAsFixed(2)} feet=${feet.toStringAsFixed(2)} '
          'after $jumped, $hopped hops; passage '
          '${crypt.passage.level.toStringAsFixed(2)}, tomb '
          '${crypt.tomb.x.toStringAsFixed(1)}',
        );
      }
      if (x > reached) reached = x;
    }
    intent.setKeyboardState(axis: 0);
    expect(
      crypt.isComplete,
      isTrue,
      reason:
          'stopped at x=${player.body.position.x.toStringAsFixed(2)} '
          'y=${player.body.position.y.toStringAsFixed(2)} '
          '(furthest ${reached.toStringAsFixed(1)}) after $jumped; mode '
          '${player.interactions.mode.name}; passage '
          '${crypt.passage.level.toStringAsFixed(2)}',
    );
    expect(hopped, greaterThanOrEqualTo(3));
    expect(waded, isTrue, reason: 'through the drained passage');
    expect(chased, isTrue, reason: 'the tomb opened and it came after him');
  });
}
