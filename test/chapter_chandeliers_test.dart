import 'support/route_pilot.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/chandeliers.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/config/game_config.dart';

import 'support/campaign.dart';

void main() {
  testWidgets('chapter nine: across on the chandeliers, one dropped on the '
      'two below the gallery, and the last one behind him in the chase', (
    tester,
  ) async {
    final game = await bootCampaign(tester);
    final hall = await enterChapter<ChandeliersChapter>(tester, game, 19);
    final player = hall.player;
    final intent = game.intent;
    final jumped = <String>{};
    var swings = 0;
    double reached = 0;
    double cooldown = 0;
    double settled = 0;
    double closest = 99;
    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    // The lips he jumps for each rope from.
    const lips = [16.0, 22.0, 28.0];
    for (var i = 0; i < 60 * 900 && !hall.isComplete; i++) {
      final double x = player.body.position.x;
      final double feet = player.body.position.y + GameConfig.playerHeight / 2;
      final bool grounded = player.isOnGround;
      final mode = player.interactions.mode;
      double axis = 1;
      bool down = false;
      cooldown -= 1 / 60;
      settled = grounded && player.velocity.x.abs() < 0.3
          ? settled + 1 / 60
          : 0;
      if (!intent.isScripted) {
        // The chandeliers: from each lip, swing, let go over the next.
        for (final lip in lips) {
          if (grounded && x > lip - 0.7 && x < lip && cooldown <= 0) {
            cooldown = 1.2;
            jump('swing$lip');
          }
        }
        if (mode == InteractionMode.swinging && cooldown <= 0 && x < 33) {
          final double lip = lips.lastWhere((l) => l < x, orElse: () => 16);
          if (x > lip + 2.4 && player.velocity.x > 1.5) {
            cooldown = 0.5;
            swings++;
            jump('release');
          }
        }
        // The gallery's cord: hang on it until the chandelier is down.
        final double cordX = hall.greatCord.anchor.x;
        if (x > 40 && x < ChandeliersChapter.galleryRight && feet < 4.5) {
          if (mode == InteractionMode.swinging ||
              mode == InteractionMode.climbing) {
            axis = 0;
            down = hall.great.landed;
          } else if (!hall.greatCord.pulled) {
            final double off = cordX - x;
            if (off.abs() > 0.12) {
              axis = off.sign * (off.abs() > 0.6 ? 1 : 0.35);
            } else {
              axis = 0;
              if (grounded && cooldown <= 0) {
                cooldown = 1.0;
                jump('greatCord');
              }
            }
          } else if (!hall.great.landed) {
            axis = 0;
          }
        }
        // Up onto the fallen chandelier's crown, over the pit.
        if (grounded &&
            hall.great.wedged &&
            x > ChandeliersChapter.danceLeft - 1.0 &&
            x < ChandeliersChapter.danceLeft - 0.3 &&
            feet > 6.9 &&
            cooldown <= 0) {
          cooldown = 0.8;
          jump('ontoChandelier');
        }
        if (x > ChandeliersChapter.galleryRight + 0.4 &&
            x < ChandeliersChapter.danceLeft - 1.0 &&
            !hall.great.wedged) {
          axis = 0;
        }
        if (grounded && x > 71.3 && x < 71.9 && !jumped.contains('hole')) {
          jump('hole');
        }
        if (grounded && x > 79.2 && x < 79.7 && !jumped.contains('table')) {
          jump('table');
        }
        if (grounded && x > 87.3 && x < 87.9 && !jumped.contains('gap')) {
          jump('gap');
        }
        if (mode == InteractionMode.swinging &&
            x > ChandeliersChapter.gapLeft + 2.4 &&
            player.velocity.x > 1.5 &&
            cooldown <= 0) {
          cooldown = 2;
          jump('releaseLast');
        }
        if (mode == InteractionMode.hanging) axis = 1;
      }
      if (hall.chasing && !hall.keeper.gone) {
        final double gap = x - hall.keeper.x;
        if (gap < closest) closest = gap;
      }
      intent.setKeyboardState(axis: axis, down: down);
      driveExtension(game);
      game.update(1 / 60);
      if (player.isDead) {
        fail(
          'died at x=${x.toStringAsFixed(2)} feet=${feet.toStringAsFixed(2)} '
          'after $jumped, $swings swings; great '
          '${hall.great.body.position} landed ${hall.great.landed}; guards '
          '${hall.guards.map((g) => '${g.x.toStringAsFixed(1)} ${g.gone}').toList()}; '
          'keeper ${hall.keeper.x.toStringAsFixed(2)} ${hall.keeper.mode.name}',
        );
      }
      if (x > reached) reached = x;
    }
    intent.setKeyboardState(axis: 0, down: false);
    expect(
      hall.isComplete,
      isTrue,
      reason:
          'stopped at x=${player.body.position.x.toStringAsFixed(2)} '
          'y=${player.body.position.y.toStringAsFixed(2)} '
          '(furthest ${reached.toStringAsFixed(1)}) after $jumped; mode '
          '${player.interactions.mode.name}; great ${hall.great.body.position} '
          'angle ${hall.great.body.angle}; last ${hall.last.body.position}',
    );
    expect(swings, greaterThanOrEqualTo(3));
    expect(hall.guards.every((g) => g.gone), isTrue, reason: 'crushed');
    expect(
      hall.last.released,
      isTrue,
      reason: 'after $jumped; cord pulled ${hall.lastCord.pulled}',
    );
    expect(closest, greaterThan(0.8));
    // ignore: avoid_print
    print('closest the keeper came: ${closest.toStringAsFixed(2)} m');
  });

  testWidgets('down in the pit with them, without the chandelier, is death', (
    tester,
  ) async {
    final game = await bootCampaign(tester);
    final hall = await enterChapter<ChandeliersChapter>(tester, game, 19);
    final player = hall.player;
    player.teleportTo(
      Vector2(
        ChandeliersChapter.danceLeft - 0.8,
        ChandeliersChapter.floor - 0.65,
      ),
    );
    var died = false;
    for (var i = 0; i < 60 * 6 && !died; i++) {
      game.intent.setKeyboardState(axis: 1);
      driveExtension(game);
      game.update(1 / 60);
      died = player.isDead;
    }
    game.intent.setKeyboardState(axis: 0);
    expect(died, isTrue);
    expect(hall.great.released, isFalse);
  });
}
