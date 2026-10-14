import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/entities/physics_props.dart';
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
    WidgetTester tester, {
    bool debugTools = false,
  }) async {
    tester.view.physicalSize = phoneSize.toSize();
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final game = UmbraGame(debugTools: debugTools);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: phoneSize.toSize()),
        child: GameWidget(game: game),
      ),
    );
    for (
      var i = 0;
      i < 20 && game.world.descendants().whereType<Player>().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await advance(tester, 30);

    final buttons = game.camera.viewport.children
        .whereType<HudButtonComponent>()
        .toList();
    final player = game.world.descendants().whereType<Player>().single;
    addTearDown(() {
      game.pauseEngine();
      if (game.world.physicsWorld.isValid) game.world.physicsWorld.destroy();
    });
    return (game, player, buttons);
  }

  /// LIMBO's four controls, in this order, then the rope's climb buttons;
  /// development buttons follow.
  const int walkLeft = 0;
  const int walkRight = 1;
  const int jump = 2;
  const int action = 3;
  const int climbUp = 4;
  const int climbDown = 5;
  const int debugToggle = 6;
  const int reset = 7;
  const int knockdown = 8;

  testWidgets('mobile actions mount into the camera viewport', (tester) async {
    final (_, _, buttons) = await boot(tester);
    expect(
      buttons,
      hasLength(6),
      reason: 'left, right, jump and action, and climbing for ropes',
    );
  });

  testWidgets('climb buttons only appear while holding a rope', (tester) async {
    final (game, player, buttons) = await boot(tester);
    for (final climb in [climbUp, climbDown]) {
      expect(
        buttons[climb].containsLocalPoint(buttons[climb].size / 2),
        isFalse,
      );
    }
    final rope = game.world.descendants().whereType<SwingRope>().single;
    player.teleportTo(rope.grip + Vector2(0, GameConfig.playerHeight * 0.40));
    await advance(tester, 4);
    expect(player.isOnRope, isTrue);
    for (final climb in [climbUp, climbDown]) {
      expect(
        buttons[climb].containsLocalPoint(buttons[climb].size / 2),
        isTrue,
      );
    }
    // Holding ˄ climbs.
    final before = rope.holdLength;
    final up = await tester.startGesture(
      buttons[climbUp].absoluteCenter.toOffset(),
    );
    await advance(tester, 30);
    await up.up();
    expect(rope.holdLength, lessThan(before - 0.2));
  });

  testWidgets('development builds add the debug buttons', (tester) async {
    final (_, _, buttons) = await boot(tester, debugTools: true);
    expect(buttons, hasLength(10));
  });

  testWidgets('controls sit on screen, along the bottom, thumbs apart', (
    tester,
  ) async {
    final (game, _, buttons) = await boot(tester, debugTools: true);
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
    }
    for (final button in buttons.take(4)) {
      expect(button.toRect().center.dy, greaterThan(viewport.y / 2));
    }
    for (var a = 0; a < buttons.length; a++) {
      for (var b = a + 1; b < buttons.length; b++) {
        expect(buttons[a].toRect().overlaps(buttons[b].toRect()), isFalse);
      }
    }

    // Walk buttons on the left, jump and action on the right.
    expect(buttons[walkLeft].toRect().right, lessThan(viewport.x / 2));
    expect(buttons[jump].toRect().left, greaterThan(viewport.x / 2));
    expect(buttons[action].toRect().left, greaterThan(viewport.x / 2));
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
    await advance(tester, 10);
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
    await advance(tester, 10);

    expect(
      player.body.linearVelocity.x,
      lessThan(-GameConfig.moveSpeedMetersPerSecond / 2),
      reason: 'left is still held, so the player should be walking left',
    );

    await left.up();
  });

  testWidgets('one running speed, and lifecycle clears touch holds', (
    tester,
  ) async {
    final (game, player, buttons) = await boot(tester);
    final walk = await tester.startGesture(
      buttons[walkRight].absoluteCenter.toOffset(),
    );
    await advance(tester, 30);
    expect(
      player.body.linearVelocity.x,
      closeTo(GameConfig.moveSpeedMetersPerSecond, 0.1),
    );
    game.lifecycleStateChange(AppLifecycleState.paused);
    game.lifecycleStateChange(AppLifecycleState.resumed);
    await advance(tester, 30);
    expect(player.body.linearVelocity.x.abs(), lessThan(0.1));
    await walk.up();
  });

  testWidgets('drag cancellation releases walk input', (tester) async {
    final (_, player, buttons) = await boot(tester);
    final walk = await tester.startGesture(
      buttons[walkRight].absoluteCenter.toOffset(),
    );
    await advance(tester, 10);
    await walk.cancel();
    await advance(tester, 20);
    expect(player.body.linearVelocity.x.abs(), lessThan(0.1));
  });

  testWidgets(
    'debug toggle draws native geometry and reset returns to checkpoint',
    (tester) async {
      final (game, player, buttons) = await boot(tester, debugTools: true);
      for (final hidden in [reset, knockdown]) {
        expect(
          buttons[hidden].containsLocalPoint(buttons[hidden].size / 2),
          isFalse,
        );
      }
      await tester.tapAt(buttons[debugToggle].absoluteCenter.toOffset());
      await advance(tester, 5);
      expect(game.debugVisible && player.debugEnabled, isTrue);
      expect(tester.takeException(), isNull);
      final walk = await tester.startGesture(
        buttons[walkRight].absoluteCenter.toOffset(),
      );
      await advance(tester, 15);
      await walk.up();
      await tester.tapAt(buttons[reset].absoluteCenter.toOffset());
      await advance(tester, 5);
      expect(
        player.body.position.x,
        closeTo(game.checkpoints.activeCheckpoint.x, 0.02),
      );
      await tester.tapAt(buttons[debugToggle].absoluteCenter.toOffset());
      await advance(tester, 5);
      expect(game.debugVisible || player.debugEnabled, isFalse);
    },
  );
}
