import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/character/character_rig.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/ground.dart';
import 'package:umbra/entities/physics_props.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/game/umbra_game.dart';
import 'package:umbra/world/level.dart';

const _step = 1 / 120;

Future<(UmbraGame, Player)> _boot(WidgetTester tester) async {
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
  game.pauseEngine();
  addTearDown(() {
    game.pauseEngine();
    if (game.world.physicsWorld.isValid) game.world.physicsWorld.destroy();
  });
  return (game, game.world.descendants().whereType<Player>().single);
}

void _advance(UmbraGame game, int ticks) {
  for (var i = 0; i < ticks; i++) {
    game.update(_step);
  }
}

Future<(UmbraGame, Player, PhysicsCrate)> _flatFixture(
  WidgetTester tester,
  double mass,
) async {
  final (game, player) = await _boot(tester);
  final floor = Ground.slab(
    left: 32,
    right: 45,
    top: 4,
    thickness: 0.4,
    style: GroundStyle.wall,
  );
  final crate = PhysicsCrate(
    position: Vector2(34, 4 - 0.72 / 2),
    size: Vector2(0.75, 0.72),
    massKg: mass,
    friction: mass < 20 ? 0.25 : 0.15,
  );
  await game.world.addAll([floor, crate]);
  _advance(game, 10);
  // A moderate-friction flat fixture isolates mass from the terrain slope.
  for (final shape in floor.body.shapes) {
    shape.friction = 0.4;
  }
  player.teleportTo(Vector2(33.35, 4 - GameConfig.playerHeight / 2));
  _advance(game, 24);
  expect(player.isOnGround, isTrue);
  return (game, player, crate);
}

void _expectHandsAtGrip(Player player) {
  final grip = player.interactions.gripWorld!;
  final pose = player.rigPoseWorld;
  expect((pose[RigJoint.frontHand] - grip).length, lessThan(0.035));
  expect(
    (pose[RigJoint.backHand] - grip - Vector2(0, 0.02)).length,
    lessThan(0.035),
    reason:
        'body=${player.body.position} grip=$grip frontShoulder=${pose[RigJoint.frontShoulder]} backShoulder=${pose[RigJoint.backShoulder]} backHand=${pose[RigJoint.backHand]} state=${player.state}',
  );
}

void main() {
  testWidgets(
    'actual player input pushes both masses with different resistance',
    (tester) async {
      final distances = <double>[];
      for (final mass in [8.0, 35.0]) {
        final (game, player, crate) = await _flatFixture(tester, mass);
        final start = crate.body.position.x;
        var pushingTicks = 0;
        var verifiedHands = false;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        for (var tick = 0; tick < 120; tick++) {
          game.update(_step);
          if (player.interactions.mode == InteractionMode.pushing) {
            pushingTicks++;
            if (pushingTicks > 15) {
              _expectHandsAtGrip(player);
              verifiedHands = true;
            }
          } else {
            pushingTicks = 0;
          }
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(verifiedHands, isTrue);
        final distance = crate.body.position.x - start;
        expect(
          distance,
          greaterThan(0.1),
          reason: '$mass kg crate did not move',
        );
        distances.add(distance);
      }
      expect(distances.first, greaterThan(distances.last + 0.25));
    },
  );

  testWidgets(
    'actual E and backward movement pull both masses with synchronized hands',
    (tester) async {
      final distances = <double>[];
      for (final mass in [8.0, 35.0]) {
        final (game, player, crate) = await _flatFixture(tester, mass);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
        _advance(game, 18);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
        _advance(game, 20);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
        _advance(game, 12);
        expect(player.interactions.mode, InteractionMode.pulling);
        final start = crate.body.position.x;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
        for (var tick = 0; tick < 120; tick++) {
          game.update(_step);
          expect(
            player.interactions.mode,
            InteractionMode.pulling,
            reason: '$mass kg grip was lost at tick $tick',
          );
          if (tick > 15) _expectHandsAtGrip(player);
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
        _advance(game, 1);
        expect(player.interactions.mode, InteractionMode.none);
        expect(player.interactions.gripWorld, isNull);
        final distance = start - crate.body.position.x;
        expect(
          distance,
          greaterThan(0.05),
          reason: '$mass kg crate did not pull',
        );
        distances.add(distance);
      }
      expect(distances.first, greaterThan(distances.last + 0.25));
    },
  );

  testWidgets(
    'actual controller cannot run through a crate blocked by a wall',
    (tester) async {
      final (game, player, crate) = await _flatFixture(tester, 8);
      final right = crate.body.position.x + crate.size.x / 2;
      await game.world.add(
        Ground.slab(
          left: right,
          right: right + 1,
          top: 2.6,
          thickness: 1.4,
          style: GroundStyle.wall,
        ),
      );
      _advance(game, 10);
      final start = crate.body.position.x;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      _advance(game, 240);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(player.interactions.mode, InteractionMode.pushing);
      expect(crate.body.position.x, closeTo(start, 0.035));
      expect(
        player.body.position.x + GameConfig.playerWidth / 2,
        lessThan(crate.body.position.x - crate.size.x / 2 + 0.035),
      );
      _expectHandsAtGrip(player);
    },
  );

  testWidgets(
    'the actual heavy scene crate moves uphill under sustained pushing',
    (tester) async {
      final (game, player) = await _boot(tester);
      final terrain = game.world
          .descendants()
          .whereType<Level>()
          .single
          .terrain;
      final crate = game.world
          .descendants()
          .whereType<PhysicsCrate>()
          .singleWhere((crate) => crate.massKg >= 25);
      final start = crate.body.position.x;
      final x = start - crate.size.x / 2 - GameConfig.playerWidth / 2 - 0.03;
      player.teleportTo(
        Vector2(x, terrain.heightAt(x)! - GameConfig.playerHeight / 2),
      );
      _advance(game, 24);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      var physicallyPushing = false;
      for (var tick = 0; tick < 120 * 30; tick++) {
        game.update(_step);
        physicallyPushing |=
            player.interactions.mode == InteractionMode.pushing;
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(physicallyPushing, isTrue);
      expect(
        crate.body.position.x - start,
        greaterThan(0.2),
        reason:
            'the heavy scene crate should move, despite its uphill resistance',
      );
    },
  );

  testWidgets(
    'Space detaches a rope until held E is released and pressed again',
    (tester) async {
      final (game, player) = await _boot(tester);
      final rope = SwingRope(anchor: Vector2(34, 1), length: 2);
      await game.world.add(rope);
      _advance(game, 10);
      player.teleportTo(rope.grip + Vector2(0, GameConfig.playerHeight * 0.42));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      _advance(game, 12);
      expect(player.interactions.mode, InteractionMode.swinging);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      for (var tick = 0; tick < 20; tick++) {
        game.update(_step);
        expect(
          player.interactions.mode,
          InteractionMode.none,
          reason:
              'holding E must not reattach after a deliberate Space release',
        );
        expect(player.interactions.controlsMotion, isFalse);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      _advance(game, 1);
      player.teleportTo(rope.grip + Vector2(0, GameConfig.playerHeight * 0.42));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      _advance(game, 2);
      expect(
        player.interactions.mode,
        InteractionMode.swinging,
        reason: 'releasing E should rearm the next intentional grab',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      _advance(game, 1);
    },
  );
}
