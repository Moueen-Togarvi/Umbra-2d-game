import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/character/character_rig.dart';
import 'package:umbra/character/character_state.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/ground.dart';
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
    final player = game.world.descendants().whereType<Player>().single;
    for (var i = 0; i < 60; i++) {
      game.update(1 / 120);
    }
    return (game, player);
  }

  void advance(UmbraGame game, double seconds) {
    for (var i = 0; i < (seconds * 120).round(); i++) {
      game.update(1 / 120);
    }
  }

  const double h = GameConfig.playerHeight;
  double lowTop(Player p) =>
      p.body.position.y + h / 2 - h * GameConfig.lowHeightRatio;

  testWidgets('sit held still: he sits on the ground, on the short capsule, '
      'and stands again when it is let go', (tester) async {
    final (game, player) = await boot(tester);
    final double startX = player.body.position.x;
    final double startY = player.body.position.y;
    game.intent.setKeyboardState(sit: true);
    var deepestPelvis = -double.infinity;
    for (var i = 0; i < 240; i++) {
      game.update(1 / 120);
      deepestPelvis = math.max(
        deepestPelvis,
        player.rigPoseWorld.joints[RigJoint.pelvis]!.y,
      );
    }
    expect(player.isLow, isTrue);
    expect(player.state, CharacterState.sitting);
    expect(player.body.mass, closeTo(GameConfig.playerMassKilograms, 0.01));
    // Soles where they were; no drift along the floor.
    expect(player.body.position.y, closeTo(startY, 0.03));
    expect((player.body.position.x - startX).abs(), lessThan(0.05));
    // The seat comes right down, and the drawn head stays under the top of
    // the short capsule.
    final pose = player.rigPoseWorld;
    final double pelvis = pose.joints[RigJoint.pelvis]!.y;
    expect(startY + h / 2 - pelvis, lessThan(0.16));
    final double headTop =
        pose.joints[RigJoint.head]!.y - CharacterRig.headRadius * h;
    expect(headTop, greaterThan(lowTop(player) - 0.05));
    // Calm: down onto the seat without sinking past it and bobbing back.
    expect(deepestPelvis - pelvis, lessThan(0.01));

    game.intent.setKeyboardState(sit: false);
    advance(game, 1.2);
    expect(player.isLow, isFalse);
    expect(player.state, CharacterState.idle);
    expect(player.body.position.y, closeTo(startY, 0.03));
  });

  testWidgets('sit held while walking: he crouches and creeps', (tester) async {
    final (game, player) = await boot(tester);
    game.intent.setKeyboardState(sit: true, axis: 1);
    advance(game, 1.0);
    expect(player.isLow, isTrue);
    expect(player.state, CharacterState.crouching);
    expect(
      player.velocity.x,
      closeTo(GameConfig.crouchSpeedMetersPerSecond, 0.15),
    );
    game.intent.setKeyboardState(sit: false);
    advance(game, 0.6);
    expect(player.isLow, isFalse);
    expect(
      player.velocity.x,
      closeTo(GameConfig.moveSpeedMetersPerSecond, 0.2),
    );
    game.intent.setKeyboardState(axis: 0);
  });

  testWidgets('under a low beam he stays down until he is out from under it', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    game.intent.setKeyboardState(sit: true);
    advance(game, 1.0);
    expect(player.isLow, isTrue);
    final double x = player.body.position.x;
    // A beam whose underside is between his low and his full height.
    final double floor = player.body.position.y + h / 2;
    await game.world.add(
      Ground.slab(
        left: x - 1.5,
        right: x + 0.6,
        top: floor - 1.05,
        thickness: 0.25,
        style: GroundStyle.wall,
      ),
    );
    advance(game, 0.1);
    game.intent.setKeyboardState(sit: false);
    advance(game, 0.8);
    expect(player.isLow, isTrue, reason: 'no room to stand');
    // Nor to jump.
    game.intent.requestJump();
    advance(game, 0.3);
    expect(player.isOnGround, isTrue);
    expect(player.isLow, isTrue);
    // Out from under it, he stands.
    game.intent.setKeyboardState(axis: 1);
    advance(game, 2.0);
    expect(player.body.position.x, greaterThan(x + 0.9));
    expect(player.isLow, isFalse);
    game.intent.setKeyboardState(axis: 0);
  });

  testWidgets('jump from low stands and jumps; sit does nothing in the air', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    game.intent.setKeyboardState(sit: true);
    advance(game, 0.8);
    expect(player.isLow, isTrue);
    game.intent.requestJump();
    advance(game, 0.15);
    expect(player.isOnGround, isFalse);
    expect(player.isLow, isFalse);
    // Still holding sit in the air: no crouch until he lands.
    advance(game, 0.2);
    expect(player.isLow, isFalse);
    advance(game, 1.0);
    expect(player.isOnGround, isTrue);
    expect(player.isLow, isTrue);
    game.intent.setKeyboardState(sit: false);
    advance(game, 0.6);
    expect(player.isLow, isFalse);
  });
}
