import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/chase.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/config/game_config.dart';

import 'support/campaign.dart';

void main() {
  testWidgets('chapter seven: the crate in the pan raises the gate, the '
      'bookcase makes a bridge, and the latched gate shuts the keeper out', (
    tester,
  ) async {
    final game = await bootCampaign(tester);
    final chase = await enterChapter<ChaseChapter>(tester, game, 6);
    final player = chase.player;
    final intent = game.intent;
    final jumped = <String>{};
    var gateRose = false, bridged = false, shutOut = false;
    double closest = 99;
    double reached = 0;
    double cooldown = 0;
    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    for (var i = 0; i < 60 * 150 && !chase.isComplete; i++) {
      final double x = player.body.position.x;
      final double feet = player.body.position.y + GameConfig.playerHeight / 2;
      final bool grounded = player.isOnGround;
      final mode = player.interactions.mode;
      double axis = 1;
      cooldown -= 1 / 60;
      if (!intent.isScripted) {
        // The kitchen: the crate into the pan, then wait for the gate.
        final bool crateIn = chase.crate.body.position.x > ChaseChapter.panLeft;
        if (crateIn &&
            x < ChaseChapter.panLeft &&
            chase.kitchenGate.travel > -1.8) {
          axis = 0;
        }
        gateRose |= chase.kitchenGate.travel < -1.8;
        // Down onto the crate in the pan, and up the far side.
        if (grounded && x > 20.2 && x < 22 && feet > 7.6 && cooldown <= 0) {
          cooldown = 0.6;
          jump('outOfPan');
        }
        if (grounded && x > 47.1 && x < 47.7 && !jumped.contains('table')) {
          jump('table');
        }
        if (grounded && x > 55.2 && x < 55.8 && !jumped.contains('hole')) {
          jump('hole');
        }
        if (grounded && x > 62.2 && x < 62.8 && feet > 6.8 && cooldown <= 0) {
          cooldown = 0.6;
          jump('step');
        }
        // The bookcase: shove it over, then wait for it to come down.
        final double tilt = chase.bookcase.body.angle.abs();
        if (x > 66 && x < ChaseChapter.gapLeft && tilt > 0.25 && tilt < 1.35) {
          axis = 0;
        }
        bridged |= tilt > 1.35;
        if (grounded &&
            chase.bookcase.wedged &&
            x > 68.9 &&
            x < 69.7 &&
            !jumped.contains('ontoBookcase')) {
          jump('ontoBookcase');
        }
        if (grounded && x > 87.3 && x < 87.9 && !jumped.contains('pit')) {
          jump('pit');
        }
        if (mode == InteractionMode.swinging &&
            x > ChaseChapter.pitLeft + 2.4 &&
            player.velocity.x > 1.5 &&
            cooldown <= 0) {
          cooldown = 2;
          jump('release');
        }
        if (grounded && x > 99.2 && x < 99.8 && cooldown <= 0) {
          cooldown = 0.6;
          jump('step2');
        }
        if (grounded && x > 105.2 && x < 105.8 && cooldown <= 0) {
          cooldown = 0.6;
          jump('step3');
        }
        if (player.interactions.mode == InteractionMode.hanging) axis = 1;
      }
      if (chase.chasing && !chase.keeper.gone) {
        final double gap = x - chase.keeper.x;
        if (gap < closest) closest = gap;
      }
      shutOut |= chase.latchedGate.isShut && chase.pursuer.blocked;
      intent.setKeyboardState(axis: axis);
      game.update(1 / 60);
      if (player.isDead) {
        fail(
          'died at x=${x.toStringAsFixed(2)} feet=${feet.toStringAsFixed(2)} '
          'after $jumped; keeper at ${chase.keeper.x.toStringAsFixed(2)} '
          '(${chase.keeper.mode.name}), closest ${closest.toStringAsFixed(2)}; '
          'bookcase ${chase.bookcase.body.angle.toStringAsFixed(2)}, '
          'gate ${chase.latchedGate.travel.toStringAsFixed(2)}',
        );
      }
      if (x > reached) reached = x;
    }
    intent.setKeyboardState(axis: 0);
    expect(
      chase.isComplete,
      isTrue,
      reason:
          'stopped at x=${player.body.position.x.toStringAsFixed(2)} '
          'y=${player.body.position.y.toStringAsFixed(2)} '
          '(furthest ${reached.toStringAsFixed(1)}) after $jumped; mode '
          '${player.interactions.mode.name}; crate '
          '${chase.crate.body.position}; gate ${chase.kitchenGate.travel}; '
          'bookcase ${chase.bookcase.body.angle} at ${chase.bookcase.body.position}',
    );
    expect(gateRose, isTrue);
    expect(bridged, isTrue);
    expect(shutOut, isTrue, reason: 'the keeper ended up behind the gate');
    expect(closest, greaterThan(0.8), reason: 'it never had him');
    // ignore: avoid_print
    print('closest the keeper came: ${closest.toStringAsFixed(2)} m');
  });

  testWidgets('stopping in the chase gets him caught; from the checkpoint '
      'the keeper comes again, a little way behind', (tester) async {
    final game = await bootCampaign(tester);
    final chase = await enterChapter<ChaseChapter>(tester, game, 6);
    final player = chase.player;
    // In the cellar, as if he had come through the gate.
    player.teleportTo(Vector2(37, ChaseChapter.floor - 0.65));
    var died = false;
    for (var i = 0; i < 60 * 12 && !died; i++) {
      game.intent.setKeyboardState(axis: i < 40 ? 1 : 0);
      game.update(1 / 60);
      died = player.isDead;
    }
    expect(died, isTrue, reason: 'it caught him standing there');
    expect(chase.pursuer.caught, isTrue);
    // Back at the checkpoint, and it comes again.
    for (var i = 0; i < 60 * 6 && player.isDead; i++) {
      game.update(1 / 60);
    }
    expect(player.isDead, isFalse);
    for (var i = 0; i < 60 * 2; i++) {
      game.update(1 / 60);
    }
    expect(chase.chasing, isTrue);
    expect(chase.keeper.gone, isFalse);
    expect(player.body.position.x - chase.keeper.x, greaterThan(4));
  });
}
