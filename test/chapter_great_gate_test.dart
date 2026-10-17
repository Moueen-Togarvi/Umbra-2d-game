import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/great_gate.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/config/game_config.dart';

import 'support/campaign.dart';

void main() {
  testWidgets('chapter thirteen: two crates sink the gate\'s bucket, and the '
      'drawbridge comes down ahead of the keeper', (tester) async {
    final game = await bootCampaign(tester);
    final gate = await enterChapter<GreatGateChapter>(tester, game, 12);
    final player = gate.player;
    final intent = game.intent;
    final jumped = <String>{};
    double closest = 99;
    double reached = 0;
    double cooldown = 0;
    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    for (var i = 0; i < 60 * 150 && !gate.isComplete; i++) {
      final double x = player.body.position.x;
      final double feet = player.body.position.y + GameConfig.playerHeight / 2;
      final bool grounded = player.isOnGround;
      final mode = player.interactions.mode;
      double axis = 1;
      bool down = false;
      cooldown -= 1 / 60;
      if (!intent.isScripted) {
        if (grounded && feet > 6.9 && x > 13.2 && x < 13.8 && cooldown <= 0) {
          cooldown = 0.8;
          jump('gallery');
        }
        // At the end of the gallery: wait for the gate to go up.
        if (x > GreatGateChapter.panLeft - 1.0 &&
            x < GreatGateChapter.panLeft &&
            feet < 6 &&
            gate.gate.travel > -2.2) {
          axis = 0;
        }
        if (grounded && x > 40.2 && x < 40.7 && cooldown <= 0) {
          cooldown = 0.8;
          jump('cart');
        }
        // The drawbridge's cord.
        final double cx = gate.bridgeCord.anchor.x;
        if (x > cx - 2 && x < GreatGateChapter.moatLeft && !gate.bridge.down) {
          if (mode == InteractionMode.swinging ||
              mode == InteractionMode.climbing) {
            axis = 0;
            down = gate.bridgeCord.pulled;
          } else if (!gate.bridgeCord.pulled) {
            final double off = cx - x;
            axis = off.abs() > 0.12
                ? off.sign * (off.abs() > 0.6 ? 1 : 0.35)
                : 0;
            if (grounded && off.abs() < 0.5 && cooldown <= 0) {
              cooldown = 1.0;
              jump('cord');
            }
          } else {
            axis = 0;
          }
        }
        if (mode == InteractionMode.hanging) axis = 1;
      }
      if (gate.chasing && !gate.keeper.gone) {
        final double gap = x - gate.keeper.x;
        if (gap < closest) closest = gap;
      }
      intent.setKeyboardState(axis: axis, down: down);
      game.update(1 / 60);
      if (player.isDead) {
        fail(
          'died at x=${x.toStringAsFixed(2)} feet=${feet.toStringAsFixed(2)} '
          'after $jumped; keeper ${gate.keeper.x.toStringAsFixed(2)} '
          '${gate.keeper.mode.name}; bridge ${gate.bridge.body.angle}; gate '
          '${gate.gate.travel}',
        );
      }
      if (x > reached) reached = x;
    }
    intent.setKeyboardState(axis: 0, down: false);
    expect(
      gate.isComplete,
      isTrue,
      reason:
          'stopped at x=${player.body.position.x.toStringAsFixed(2)} '
          'y=${player.body.position.y.toStringAsFixed(2)} '
          '(furthest ${reached.toStringAsFixed(1)}) after $jumped; mode '
          '${player.interactions.mode.name}; crates ${gate.crateA.body.position} '
          '${gate.crateB.body.position}; gate ${gate.gate.travel}; bridge '
          '${gate.bridge.body.angle}',
    );
    expect(gate.bridge.down, isTrue);
    expect(closest, greaterThan(0.8));
    // ignore: avoid_print
    print('closest the keeper came: ${closest.toStringAsFixed(2)} m');
  });
}
