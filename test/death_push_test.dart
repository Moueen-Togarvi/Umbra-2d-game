import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/game/umbra_game.dart';

void main() {
  Future<(UmbraGame, Player)> boot(WidgetTester tester) async {
    final game = UmbraGame();
    await tester.pumpWidget(GameWidget(game: game));
    for (
      var i = 0;
      i < 30 && game.world.descendants().whereType<Player>().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    game.pauseEngine();
    addTearDown(game.pauseEngine);
    return (game, game.world.descendants().whereType<Player>().single);
  }

  testWidgets('a blow throws the body the way it came; a plain death just '
      'lets it fall', (tester) async {
    final (game, player) = await boot(tester);
    void advance(double seconds) {
      for (var i = 0; i < (seconds * 120).round(); i++) {
        game.update(1 / 120);
      }
    }

    player.teleportTo(Vector2(19, 5));
    advance(1);
    final double start = player.body.position.x;
    player.die(push: Vector2(-4.5, -1.2));
    advance(0.25);
    final double thrown = player.rigPoseWorld.pelvis.x - start;
    expect(thrown, lessThan(-0.4), reason: 'knocked back to the left');

    game.resetFromPause();
    advance(4);
    expect(player.isDead, isFalse);
    player.teleportTo(Vector2(19, 5));
    advance(1);
    final double still = player.body.position.x;
    player.die();
    advance(0.25);
    expect((player.rigPoseWorld.pelvis.x - still).abs(), lessThan(0.25));
  });
}
