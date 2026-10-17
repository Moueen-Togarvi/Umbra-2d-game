import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/clock_tower.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/config/game_config.dart';

import 'support/campaign.dart';

void main() {
  testWidgets('chapter ten: across on the pendulum, the hammer stopped by a '
      'crate in the gear, and over the shaft on the minute hand', (
    tester,
  ) async {
    final game = await bootCampaign(tester);
    final tower = await enterChapter<ClockTowerChapter>(tester, game, 9);
    final player = tower.player;
    final intent = game.intent;
    final jumped = <String>{};
    var rode = false;
    double reached = 0;
    double cooldown = 0;
    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    for (var i = 0; i < 60 * 200 && !tower.isComplete; i++) {
      final double x = player.body.position.x;
      final double feet = player.body.position.y + GameConfig.playerHeight / 2;
      final bool grounded = player.isOnGround;
      final mode = player.interactions.mode;
      double axis = 1;
      cooldown -= 1 / 60;
      if (!intent.isScripted) {
        // The pendulum: on at the near end of its swing, off at the far.
        final plate = tower.pendulum.plateTop;
        final double pv = tower.pendulum.body.linearVelocity.x;
        final bool onPlate =
            grounded &&
            (feet - plate.y).abs() < 0.15 &&
            (x - plate.x).abs() < 0.9;
        if (x < ClockTowerChapter.swingLeft && x > 11) {
          final double off = 13.38 - x;
          axis = off.abs() > 0.1 ? off.sign * (off.abs() > 0.5 ? 1 : 0.3) : 0;
          if (grounded &&
              off.abs() < 0.15 &&
              // As it comes in, so that it is there when he lands.
              plate.x < 15.2 &&
              pv < -1.0 &&
              cooldown <= 0) {
            cooldown = 1.0;
            axis = 0.6;
            jump('onto');
          }
        }
        // In the air towards it: keep going.
        if (!grounded && x > 12.5 && x < 15.2 && jumped.contains('onto')) {
          axis = 0.7;
        }
        if (onPlate) {
          rode = true;
          axis = 0;
          if (plate.x > 20.3 && pv.abs() < 1.2 && cooldown <= 0) {
            cooldown = 1.0;
            axis = 1;
            jump('off');
          }
        }
        // The crate in the slot, then over it.
        final double cx = tower.crate.body.position.x;
        final bool crateIn =
            cx > ClockTowerChapter.slotLeft &&
            tower.crate.body.position.y > ClockTowerChapter.floor - 0.3;
        if (crateIn &&
            grounded &&
            x > ClockTowerChapter.slotLeft - 1.0 &&
            x < ClockTowerChapter.slotLeft &&
            cooldown <= 0) {
          cooldown = 0.8;
          jump('overCrate');
        }
        if (x > 32 && x < 38 && !tower.gear.jammed) axis = 0;
        // The hand: from the lip, as soon as it lies level towards him.
        if (x > 42 && x < ClockTowerChapter.shaftLeft && feet > 6.8) {
          final bool ready =
              tower.hand.level &&
              math.cos(tower.hand.pointing) < 0 &&
              tower.hand.untilNext > 1.4;
          if (!ready && x > 45.6) axis = 0;
        }
        for (final step in const [63.3, 69.3, 75.3]) {
          if (grounded && x > step && x < step + 0.5 && cooldown <= 0) {
            cooldown = 0.8;
            jump('step$step');
          }
        }
        if (mode == InteractionMode.hanging) axis = 1;
      }
      intent.setKeyboardState(axis: axis);
      game.update(1 / 60);
      if (player.isDead) {
        fail(
          'died at x=${x.toStringAsFixed(2)} feet=${feet.toStringAsFixed(2)} '
          'after $jumped; plate ${tower.pendulum.plateTop}; gear '
          '${tower.gear.turning.toStringAsFixed(2)}; crate '
          '${tower.crate.body.position}; hand '
          '${tower.hand.pointing.toStringAsFixed(2)}',
        );
      }
      if (x > reached) reached = x;
    }
    intent.setKeyboardState(axis: 0);
    expect(
      tower.isComplete,
      isTrue,
      reason:
          'stopped at x=${player.body.position.x.toStringAsFixed(2)} '
          'y=${player.body.position.y.toStringAsFixed(2)} '
          '(furthest ${reached.toStringAsFixed(1)}) after $jumped; mode '
          '${player.interactions.mode.name}; plate ${tower.pendulum.plateTop}; '
          'crate ${tower.crate.body.position}; gear ${tower.gear.turning}',
    );
    expect(rode, isTrue);
    expect(tower.gear.jammed, isTrue);
  });
}
