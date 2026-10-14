import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/ground.dart';
import 'package:umbra/entities/hill_ground.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/entities/rock.dart';
import 'package:umbra/game/umbra_game.dart';

void main() {
  Future<UmbraGame> boot(WidgetTester tester) async {
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
    game.pauseEngine();
    addTearDown(() {
      game.pauseEngine();
      if (game.world.physicsWorld.isValid) game.world.physicsWorld.destroy();
    });
    return game;
  }

  double drawnGround(UmbraGame game, double x) => game.world
      .descendants()
      .whereType<HillGround>()
      .firstWhere((bank) => x >= bank.segment.left && x <= bank.segment.right)
      .drawnHeightAt(x);

  testWidgets('logs lie in the soil, with no light under them', (tester) async {
    final game = await boot(tester);
    final logs = game.world
        .descendants()
        .whereType<Ground>()
        .where((g) => g.style == GroundStyle.log)
        .toList();
    expect(logs, hasLength(GameConfig.logs.length));
    for (final log in logs) {
      final centre = log.body.position;
      final span = GameConfig.logs.firstWhere(
        (s) => ((s[0] + s[1]) / 2 - centre.x).abs() < 1e-3,
      );
      final double top = centre.y - log.size.y / 2;
      for (double x = span[0] + 0.06; x <= span[1] - 0.06; x += 0.05) {
        Offset local(double y) => Offset(x - centre.x, y - centre.y);
        // Just above the ground under it, the log or its soil is there.
        final double ground = drawnGround(game, x);
        expect(
          log.outline.contains(local(ground - 0.006)),
          isTrue,
          reason: 'a gap under the log at x=$x',
        );
        // The bark is where the feet land, within a centimetre.
        if (x > span[0] + 0.35 && x < span[1] - 0.35) {
          expect(log.outline.contains(local(top + 0.012)), isTrue);
        }
      }
      // And the physics reaches down into the ground too.
      final double bottom = centre.y + log.size.y / 2;
      for (double x = span[0]; x <= span[1]; x += 0.1) {
        expect(bottom, greaterThan(drawnGround(game, x)));
      }
    }
  });

  testWidgets('boulders sit half sunk in the ground', (tester) async {
    final game = await boot(tester);
    final rocks = game.world.descendants().whereType<Rock>().toList();
    expect(rocks, hasLength(GameConfig.rocks.length));
    for (final rock in rocks) {
      final centre = rock.body.position;
      for (final x in [rock.left + 0.05, rock.right - 0.05]) {
        final double ground = drawnGround(game, x);
        expect(
          rock.outline.contains(Offset(x - centre.x, ground + 0.01 - centre.y)),
          isTrue,
          reason: 'the rock goes into the ground at x=$x',
        );
      }
      // It stands about its height out of the ground.
      final top = rock.body.position.y - GameConfig.rockHeight;
      expect(rock.outline.contains(Offset(0, top + 0.03 - centre.y)), isTrue);
    }
  });
}
