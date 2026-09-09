import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/game/umbra_game.dart';

/// Behavioural checks for the Step 1 physics setup.
///
/// These do not test Box2D — Box2D is already tested. They check that *our*
/// world is wired the way we think it is: gravity acts, the ground stops the
/// player, the foot sensor reports contact, a real key press produces a jump of
/// the height we configured, and the checkpoint respawn still works.
///
/// Driving these through actual key events rather than by poking the player
/// directly means the input layer is covered too.
void main() {
  /// Advances the game loop by [frames] steps of roughly 60fps.
  Future<void> advance(WidgetTester tester, int frames) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<(UmbraGame, Player)> boot(WidgetTester tester) async {
    final game = UmbraGame();
    await tester.pumpWidget(GameWidget(game: game));
    // One pump runs onLoad; the rest let the world settle onto the floor.
    await tester.pump();
    await advance(tester, 30);
    return (game, game.world.descendants().whereType<Player>().single);
  }

  testWidgets('player rests on the floor instead of falling through', (
    tester,
  ) async {
    final (_, player) = await boot(tester);

    // Feet should sit at the floor surface, within Box2D's allowed resting
    // overlap (linearSlop is 5mm).
    final feetY = player.body.position.y + GameConfig.playerHeight / 2;
    expect(feetY, closeTo(GameConfig.floorSurfaceY, 0.05));

    // The foot sensor must agree, or jumping will never work.
    expect(player.isOnGround, isTrue);

    // At rest: not sinking, not jittering.
    expect(player.body.linearVelocity.y.abs(), lessThan(0.1));
  });

  testWidgets('holding a direction key walks the player', (tester) async {
    final (_, player) = await boot(tester);
    final startX = player.body.position.x;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await advance(tester, 30);

    expect(player.body.position.x, greaterThan(startX));

    // Releasing the key stops the player promptly, rather than letting it
    // coast.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await advance(tester, 5);
    expect(player.body.linearVelocity.x.abs(), lessThan(0.1));
  });

  testWidgets('a space press jumps to roughly the configured apex', (
    tester,
  ) async {
    final (_, player) = await boot(tester);
    final restingY = player.body.position.y;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);

    var highestPoint = restingY;
    for (var i = 0; i < 40; i++) {
      await advance(tester, 1);
      // Smaller y is higher up: Flame's y-axis points down.
      if (player.body.position.y < highestPoint) {
        highestPoint = player.body.position.y;
      }
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);

    final achievedApex = restingY - highestPoint;
    // Within 15%. Frame-stepped integration will not land exactly on the
    // closed-form value, and it does not need to.
    expect(
      achievedApex,
      closeTo(GameConfig.jumpApexMeters, GameConfig.jumpApexMeters * 0.15),
    );
  });

  testWidgets('the player cannot jump again while airborne', (tester) async {
    final (_, player) = await boot(tester);
    final restingY = player.body.position.y;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await advance(tester, 10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);

    expect(player.isOnGround, isFalse, reason: 'should be mid-air by now');

    // A second press mid-air must be ignored.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await advance(tester, 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);

    var highestPoint = restingY;
    for (var i = 0; i < 40; i++) {
      await advance(tester, 1);
      if (player.body.position.y < highestPoint) {
        highestPoint = player.body.position.y;
      }
    }

    // Still a single jump's worth of height, not two.
    expect(restingY - highestPoint, lessThan(GameConfig.jumpApexMeters * 1.2));
  });

  testWidgets('falling into the hazard respawns at the checkpoint, at rest', (
    tester,
  ) async {
    final (game, player) = await boot(tester);

    // Drop the player into the pit between the two floor slabs.
    final pitCentreX = (GameConfig.gapStartX + GameConfig.gapEndX) / 2;
    player.teleportTo(Vector2(pitCentreX, 1));

    await advance(tester, 120);

    // Back at the checkpoint...
    expect(
      player.body.position.x,
      closeTo(game.checkpoints.activeCheckpoint.x, 0.05),
    );
    // ...carrying no leftover speed from the fall...
    expect(player.body.linearVelocity.length, lessThan(0.5));
    // ...and standing, not stuck mid-air.
    expect(player.isOnGround, isTrue);
  });
}
