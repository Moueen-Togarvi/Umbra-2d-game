import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/castle_props.dart';
import 'package:umbra/entities/clock_props.dart';
import 'package:umbra/entities/physics_props.dart';

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
      game.update(1 / 60);
    }
  }

  testWidgets('the pendulum keeps its swing, with a load on its platform, and '
      'the platform stays level', (tester) async {
    final game = await boot(tester);
    final pendulum = Pendulum(pivot: Vector2(10, 1), length: 6);
    await game.world.add(pendulum);
    await settle(tester, game);
    final load = PhysicsCrate(
      position: pendulum.plateTop - Vector2(0, 0.31),
      size: Vector2(0.6, 0.6),
      massKg: 40,
    );
    await game.world.add(load);
    await settle(tester, game);
    double widest = 0, tilt = 0;
    for (var i = 0; i < 60 * 20; i++) {
      game.update(1 / 60);
      if (i > 60 * 10) widest = math.max(widest, pendulum.swing.abs());
      tilt = math.max(tilt, pendulum.body.angle.abs());
    }
    expect(widest, closeTo(0.56, 0.07), reason: 'the escapement keeps it');
    expect(tilt, lessThan(0.05), reason: 'the platform stays level');
  });

  testWidgets('a gear turns its hammer until a crate jams its teeth', (
    tester,
  ) async {
    final game = await boot(tester);
    final gear = Gear(centre: Vector2(10, 9.1), radius: 1.3);
    final hammer = StrikingHammer(axle: Vector2(15, 2.6), arm: 3.6, gear: gear);
    await game.world.addAll([
      // The floor, with a trench over the gear's teeth.
      StoneBlock(left: 0, top: 7, right: 9.4, bottom: 7.4),
      StoneBlock(left: 10.6, top: 7, right: 20, bottom: 7.4),
      gear,
      hammer,
    ]);
    await settle(tester, game);
    for (var i = 0; i < 120; i++) {
      game.update(1 / 60);
    }
    expect(gear.jammed, isFalse);
    final double swungFree = hammer.angle;
    final crate = PhysicsCrate(
      position: Vector2(10, 6.3),
      size: Vector2(1, 1),
      massKg: 30,
    );
    await game.world.add(crate);
    await settle(tester, game);
    for (var i = 0; i < 180; i++) {
      game.update(1 / 60);
    }
    expect(gear.jammed, isTrue, reason: 'the crate is caught in its teeth');
    final double stopped = hammer.angle;
    for (var i = 0; i < 120; i++) {
      game.update(1 / 60);
    }
    expect((hammer.angle - stopped).abs(), lessThan(0.2));
    expect(swungFree, isNot(math.pi));
  });

  testWidgets('the clock hand moves in jumps and lies level for a while', (
    tester,
  ) async {
    final game = await boot(tester);
    final hand = ClockHand(
      hub: Vector2(10, 7),
      length: 6,
      startAngle: math.pi - math.pi / 6,
    );
    await game.world.add(hand);
    await settle(tester, game);
    var levelFor = 0.0;
    for (var i = 0; i < 60 * 8; i++) {
      game.update(1 / 60);
      if (hand.level) levelFor += 1 / 60;
    }
    expect(levelFor, closeTo(2.2 - 0.35, 0.4));
  });
}
