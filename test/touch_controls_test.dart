import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/game/umbra_game.dart';

/// Checks the on-screen controls, which are the only way to play on a phone.
///
/// These drive the real HUD buttons by their real screen positions rather than
/// poking [PlayerIntent] directly, so they cover the whole chain: touch ->
/// button -> intent -> physics. If the buttons were mispositioned, off-screen,
/// or not receiving taps, these fail.
void main() {
  /// A landscape phone, in logical pixels. Roughly a 20:9 device.
  final phoneSize = Vector2(800, 360);

  Future<void> advance(WidgetTester tester, int frames) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<(UmbraGame, Player, List<HudButtonComponent>)> boot(
    WidgetTester tester,
  ) async {
    final game = UmbraGame();
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: phoneSize.toSize()),
        child: GameWidget(game: game),
      ),
    );
    await tester.pump();
    await advance(tester, 30);

    final buttons = game.camera.viewport.children
        .whereType<HudButtonComponent>()
        .toList();
    final player = game.world.descendants().whereType<Player>().single;
    return (game, player, buttons);
  }

  /// The three buttons, in the order TouchControls builds them.
  const int walkLeft = 0;
  const int walkRight = 1;
  const int jump = 2;

  testWidgets('three controls mount into the camera viewport', (tester) async {
    final (_, _, buttons) = await boot(tester);
    expect(buttons, hasLength(3));
  });

  testWidgets('controls sit on screen, along the bottom, thumbs apart', (
    tester,
  ) async {
    final (game, _, buttons) = await boot(tester);
    final viewport = game.camera.viewport.virtualSize;

    for (final button in buttons) {
      final rect = button.toRect();
      expect(
        rect.left >= 0 && rect.right <= viewport.x,
        isTrue,
        reason: 'button is off screen horizontally: $rect in $viewport',
      );
      expect(
        rect.bottom <= viewport.y,
        isTrue,
        reason: 'button hangs below the screen: $rect in $viewport',
      );
      // All three belong in the lower half, where thumbs are.
      expect(rect.center.dy, greaterThan(viewport.y / 2));
    }

    // Walk buttons on the left, jump on the right, and not overlapping.
    expect(buttons[walkLeft].toRect().right, lessThan(viewport.x / 2));
    expect(buttons[jump].toRect().left, greaterThan(viewport.x / 2));
    expect(
      buttons[walkLeft].toRect().overlaps(buttons[walkRight].toRect()),
      isFalse,
    );
  });

  testWidgets('holding the walk buttons moves the player both ways', (
    tester,
  ) async {
    final (_, player, buttons) = await boot(tester);
    final startX = player.body.position.x;

    // Press and hold walk-right.
    final rightGesture = await tester.startGesture(
      buttons[walkRight].absolutePosition.toOffset(),
    );
    await advance(tester, 30);
    expect(player.body.position.x, greaterThan(startX));

    await rightGesture.up();
    await advance(tester, 5);
    expect(
      player.body.linearVelocity.x.abs(),
      lessThan(0.1),
      reason: 'releasing the button should stop the player',
    );

    // And back the other way.
    final afterRightX = player.body.position.x;
    final leftGesture = await tester.startGesture(
      buttons[walkLeft].absolutePosition.toOffset(),
    );
    await advance(tester, 30);
    expect(player.body.position.x, lessThan(afterRightX));
    await leftGesture.up();
  });

  testWidgets('the jump button gets the player off the ground', (tester) async {
    final (_, player, buttons) = await boot(tester);
    final restingY = player.body.position.y;

    final tap = await tester.startGesture(
      buttons[jump].absolutePosition.toOffset(),
    );
    await advance(tester, 10);
    await tap.up();

    expect(player.isOnGround, isFalse);
    expect(
      player.body.position.y,
      lessThan(restingY),
      reason: 'smaller y is higher up',
    );
  });

  testWidgets('walking and jumping work at the same time (multi-touch)', (
    tester,
  ) async {
    final (_, player, buttons) = await boot(tester);
    final startX = player.body.position.x;

    // Thumb one holds walk-right...
    final walk = await tester.startGesture(
      buttons[walkRight].absolutePosition.toOffset(),
      pointer: 1,
    );
    await advance(tester, 5);

    // ...thumb two taps jump. This is the case a single-pointer implementation
    // would break.
    final leap = await tester.startGesture(
      buttons[jump].absolutePosition.toOffset(),
      pointer: 2,
    );
    await advance(tester, 10);
    await leap.up();

    expect(player.isOnGround, isFalse, reason: 'should have jumped');
    expect(
      player.body.position.x,
      greaterThan(startX),
      reason: 'should still be moving right while airborne',
    );

    await walk.up();
  });

  testWidgets('releasing one walk button keeps the other one held', (
    tester,
  ) async {
    final (_, player, buttons) = await boot(tester);

    // Hold left, then tap right and let go. Left is still down, so the player
    // must resume walking left rather than stopping.
    final left = await tester.startGesture(
      buttons[walkLeft].absolutePosition.toOffset(),
      pointer: 1,
    );
    await advance(tester, 5);

    final right = await tester.startGesture(
      buttons[walkRight].absolutePosition.toOffset(),
      pointer: 2,
    );
    await advance(tester, 5);
    await right.up();
    await advance(tester, 5);

    expect(
      player.body.linearVelocity.x,
      lessThan(-GameConfig.moveSpeedMetersPerSecond / 2),
      reason: 'left is still held, so the player should be walking left',
    );

    await left.up();
  });
}
