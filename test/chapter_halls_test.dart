import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/halls.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/config/game_config.dart';

import 'support/campaign.dart';

void main() {
  testWidgets('chapter eight: the lantern drives one into the wall, the '
      'lift rises without the chest, and the moon drives the last down the '
      'gallery', (tester) async {
    final game = await bootCampaign(tester);
    final halls = await enterChapter<HallsChapter>(tester, game, 7);
    final player = halls.player;
    final intent = game.intent;
    final jumped = <String>{};
    var ruleShown = false, rode = false;
    int cord = 0;
    double reached = 0;
    double cooldown = 0;
    double waitAtCord = 0;
    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    for (var i = 0; i < 60 * 240 && !halls.isComplete; i++) {
      final double x = player.body.position.x;
      final double feet = player.body.position.y + GameConfig.playerHeight / 2;
      final bool grounded = player.isOnGround;
      final mode = player.interactions.mode;
      double axis = 1;
      bool down = false;
      cooldown -= 1 / 60;
      ruleShown |= halls.visitor.shieldGoal > 0.5;
      if (!intent.isScripted) {
        final double cartX = halls.cart.body.position.x;
        // The corridor: push the lantern all the way to the wall.
        if (x < HallsChapter.wallLeft && feet > 6.5) {
          final bool burnt = halls.corridor.gone;
          if (!burnt && cartX > 46.6) axis = 0;
          if (burnt && grounded && x > cartX - 1.4 && cooldown <= 0) {
            cooldown = 0.6;
            jump('ontoCart');
          }
        }
        // On the cart's bed: up the wall.
        if (grounded && feet < 6.5 && feet > 6.0 && x < HallsChapter.wallLeft) {
          if (x < cartX + 0.3) {
            axis = 0.4;
          } else if (cooldown <= 0) {
            cooldown = 0.8;
            jump('wall');
          }
        }
        // The lift: over its rail, the chest off the far side, and up.
        if (x > HallsChapter.wallRight && x < HallsChapter.galleryLeft) {
          final double deck = HallsChapter.floor - 0.24 + halls.lift.travel;
          final bool chestOn = halls.chest.body.position.x < 61.0;
          if (grounded && feet > 6.9 && x > 56.6 && x < 57.3 && cooldown <= 0) {
            cooldown = 0.8;
            axis = 0.55;
            jump('rail');
          } else if (grounded && (feet - deck).abs() < 0.15) {
            if (chestOn) {
              axis = 0.6;
            } else if (halls.lift.travel > -3.0) {
              // Riding up, in the middle of it.
              final double off = HallsChapter.liftX - x;
              axis = off.abs() > 0.15 ? off.sign * 0.5 : 0;
              rode = true;
            }
          } else if (grounded && feet < deck - 0.5 && chestOn) {
            // Up on the chest: back down behind it.
            axis = -0.6;
          }
        }
        // The gallery: each cord in turn, from the light of the last.
        if (x > HallsChapter.galleryLeft && feet < 4 && cord < 4) {
          final double cx = halls.cords[cord].anchor.x;
          final bool keeperNear = cord == 0 && (halls.keeper.x - cx).abs() < 7;
          if (mode == InteractionMode.swinging ||
              mode == InteractionMode.climbing) {
            axis = 0;
            if (halls.cords[cord].pulled) {
              down = true;
            }
          } else if (halls.cords[cord].pulled) {
            // Let go: on to the next one once its window is open.
            if (halls.windows[cord].isOpen) {
              cord++;
            } else {
              axis = 0;
            }
          } else {
            final double off = cx - x;
            if (off.abs() > 0.12) {
              axis = off.sign * (off.abs() > 0.6 ? 1 : 0.35);
            } else {
              axis = 0;
              waitAtCord += 1 / 60;
              if (grounded &&
                  !keeperNear &&
                  waitAtCord > 0.3 &&
                  cooldown <= 0) {
                cooldown = 1.0;
                waitAtCord = 0;
                jump('cord$cord');
              }
            }
          }
        }
        if (cord >= 4 && !halls.keeper.gone && x > HallsChapter.galleryLeft) {
          axis = 0;
        }
        if (mode == InteractionMode.hanging) axis = 1;
      }
      intent.setKeyboardState(axis: axis, down: down);
      game.update(1 / 60);
      if (player.isDead) {
        fail(
          'died at x=${x.toStringAsFixed(2)} feet=${feet.toStringAsFixed(2)} '
          'after $jumped, cord $cord; corridor '
          '${halls.corridor.x.toStringAsFixed(2)} ${halls.corridor.mode.name}; '
          'keeper ${halls.keeper.x.toStringAsFixed(2)} '
          '${halls.keeper.mode.name}; cart '
          '${halls.cart.body.position.x.toStringAsFixed(2)}',
        );
      }
      if (x > reached) reached = x;
    }
    intent.setKeyboardState(axis: 0, down: false);
    expect(
      halls.isComplete,
      isTrue,
      reason:
          'stopped at x=${player.body.position.x.toStringAsFixed(2)} '
          'y=${player.body.position.y.toStringAsFixed(2)} '
          '(furthest ${reached.toStringAsFixed(1)}) after $jumped; cord '
          '$cord; mode ${player.interactions.mode.name}; cart '
          '${halls.cart.body.position}; corridor ${halls.corridor.x} '
          '${halls.corridor.mode.name} gone ${halls.corridor.gone}; lift '
          '${halls.lift.travel}; chest ${halls.chest.body.position}; keeper '
          '${halls.keeper.x} ${halls.keeper.mode.name}; windows '
          '${halls.windows.map((w) => w.isOpen).toList()}',
    );
    expect(ruleShown, isTrue, reason: 'it flinched from the light');
    expect(halls.corridor.gone, isTrue, reason: 'burnt in the corridor');
    expect(rode, isTrue, reason: 'up on the lift');
    expect(halls.keeper.gone, isTrue, reason: 'burnt in the gallery');
  });

  testWidgets('without the lantern, the dark corridor is death', (
    tester,
  ) async {
    final game = await bootCampaign(tester);
    final halls = await enterChapter<HallsChapter>(tester, game, 7);
    final player = halls.player;
    player.teleportTo(Vector2(20, HallsChapter.floor - 0.65));
    var died = false;
    // (The rule is shown first, under the window behind him.)
    for (var i = 0; i < 60 * 20 && !died; i++) {
      game.intent.setKeyboardState(axis: 1);
      game.update(1 / 60);
      died = player.isDead;
    }
    game.intent.setKeyboardState(axis: 0);
    expect(died, isTrue);
    expect(halls.corridorHunt.caught, isTrue);
  });
}
