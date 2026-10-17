import 'dart:math' as math;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/entities/cave_props.dart';
import 'package:umbra/entities/hazard.dart';
import 'package:umbra/physics/collision_layers.dart';
import 'package:umbra/physics/shape_clearance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeForge2D);
  test('a rotated crate AABB does not block empty space beside the crate', () {
    final world = Forge2DWorld(gravity: Vector2.zero());
    addTearDown(() => world.physicsWorld.destroy());
    final body = world.createBody(
      BodyDef(rotation: Rot.fromAngle(math.pi / 4)),
    );
    final shape = body.createShape(Polygon.box(1, .2));
    expect(
      world.overlapAabb(Aabb(Vector2(.7, -.9), Vector2(.9, -.7))),
      contains(shape),
    );
    expect(capsuleOverlapsShape(shape, Vector2(.8, -.8), .2, .3), isFalse);
    expect(capsuleOverlapsShape(shape, Vector2(.3, .3), .2, .3), isTrue);
  });
  test('closed cave rock rejects positions inside its chain boundary', () {
    final world = Forge2DWorld(gravity: Vector2.zero());
    addTearDown(() => world.physicsWorld.destroy());
    final rock = RockMass([
      Vector2(-2, -2),
      Vector2(2, -2),
      Vector2(2, 2),
      Vector2(-2, 2),
    ])..world = world;
    rock.body = rock.createBody();
    expect(
      capsuleOverlapsShape(rock.body.shapes.first, Vector2.zero(), .42, 1.3),
      isTrue,
    );
    expect(
      capsuleOverlapsShape(rock.body.shapes.first, Vector2(3, 0), .42, 1.3),
      isFalse,
    );
  });
  test('stake tips generate native sensor events only on actual overlap', () {
    final world = Forge2DWorld(gravity: Vector2.zero());
    addTearDown(() => world.physicsWorld.destroy());
    final hazard = Hazard(center: Vector2.zero(), size: Vector2(3, 2))
      ..world = world;
    hazard.body = hazard.createBody();
    final sensors = hazard.body.shapes.where((s) => s.isSensor).toList();
    expect(sensors.length, greaterThan(5));
    final vertices = [
      for (final shape in sensors) ...(shape.geometry as Polygon).points!,
    ];
    vertices.sort((a, b) => a.y.compareTo(b.y));
    final tip = vertices.first;
    final probe = world.createBody(
      BodyDef(type: BodyType.dynamic, position: tip + Vector2(0, -.06)),
    );
    probe.createShape(
      Circle(radius: .015),
      ShapeDef(
        filter: Filter(
          categoryBits: CollisionLayers.player,
          maskBits: CollisionLayers.sensor,
        ),
        enableSensorEvents: true,
      ),
    );
    world.update(1 / 60);
    expect(world.physicsWorld.sensorEvents.begin, isEmpty);
    final target = sensors.firstWhere(
      (s) =>
          (s.geometry as Polygon).points!.any((p) => (p - tip).length < .001),
    );
    final hull = (target.geometry as Polygon).points!;
    final centroid =
        hull.fold(Vector2.zero(), (sum, p) => sum + p) / hull.length.toDouble();
    final inside = tip + (centroid - tip) * .12;
    expect(target.testPoint(inside), isTrue);
    probe.setTransform(inside, const Rot.identity());
    probe.isAwake = true;
    var touched = false;
    for (var i = 0; i < 3; i++) {
      world.update(1 / 60);
      touched |= world.physicsWorld.sensorEvents.begin.any(
        (event) => event.visitor.body == probe,
      );
    }
    expect(touched, isTrue);
  });
}
