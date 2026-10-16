import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/ground.dart';
import 'package:umbra/entities/physics_props.dart';
import 'package:umbra/physics/water.dart';

void main() {
  Future<Forge2DGame> boot(WidgetTester tester) async {
    final game = Forge2DGame(gravity: GameConfig.gravity);
    await tester.pumpWidget(GameWidget(game: game));
    for (var i = 0; i < 20 && !game.isLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    game.pauseEngine();
    addTearDown(() {
      if (game.world.physicsWorld.isValid) game.world.physicsWorld.destroy();
    });
    return game;
  }

  Future<void> settle(WidgetTester tester, Forge2DGame game) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
      game.update(1 / 120);
    }
  }

  void step(Forge2DGame game, double seconds) {
    for (var i = 0; i < (seconds * 120).round(); i++) {
      game.update(1 / 120);
    }
  }

  testWidgets('a light crate floats as deep as its density says; a heavy '
      'one sinks', (tester) async {
    final game = await boot(tester);
    final water = WaterBody(left: 0, right: 10, surface: 5, bottom: 9);
    // 1 m x 1 m crates: 15 kg is a quarter the water's 60, 90 kg is more.
    final light = PhysicsCrate(
      position: Vector2(3, 4),
      size: Vector2(1, 1),
      massKg: 15,
    );
    final heavy = PhysicsCrate(
      position: Vector2(7, 4),
      size: Vector2(1, 1),
      massKg: 90,
    );
    await game.world.addAll([
      Ground.slab(left: -1, right: 11, top: 9, thickness: 1),
      water,
      light,
      heavy,
    ]);
    await settle(tester, game);
    step(game, 8);
    // A quarter under water: its bottom 0.25 m below the surface.
    final double bottom = light.body.position.y + 0.5;
    expect(bottom - water.level, closeTo(0.25, 0.06));
    expect(light.body.linearVelocity.length, lessThan(0.05));
    // The heavy one is on the floor.
    expect(heavy.body.position.y, closeTo(8.5, 0.05));
  });

  testWidgets('a floating crate turned on its corner rights itself, and a '
      'current carries it along', (tester) async {
    final game = await boot(tester);
    final water = WaterBody(
      left: 0,
      right: 30,
      surface: 5,
      bottom: 9,
      current: 0.8,
    );
    final crate = PhysicsCrate(
      position: Vector2(4, 4.8),
      size: Vector2(1.6, 0.6),
      massKg: 18,
    );
    await game.world.addAll([water, crate]);
    await settle(tester, game);
    crate.body.setTransform(crate.body.position, Rot.fromAngle(1.2));
    step(game, 6);
    final double angle = crate.body.angle % 3.14159;
    expect(
      angle < 0.15 || angle > 3.0,
      isTrue,
      reason: 'lies flat on the water (angle ${crate.body.angle})',
    );
    expect(crate.body.position.x, greaterThan(6.5));
    expect(crate.body.linearVelocity.x, closeTo(0.8, 0.25));
  });

  testWidgets('a load pushes a floating crate deeper', (tester) async {
    final game = await boot(tester);
    final water = WaterBody(left: 0, right: 10, surface: 5, bottom: 9);
    final raft = PhysicsCrate(
      position: Vector2(5, 4.7),
      size: Vector2(2.4, 0.5),
      massKg: 15,
    );
    await game.world.addAll([water, raft]);
    await settle(tester, game);
    step(game, 4);
    final double empty = raft.body.position.y;
    final load = PhysicsCrate(
      position: Vector2(5, 4.0),
      size: Vector2(0.6, 0.6),
      massKg: 30,
    );
    await game.world.add(load);
    await settle(tester, game);
    step(game, 6);
    expect(raft.body.position.y, greaterThan(empty + 0.15));
    // Still afloat: 45 kg on 1.2 m² of 60 kg/m² water.
    expect(raft.body.position.y - 0.25, lessThan(water.level));
  });
}
