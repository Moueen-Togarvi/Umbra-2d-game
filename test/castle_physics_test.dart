import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/castle_props.dart';
import 'package:umbra/entities/ground.dart';
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

  void step(Forge2DGame game, double seconds) {
    for (var i = 0; i < (seconds * 60).round(); i++) {
      game.update(1 / 60);
    }
  }

  testWidgets('a weighing pan lifts the gate on its rope only when it is '
      'heavier than the gate', (tester) async {
    final game = await boot(tester);
    final pan = WeighPan(floorAt: Vector2(5, 5), width: 1.9, drop: 2.2);
    final gate = Portcullis(position: Vector2(10, 3.65), height: 2.7);
    final pulley = Pulley(a: pan, b: gate, wheelY: 1.5);
    await game.world.addAll([
      Ground.slab(left: 0, right: 4, top: 5, thickness: 4),
      Ground.slab(left: 6, right: 14, top: 5, thickness: 4),
      Ground.slab(left: 3.9, right: 6.1, top: 7.6, thickness: 1),
      pan,
      gate,
      pulley,
    ]);
    await settle(tester, game);
    step(game, 2);
    // Empty, the 8 kg pan cannot lift 40 kg of iron.
    expect(gate.travel, closeTo(0, 0.02));
    expect(pan.travel, closeTo(0, 0.02));
    // A 35 kg crate in it: 43 kg against 40, slowly.
    final crate = PhysicsCrate(
      position: Vector2(5, 4.45),
      size: Vector2(1, 1),
      massKg: 35,
    );
    await game.world.add(crate);
    await settle(tester, game);
    final double length = pan.body.position.y + gate.body.position.y;
    step(game, 1.0);
    expect(gate.travel, lessThan(-0.15), reason: 'the gate begins to rise');
    step(game, 4);
    expect(gate.travel, lessThan(-1.9), reason: 'up in its slot');
    expect(pan.travel, greaterThan(1.9), reason: 'down in its pit');
    expect(
      pan.body.position.y + gate.body.position.y,
      closeTo(length, 0.03),
      reason: 'the rope does not stretch',
    );
    expect(pulley.massA, closeTo(43, 0.5), reason: 'the crate rides in it');
    // Take the crate out: the gate is heavier again and comes back down.
    crate.body.setTransform(Vector2(12, 4.4), const Rot.identity());
    step(game, 5);
    expect(gate.travel, closeTo(0, 0.05));
  });

  testWidgets('a counterweighted lift rises once the crate holding it down '
      'is off it', (tester) async {
    final game = await boot(tester);
    final lift = LiftPlatform(
      position: Vector2(5, 8.88),
      rise: 3.4,
      massKg: 20,
    );
    final weight = Counterweight(
      position: Vector2(9, 3),
      massKg: 65,
      rise: 0,
      drop: 3.4,
    );
    final crate = PhysicsCrate(
      position: Vector2(5.6, 8.2),
      size: Vector2(1, 1),
      massKg: 50,
    );
    await game.world.addAll([
      Ground.slab(left: 0, right: 14, top: 9, thickness: 1),
      lift,
      weight,
      Pulley(a: lift, b: weight, wheelY: 0.5),
      crate,
    ]);
    await settle(tester, game);
    step(game, 2);
    // 70 kg on the lift against 65: it stays down.
    expect(lift.travel, closeTo(0, 0.03));
    crate.body.setTransform(Vector2(12, 8.4), const Rot.identity());
    step(game, 5);
    expect(lift.travel, lessThan(-3.3), reason: 'up to the top');
    expect(weight.travel, greaterThan(3.3));
  });

  testWidgets('a hung chandelier falls when let go, and its candles go out '
      'in the crash', (tester) async {
    final game = await boot(tester);
    final chandelier = HungChandelier(
      anchor: Vector2(5, 0),
      ropeLength: 2,
      width: 2.4,
    );
    await game.world.addAll([
      Ground.slab(left: 0, right: 10, top: 12, thickness: 1),
      chandelier,
    ]);
    await settle(tester, game);
    step(game, 1);
    final double hung = chandelier.body.position.y;
    expect(chandelier.lit, isTrue);
    expect(hung, closeTo(2 + chandelier.height / 2, 0.05));
    chandelier.release();
    var fastest = 0.0;
    for (var i = 0; i < 120; i++) {
      game.update(1 / 60);
      if (chandelier.body.linearVelocity.y > fastest) {
        fastest = chandelier.body.linearVelocity.y;
      }
    }
    expect(fastest, greaterThan(8));
    expect(chandelier.landed, isTrue);
    expect(chandelier.lit, isFalse);
    expect(chandelier.body.position.y, greaterThan(hung + 5));
  });

  testWidgets('a tall bookcase tips over when pushed at the height of a '
      'boy, and lies flat', (tester) async {
    final game = await boot(tester);
    final bookcase = TallBookcase(x: 5, floorY: 9);
    await game.world.addAll([
      Ground.slab(left: 0, right: 14, top: 9, thickness: 1),
      bookcase,
    ]);
    await settle(tester, game);
    // A boy's push: 500 N at 0.7 m up, for a moment.
    for (var i = 0; i < 40; i++) {
      bookcase.body.applyForce(
        Vector2(GameConfig.pushForceNewtons, 0),
        point: Vector2(4.65, 8.3),
      );
      game.update(1 / 60);
    }
    step(game, 3);
    expect(bookcase.body.angle.abs(), closeTo(1.5708, 0.12));
    expect(bookcase.body.position.x, greaterThan(6));
  });
}
