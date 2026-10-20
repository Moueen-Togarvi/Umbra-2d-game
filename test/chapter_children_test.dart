import 'support/route_pilot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/children.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/castle_props.dart';

import 'support/campaign.dart';

void main() {
  testWidgets('chapter eleven: three cells opened, the watcher burnt by the '
      'lamp, the chest shifted with the children, and out through the drain', (
    tester,
  ) async {
    final game = await bootCampaign(tester);
    final dungeon = await enterChapter<ChildrenChapter>(tester, game, 24);
    final player = dungeon.player;
    final intent = game.intent;
    final jumped = <String>{};
    var helped = 0;
    double reached = 0;
    double cooldown = 0;
    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    // Each cord in turn, and what must have happened before going on.
    final List<(PullCord, bool Function())> cords = [
      (dungeon.cellCords[0], () => dungeon.cells[0].isOpen),
      (
        dungeon.lampCord,
        () => dungeon.watcher.gone && !(dungeon.lamp.fire?.burning ?? true),
      ),
      (dungeon.cellCords[1], () => dungeon.cells[1].isOpen),
      (dungeon.cellCords[2], () => dungeon.cells[2].isOpen),
    ];
    var next = 0;
    for (var i = 0; i < 60 * 900 && !dungeon.isComplete; i++) {
      final double x = player.body.position.x;
      final double feet = player.body.position.y + GameConfig.playerHeight / 2;
      final bool grounded = player.isOnGround;
      final mode = player.interactions.mode;
      double axis = 1;
      bool down = false;
      cooldown -= 1 / 60;
      if (!intent.isScripted) {
        if (next < cords.length) {
          final (cord, done) = cords[next];
          final double cx = cord.anchor.x;
          if (mode == InteractionMode.swinging ||
              mode == InteractionMode.climbing) {
            axis = 0;
            down = cord.pulled;
          } else if (cord.pulled) {
            axis = 0;
            if (done()) next++;
          } else if (x > cx - 8) {
            final double off = cx - x;
            axis = off.abs() > 0.12
                ? off.sign * (off.abs() > 0.6 ? 1 : 0.35)
                : 0;
            // The lamp only when the watcher walks under it.
            final bool now =
                cord != dungeon.lampCord ||
                (dungeon.watcher.x - ChildrenChapter.lampX).abs() < 1.0;
            if (axis == 0 && grounded && now && cooldown <= 0) {
              cooldown = 1.2;
              jump('cord$next');
            }
          }
        }
        if (player.interactions.mode == InteractionMode.pushing) {
          if (dungeon.following.helping > helped) {
            helped = dungeon.following.helping;
          }
        }
        // Out of the passage, over the chest.
        final double cx = dungeon.chest.body.position.x;
        if (cx > ChildrenChapter.passageRight + 0.6 &&
            grounded &&
            x > cx - 1.6 &&
            x < cx - 0.6 &&
            cooldown <= 0) {
          cooldown = 0.8;
          jump('overChest');
        }
        for (final step in const [95.3, 99.3]) {
          if (grounded && x > step && x < step + 0.5 && cooldown <= 0) {
            cooldown = 0.8;
            jump('step$step');
          }
        }
        if (mode == InteractionMode.hanging) axis = 1;
      }
      intent.setKeyboardState(axis: axis, down: down);
      driveExtension(game);
      game.update(1 / 60);
      if (player.isDead) {
        fail(
          'died at x=${x.toStringAsFixed(2)} feet=${feet.toStringAsFixed(2)} '
          'after $jumped, next $next; watcher '
          '${dungeon.watcher.x.toStringAsFixed(2)} ${dungeon.watcher.mode.name}; '
          'fire ${dungeon.lamp.fire?.extent}',
        );
      }
      if (x > reached) reached = x;
    }
    intent.setKeyboardState(axis: 0, down: false);
    expect(
      dungeon.isComplete,
      isTrue,
      reason:
          'stopped at x=${player.body.position.x.toStringAsFixed(2)} '
          'y=${player.body.position.y.toStringAsFixed(2)} '
          '(furthest ${reached.toStringAsFixed(1)}) after $jumped, next $next; '
          'mode ${player.interactions.mode.name}; chest '
          '${dungeon.chest.body.position}; kids '
          '${dungeon.kids.map((k) => '${k.feet.x.toStringAsFixed(1)} ${k.following}').toList()}',
    );
    expect(dungeon.watcher.gone, isTrue, reason: 'burnt in the corridor');
    expect(helped, 2, reason: 'two pushed the chest with him');
    expect(dungeon.escaped, isTrue);
    expect(dungeon.kids.every((k) => k.gone), isTrue);
  });
}
