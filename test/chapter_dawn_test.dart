import 'support/route_pilot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/dawn.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/story/vampire.dart';

import 'support/campaign.dart';

void main() {
  testWidgets('chapter fifteen: the sun catches the last two behind him, and '
      'he comes home, and his eyes go red', (tester) async {
    final game = await bootCampaign(tester);
    final dawn = await enterChapter<DawnChapter>(tester, game, 39);
    final player = dawn.player;
    final intent = game.intent;
    final jumped = <String>{};
    double closest = 99;
    double reached = 0;
    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    for (var i = 0; i < 60 * 900 && !dawn.isComplete; i++) {
      final double x = player.body.position.x;
      final double feet = player.body.position.y + GameConfig.playerHeight / 2;
      final bool grounded = player.isOnGround;
      double axis = 1;
      if (!intent.isScripted) {
        if (grounded && x > 49.2 && x < 49.7 && !jumped.contains('fence')) {
          jump('fence');
        }
        if (grounded && x > 57.3 && x < 57.9 && !jumped.contains('ditch')) {
          jump('ditch');
        }
        if (player.interactions.mode == InteractionMode.hanging) axis = 1;
      }
      for (final v in dawn.last) {
        if (!v.gone && v.mode != VampireMode.burn) {
          final double gap = x - v.x;
          if (gap < closest) closest = gap;
        }
      }
      intent.setKeyboardState(axis: axis);
      driveExtension(game);
      game.update(1 / 60);
      if (player.isDead) {
        fail(
          'died at x=${x.toStringAsFixed(2)} feet=${feet.toStringAsFixed(2)} '
          'after $jumped; them '
          '${dawn.last.map((v) => '${v.x.toStringAsFixed(1)} ${v.mode.name}').toList()}; '
          'sun ${dawn.sun.edge.toStringAsFixed(1)}',
        );
      }
      if (x > reached) reached = x;
    }
    intent.setKeyboardState(axis: 0);
    expect(
      dawn.isComplete,
      isTrue,
      reason:
          'stopped at x=${player.body.position.x.toStringAsFixed(2)} '
          '(furthest ${reached.toStringAsFixed(1)}) after $jumped; home '
          '${dawn.home}',
    );
    expect(dawn.last.every((v) => v.gone), isTrue, reason: 'burnt at sunrise');
    expect(dawn.home, isTrue);
    expect(dawn.redEyes, isTrue);
    // ignore: avoid_print
    print('closest they came: ${closest.toStringAsFixed(2)} m');
  });
}
