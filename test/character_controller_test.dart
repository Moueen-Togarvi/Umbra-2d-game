import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/character/character_state.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/ground.dart';
import 'package:umbra/entities/physics_props.dart';
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

  void advance(UmbraGame game, double seconds) {
    for (var i = 0; i < (seconds * 120).round(); i++) {
      game.update(1 / 120);
    }
  }

  testWidgets(
    'walk, run and crouch select real speeds and reversal has inertia',
    (tester) async {
      final (game, player) = await boot(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      advance(game, 0.2);
      expect(
        player.velocity.x,
        closeTo(GameConfig.walkSpeedMetersPerSecond, 0.1),
      );
      expect(player.state, CharacterState.walking);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      advance(game, 0.3);
      expect(
        player.velocity.x,
        closeTo(GameConfig.moveSpeedMetersPerSecond, 0.1),
      );
      expect(player.state, CharacterState.running);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      advance(game, 1 / 120);
      expect(player.velocity.x, greaterThan(0));
      expect(player.state, CharacterState.turning);
      advance(game, 0.5);
      expect(player.velocity.x, lessThan(-2));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      advance(game, 0.25);
      expect(player.isCrouching, isTrue);
      expect(
        player.velocity.x.abs(),
        closeTo(GameConfig.crouchSpeedMetersPerSecond, 0.1),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    },
  );

  testWidgets(
    'crouch shrinks collision and refuses to stand inside a ceiling',
    (tester) async {
      final (game, player) = await boot(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      advance(game, 0.1);
      final ceiling = Ground.slab(
        left: 1,
        right: 3,
        top: 6.20,
        thickness: 0.4,
        style: GroundStyle.wall,
      );
      await game.world.add(ceiling);
      advance(game, 0.1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      advance(game, 0.2);
      expect(player.isCrouching, isTrue);
      expect(
        player.body.position.y + GameConfig.playerHeight / 2,
        closeTo(GameConfig.floorSurfaceY, 0.03),
      );
      ceiling.removeFromParent();
      advance(game, 0.2);
      expect(player.isCrouching, isFalse);
    },
  );

  testWidgets(
    'ceiling collision cuts ascent without penetration or double jump',
    (tester) async {
      final (game, player) = await boot(tester);
      final ceiling = Ground.slab(
        left: 1,
        right: 4,
        top: 5.45,
        thickness: 0.25,
        style: GroundStyle.wall,
      );
      await game.world.add(ceiling);
      advance(game, 0.05);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      var minimumHead = double.infinity;
      for (var i = 0; i < 60; i++) {
        game.update(1 / 120);
        minimumHead = math.min(
          minimumHead,
          player.body.position.y - GameConfig.playerHeight / 2,
        );
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(minimumHead, greaterThanOrEqualTo(5.68));
      advance(game, 0.4);
      expect(player.isOnGround, isTrue);
    },
  );

  for (final vertical in [false, true]) {
    testWidgets(
      '${vertical ? 'vertical' : 'horizontal'} platform carries idle player and jump inherits velocity',
      (tester) async {
        final (game, player) = await boot(tester);
        final platform = MovingPlatform(
          from: Vector2(3, 4.8),
          to: vertical ? Vector2(3, 3.2) : Vector2(7, 4.8),
          size: Vector2(2, 0.25),
          speed: 0.6,
        );
        await game.world.add(platform);
        advance(game, 0.05);
        player.teleportTo(
          platform.body.position -
              Vector2(0, 0.125 + GameConfig.playerHeight / 2),
        );
        advance(game, 0.3);
        final offset = player.body.position - platform.body.position;
        advance(game, 1);
        expect(player.isOnGround, isTrue);
        expect(
          (player.body.position - platform.body.position - offset).length,
          lessThan(0.05),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        advance(game, 0.05);
        expect(player.isOnGround, isFalse);
        if (!vertical) expect(player.velocity.x, closeTo(0.6, 0.04));
        expect(player.velocity.y, lessThan(-5));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      },
    );
  }

  testWidgets(
    'planted feet keep world anchors during a steady walking stance',
    (tester) async {
      final (game, player) = await boot(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      advance(game, 0.3);
      var stationarySamples = 0;
      var previous = player.rigFootTargets;
      for (var i = 0; i < 50; i++) {
        game.update(1 / 120);
        final current = player.rigFootTargets;
        if ((current[0] - previous[0]).length < 0.002 ||
            (current[1] - previous[1]).length < 0.002) {
          stationarySamples++;
        }
        previous = current;
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      expect(stationarySamples, greaterThan(43));
    },
  );

  testWidgets(
    'all presets share controller; knockdown disables capsule and recovers',
    (tester) async {
      final (game, player) = await boot(tester);
      expect(player.presetIndex, 2);
      for (var i = 0; i < 3; i++) {
        player.selectPreset(i);
        advance(game, 0.1);
        expect(player.presetIndex, i);
        expect(player.isOnGround, isTrue);
        expect(player.body.mass, closeTo(GameConfig.playerMassKilograms, 0.01));
      }
      final before = player.body.position.clone();
      player.knockDown();
      expect(player.isRagdoll, isTrue);
      expect(player.body.isEnabled, isFalse);
      expect((player.cameraPosition - before).length, lessThan(0.25));
      for (
        var i = 0;
        i < 120 * 10 && (player.isRagdoll || !player.body.isEnabled);
        i++
      ) {
        game.update(1 / 120);
      }
      expect(player.isRagdoll, isFalse);
      expect(player.body.isEnabled, isTrue);
      advance(game, 0.3);
      expect(player.isOnGround, isTrue);
      expect(player.state, CharacterState.idle);
    },
  );

  testWidgets(
    'ragdoll hazard contact cleans up limbs and restores the checkpoint',
    (tester) async {
      final (game, player) = await boot(tester);
      player.teleportTo(
        Vector2((GameConfig.gapStartX + GameConfig.gapEndX) / 2, 2),
      );
      player.knockDown();
      advance(game, 3);
      expect(player.isRagdoll, isFalse);
      expect(player.body.isEnabled, isTrue);
      expect(
        player.body.position.x,
        closeTo(game.checkpoints.activeCheckpoint.x, 0.05),
      );
      expect(player.isOnGround, isTrue);
    },
  );
}
