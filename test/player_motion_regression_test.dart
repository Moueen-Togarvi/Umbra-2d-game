import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/ground.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/entities/physics_props.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/game/umbra_game.dart';
import 'package:umbra/world/level.dart';

void main() {
  Future<(UmbraGame, Player)> boot(WidgetTester tester) async {
    final game = UmbraGame();
    await tester.pumpWidget(GameWidget(game: game));
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
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Drive exact display-frame durations without Flutter's millisecond clock.
    game.pauseEngine();
    addTearDown(() {
      game.pauseEngine();
      if (game.world.physicsWorld.isValid) {
        game.world.physicsWorld.destroy();
      }
    });
    return (game, game.world.descendants().whereType<Player>().single);
  }

  void advance(UmbraGame game, double seconds, {int fps = 60}) {
    for (var i = 0; i < (seconds * fps).round(); i++) {
      game.update(1 / fps);
    }
  }

  testWidgets('travel, braking and jump arc agree at 30, 60 and 120 fps', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    final distances = <double>[];
    final apexes = <double>[];

    for (final fps in const [30, 60, 120]) {
      player.teleportTo(GameConfig.playerSpawn);
      advance(game, 0.2, fps: fps);
      final startX = player.body.position.x;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      advance(game, 0.6, fps: fps);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      advance(game, 0.3, fps: fps);
      distances.add(player.body.position.x - startX);
      expect(player.body.linearVelocity.x.abs(), lessThan(0.05));

      player.teleportTo(GameConfig.playerSpawn);
      advance(game, 0.2, fps: fps);
      final restingY = player.body.position.y;
      var highestY = restingY;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      for (var frame = 0; frame < fps; frame++) {
        game.update(1 / fps);
        highestY = math.min(highestY, player.body.position.y);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      apexes.add(restingY - highestY);
      expect(player.isOnGround, isTrue);
      expect(
        player.body.position.y + GameConfig.playerHeight / 2,
        closeTo(restingY + GameConfig.playerHeight / 2, 0.03),
        reason: 'ground support must settle onto the floor after landing',
      );
    }

    expect(
      distances.reduce(math.max) - distances.reduce(math.min),
      lessThan(0.025),
    );
    expect(apexes.reduce(math.max) - apexes.reduce(math.min), lessThan(0.035));
    expect(apexes.first, closeTo(GameConfig.jumpApexMeters, 0.08));
  });

  testWidgets('an edge jump works briefly after departure, then expires', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    final terrain = game.world.descendants().whereType<Level>().single.terrain;

    Future<void> walkOffEdge() async {
      player.teleportTo(
        Vector2(13, terrain.heightAt(13)! - GameConfig.playerHeight / 2),
      );
      advance(game, 0.2, fps: 120);
      expect(player.isOnGround, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      for (var tick = 0; tick < 120 && player.isOnGround; tick++) {
        game.update(1 / 120);
      }
      expect(player.isOnGround, isFalse);
      expect(player.body.position.x, greaterThan(GameConfig.gapStartX));
    }

    await walkOffEdge();
    advance(game, GameConfig.coyoteTimeSeconds / 3, fps: 120);
    final nearEdgeY = player.body.position.y;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    advance(game, 0.0833, fps: 120);
    expect(player.body.linearVelocity.y, lessThan(-1));
    expect(player.body.position.y, lessThan(nearEdgeY - 0.15));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);

    await walkOffEdge();
    advance(game, GameConfig.coyoteTimeSeconds + 0.05, fps: 120);
    final lateY = player.body.position.y;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    advance(game, 0.05, fps: 120);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    expect(player.isOnGround, isFalse);
    expect(player.body.linearVelocity.y, greaterThan(0));
    expect(player.body.position.y, greaterThan(lateY));
  });

  testWidgets(
    'a recent landing press jumps, but an old airborne press expires',
    (tester) async {
      final (game, player) = await boot(tester);
      final spawn = GameConfig.playerSpawn;
      player.teleportTo(Vector2(spawn.x, spawn.y - 0.7));
      for (var tick = 0; tick < 120; tick++) {
        final gap =
            GameConfig.floorSurfaceY -
            (player.body.position.y + GameConfig.playerHeight / 2);
        if (gap < 0.17) break;
        game.update(1 / 120);
      }
      expect(player.isOnGround, isFalse);
      expect(player.body.linearVelocity.y, greaterThan(0));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      game.update(1 / 120);
      expect(
        player.body.linearVelocity.y,
        greaterThan(0),
        reason: 'a buffered press must wait for solid support',
      );

      var bounced = false;
      for (var tick = 0; tick < 30; tick++) {
        game.update(1 / 120);
        if (player.body.linearVelocity.y < -1) {
          bounced = true;
          break;
        }
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(
        bounced,
        isTrue,
        reason: 'landing should consume the recent press',
      );

      player.teleportTo(Vector2(spawn.x, spawn.y - 2));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      var jumpedFromOldPress = false;
      for (var tick = 0; tick < 80; tick++) {
        game.update(1 / 120);
        if (player.body.linearVelocity.y < -1) jumpedFromOldPress = true;
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(jumpedFromOldPress, isFalse);
      expect(player.isOnGround, isTrue);
      expect(
        player.body.position.y + GameConfig.playerHeight / 2,
        closeTo(GameConfig.floorSurfaceY, 0.03),
      );
    },
  );

  testWidgets('airborne release preserves momentum and reversal is limited', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    advance(game, 0.3, fps: 120);
    final takeoffSpeed = player.body.linearVelocity.x;
    expect(
      takeoffSpeed,
      greaterThan(GameConfig.moveSpeedMetersPerSecond * 0.9),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    advance(game, GameConfig.jumpAnticipationSeconds + 0.017, fps: 120);
    expect(player.isOnGround, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    advance(game, 0.1, fps: 120);
    expect(
      player.body.linearVelocity.x,
      closeTo(takeoffSpeed, 0.05),
      reason: 'releasing the run in the air should not brake the jump',
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    advance(game, 0.15, fps: 120);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(player.isOnGround, isFalse);
    expect(player.body.linearVelocity.x, greaterThan(takeoffSpeed * 0.7));
    expect(
      player.facing,
      greaterThan(0),
      reason: 'the character should face its actual airborne travel',
    );
  });

  testWidgets(
    'touching an airborne wall does not ground or launch the player',
    (tester) async {
      final (game, player) = await boot(tester);
      final wall = Ground.slab(
        left: 4.4,
        right: 4.8,
        top: 1,
        thickness: 4.8,
        style: GroundStyle.wall,
      );
      await game.world.add(wall);
      advance(game, 0.05);
      player.teleportTo(Vector2(4.19, 3.5));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      advance(game, 0.1);
      expect(player.isOnGround, isFalse);

      final yBeforeJump = player.body.position.y;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      advance(game, 0.1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      expect(player.body.position.y, greaterThan(yBeforeJump));
      expect(player.body.linearVelocity.y, greaterThan(0));
      expect(player.isOnGround, isFalse);
    },
  );

  testWidgets('walking on a flat log stays level above a sloping hill', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    const top = 4.8;
    final log = Ground.slab(
      left: 32.6,
      right: 36.3,
      top: top,
      thickness: 0.4,
      style: GroundStyle.log,
    );
    await game.world.add(log);
    advance(game, 0.05);
    player.teleportTo(Vector2(33, top - GameConfig.playerHeight / 2));
    advance(game, 0.2);
    expect(player.isOnGround, isTrue);

    final restingY = player.body.position.y;
    var largestHeightError = 0.0;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    for (var frame = 0; frame < 54; frame++) {
      game.update(1 / 60);
      largestHeightError = math.max(
        largestHeightError,
        (player.body.position.y - restingY).abs(),
      );
      expect(player.isOnGround, isTrue, reason: 'lost flat log support');
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    expect(player.body.position.x, greaterThan(35.3));
    expect(largestHeightError, lessThan(0.025));
  });

  testWidgets('running, crate jumps and ledge climbing traverse all six areas', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    final level = game.world.descendants().whereType<Level>().single;
    final jumpAt = <double>[
      for (var i = 0; i + 1 < level.terrain.segments.length; i++)
        level.terrain.segments[i].right - 0.32,
      for (final log in GameConfig.logs) log.first - 0.55,
      for (final rock in GameConfig.rocks) rock.first - 0.55,
      for (final crate in game.world.descendants().whereType<PhysicsCrate>())
        crate.body.position.x - crate.size.x / 2 - 1.25,
      72.1,
    ]..sort();
    var nextJump = 0;
    var jumpHeld = false;
    var hasLeftGround = false;
    var reachedX = player.body.position.x;
    var climbedLedge = false;
    final platformJumps = <MovingPlatform>{};
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);

    for (
      var frame = 0;
      frame < 60 * 40 && player.body.position.x < GameConfig.levelWidth - 0.6;
      frame++
    ) {
      if (jumpHeld) {
        if (!player.isOnGround) hasLeftGround = true;
        if ((hasLeftGround && player.isOnGround) ||
            player.interactions.controlsMotion) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
          jumpHeld = false;
        }
      }
      // The ledge is caught and climbed by itself, as in LIMBO.
      if (player.interactions.mode == InteractionMode.climbing) {
        climbedLedge = true;
      }
      if (!jumpHeld &&
          nextJump < jumpAt.length &&
          player.body.position.x >= jumpAt[nextJump] &&
          player.isOnGround) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        jumpHeld = true;
        hasLeftGround = false;
        nextJump++;
      }
      if (!jumpHeld && player.isOnGround) {
        for (final platform
            in game.world.descendants().whereType<MovingPlatform>()) {
          final left = platform.body.position.x - platform.size.x / 2;
          final lift =
              player.body.position.y +
              GameConfig.playerHeight / 2 -
              (platform.body.position.y - platform.size.y / 2);
          if (!platformJumps.contains(platform) &&
              player.body.position.x >= left - 1.2 &&
              player.body.position.x < left &&
              lift > 0.3 &&
              lift < 1.2) {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
            jumpHeld = true;
            hasLeftGround = false;
            platformJumps.add(platform);
            break;
          }
        }
      }

      game.update(1 / 60);

      expect(player.isDead, isFalse, reason: 'died near x=$reachedX');
      expect(
        player.body.position.x,
        greaterThanOrEqualTo(reachedX - 0.2),
        reason: 'respawn near x=$reachedX after obstacle $nextJump',
      );
      reachedX = math.max(reachedX, player.body.position.x);
    }
    if (jumpHeld) await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    expect(
      nextJump,
      jumpAt.length,
      reason:
          'not all obstacles were reached: x=${player.body.position.x} y=${player.body.position.y} state=${player.state} mode=${player.interactions.mode} grounded=${player.isOnGround}',
    );
    expect(player.body.position.x, greaterThan(GameConfig.levelWidth - 0.8));
    expect(game.checkpoints.activeCheckpoint.x, greaterThan(80));
    expect(
      climbedLedge,
      isTrue,
      reason: 'the route must use the ledge interaction',
    );
  });
}
