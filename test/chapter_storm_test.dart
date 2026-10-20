import 'support/route_pilot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/storm.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/config/game_config.dart';

import 'support/campaign.dart';

void main() {
  testWidgets('chapter fourteen: up the cliff over the falling stones, across '
      'the rope bridge, and the lightning takes it behind him', (tester) async {
    final game = await bootCampaign(tester);
    final storm = await enterChapter<StormChapter>(tester, game, 34);
    final player = storm.player;
    final intent = game.intent;
    var hops = 0, gusts = 0;
    double closest = 99;
    double reached = 0;
    double cooldown = 0;
    final flashesAtStart = storm.lightning.flashed;

    for (var i = 0; i < 60 * 900 && !storm.isComplete; i++) {
      final double x = player.body.position.x;
      final double feet = player.body.position.y + GameConfig.playerHeight / 2;
      final bool grounded = player.isOnGround;
      final mode = player.interactions.mode;
      double axis = 1;
      cooldown -= 1 / 60;
      if (storm.gust > 0) gusts++;
      if (!intent.isScripted) {
        // A stone bounding down at him: over it.
        for (final r in storm.stones.rocks) {
          if (!r.isEnabled) continue;
          final double ahead = r.position.x - x;
          if (grounded &&
              ahead > 0.6 &&
              ahead < 2.6 &&
              (r.position.y - feet).abs() < 1.2 &&
              cooldown <= 0) {
            cooldown = 0.7;
            hops++;
            intent.requestJump();
          }
        }
        if (mode == InteractionMode.hanging) axis = 1;
      }
      if (storm.chasing && !storm.keeper.gone) {
        final double gap = x - storm.keeper.x;
        if (gap < closest) closest = gap;
      }
      intent.setKeyboardState(axis: axis);
      driveExtension(game);
      game.update(1 / 60);
      if (player.isDead) {
        fail(
          'died at x=${x.toStringAsFixed(2)} feet=${feet.toStringAsFixed(2)} '
          'after $hops hops; keeper ${storm.keeper.x.toStringAsFixed(2)} '
          '${storm.keeper.mode.name}; stones '
          '${storm.stones.rocks.where((r) => r.isEnabled).map((r) => '${r.position.x.toStringAsFixed(1)},${r.position.y.toStringAsFixed(1)} v${r.linearVelocity.x.toStringAsFixed(1)}').toList()}',
        );
      }
      if (x > reached) reached = x;
    }
    intent.setKeyboardState(axis: 0);
    expect(
      storm.isComplete,
      isTrue,
      reason:
          'stopped at x=${player.body.position.x.toStringAsFixed(2)} '
          'y=${player.body.position.y.toStringAsFixed(2)} '
          '(furthest ${reached.toStringAsFixed(1)}); $hops hops',
    );
    expect(storm.bridge.snapped, isTrue);
    expect(storm.lightning.flashed, greaterThan(flashesAtStart));
    expect(gusts, greaterThan(0));
    // ignore: avoid_print
    print(
      'closest the keeper came: ${closest.toStringAsFixed(2)} m, $hops hops',
    );
  });
}
