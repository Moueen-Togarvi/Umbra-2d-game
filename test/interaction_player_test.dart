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
    'pushing, the arms hold the crate off; a heavy one makes him strain',
    (tester) async {
      final leans = <double>[];
      for (final mass in [8.0, 35.0]) {
        final (game, player, crate) = await _flatFixture(tester, mass);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
        _advance(game, 60);
        var lean = 0.0;
        var reaches = 0.0;
        var samples = 0;
        for (var tick = 0; tick < 60; tick++) {
          game.update(_step);
          expect(player.interactions.mode, InteractionMode.pushing);
          final gap =
              (crate.body.position.x - crate.size.x / 2) -
              (player.body.position.x + GameConfig.playerWidth / 2);
          expect(gap, greaterThan(0.1), reason: 'held at arm\'s length');
          final pose = player.rigPoseWorld;
          final reach =
              (pose[RigJoint.frontHand] - pose[RigJoint.frontShoulder]).length;
          final spine = pose[RigJoint.neck] - pose[RigJoint.pelvis];
          reaches += reach;
          expect(
            crate.body.angle.abs(),
            lessThan(0.05),
            reason: 'a steady push on the flat does not tip it',
          );
          lean += spine.x / -spine.y;
          samples++;
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
        // The arms reach out nearly straight to the crate.
        expect(
          reaches / samples,
          greaterThan(CharacterRig.armReach * GameConfig.playerHeight * 0.85),
          reason: '$mass kg',
        );
        leans.add(lean / samples);
      }
      expect(leans.first, greaterThan(0.05), reason: 'leans into the push');
      expect(leans.last, greaterThan(leans.first + 0.08));
    },
  );

  testWidgets('a crate pushed off a ledge tips over and comes to rest', (
    tester,
  ) async {
    final (game, player) = await _boot(tester);
    // A high shelf ending at x = 35, with a floor 1.6 m below it.
    final shelf = Ground.slab(
      left: 32,
      right: 35,
      top: 4,
      thickness: 0.4,
      style: GroundStyle.wall,
    );
    final floor = Ground.slab(
      left: 30,
      right: 42,
      top: 5.6,
      thickness: 0.4,
      style: GroundStyle.wall,
    );
    final crate = PhysicsCrate(
      position: Vector2(34.8, 4 - 0.72 / 2),
      size: Vector2(0.75, 0.72),
      massKg: 8,
    );
    await game.world.addAll([shelf, floor, crate]);
    player.teleportTo(Vector2(38, 5.6 - GameConfig.playerHeight / 2));
    _advance(game, 10);
    expect(crate.body.angle.abs(), lessThan(0.01));
    // Shoved over the edge.
    crate.body.linearVelocity = Vector2(2, 0);
    var turned = 0.0;
    for (var tick = 0; tick < 360; tick++) {
      game.update(_step);
      turned = turned < crate.body.angle.abs()
          ? crate.body.angle.abs()
          : turned;
    }
    expect(
      turned,
      greaterThan(0.5),
      reason: "it tumbles off the edge ${crate.body.position}",
    );
    expect(crate.body.position.y, greaterThan(5));
    expect(crate.body.linearVelocity.length, lessThan(0.05));
    expect(crate.body.angularVelocity.abs(), lessThan(0.05));
  });

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
      _advance(game, 240);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
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
      var physicallyPushing = false;
      for (var tick = 0; tick < 120 * 30; tick++) {
        game.update(_step);
        physicallyPushing |=
            player.interactions.mode == InteractionMode.pushing;
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      expect(physicallyPushing, isTrue);
      expect(
        crate.body.position.x - start,
        greaterThan(0.2),
        reason:
            'the heavy scene crate should move, despite its uphill resistance',
      );
    },
  );

  testWidgets('a rope is caught part way down and climbed up and down', (
    tester,
  ) async {
    final (game, player) = await _boot(tester);
    final rope = SwingRope(anchor: Vector2(34, -0.5), length: 3.6);
    await game.world.add(rope);
    _advance(game, 10);
    // Jumping at the middle of the rope, not its end.
    player.teleportTo(Vector2(33.92, 1.4 + GameConfig.playerHeight * 0.3));
    _advance(game, 2);
    expect(player.interactions.mode, InteractionMode.swinging);
    expect(rope.holdLength, inInclusiveRange(1.4, 2.5));
    _advance(game, 60);
    // The rope hangs on below his hands, and his feet clamp it.
    expect(rope.length - rope.holdLength, greaterThan(1));
    expect(player.interactions.ropeFeet, isNotNull);

    final held = rope.holdLength;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    _advance(game, 120);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    expect(
      player.interactions.mode,
      InteractionMode.swinging,
      reason: 'W climbs',
    );
    expect(rope.holdLength, lessThan(held - 0.5));
    // He went up with the hold.
    expect((player.body.position - rope.grip).length, lessThan(0.6));
    final high = rope.holdLength;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    _advance(game, 60);
    expect(
      player.interactions.mode,
      InteractionMode.swinging,
      reason: 'S climbs down',
    );
    expect(rope.holdLength, greaterThan(high + 0.6));
    // Down at the bottom of the rope, held a moment, lets go.
    _advance(game, 240);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    expect(player.interactions.mode, InteractionMode.none);
    expect(rope.holdLength, rope.length);
  });

  testWidgets(
    'a rope is caught by itself, jump kicks off it, and it is caught again later',
    (tester) async {
      final (game, player) = await _boot(tester);
      final rope = SwingRope(anchor: Vector2(34, 1), length: 2);
      await game.world.add(rope);
      _advance(game, 10);
      player.teleportTo(rope.grip + Vector2(0, GameConfig.playerHeight * 0.42));
      _advance(game, 2);
      expect(player.interactions.mode, InteractionMode.swinging);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      _advance(game, 1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(player.velocity.y, lessThan(-2), reason: 'kicked off upwards');
      for (var tick = 0; tick < 20; tick++) {
        game.update(_step);
        expect(
          player.interactions.mode,
          InteractionMode.none,
          reason: 'the rope just let go must not be caught straight back',
        );
      }
      _advance(game, 60);
      player.teleportTo(rope.grip + Vector2(0, GameConfig.playerHeight * 0.42));
      _advance(game, 2);
      expect(player.interactions.mode, InteractionMode.swinging);
    },
  );
}
