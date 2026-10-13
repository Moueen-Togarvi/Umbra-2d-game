import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/character/character_rig.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/physics_props.dart';

const _step = 1 / 120;
const _width = 0.42;
const _height = 1.3;

Forge2DWorld _world() {
  final world = Forge2DWorld(gravity: Vector2(0, 22));
  addTearDown(() => world.physicsWorld.destroy());
  return world;
}

Body _box(Forge2DWorld world, Vector2 centre, Vector2 size) {
  final result = world.createBody(BodyDef(position: centre));
  result.createShape(
    Polygon.box(size.x / 2, size.y / 2),
    ShapeDef(material: SurfaceMaterial(friction: 0.5)),
  );
  return result;
}

Body _player(Forge2DWorld world, Vector2 position, {double friction = 0}) {
  final result = world.createBody(
    BodyDef(
      type: BodyType.dynamic,
      position: position,
      fixedRotation: true,
      enableSleep: false,
    ),
  );
  const radius = _width / 2;
  final area = _width * (_height - _width) + math.pi * radius * radius;
  result.createShape(
    Capsule(
      center1: Vector2(0, -_height / 2 + radius),
      center2: Vector2(0, _height / 2 - radius),
      radius: radius,
    ),
    ShapeDef(
      density: 40 / area,
      filter: Filter(categoryBits: 2, maskBits: 1 | 4),
      material: SurfaceMaterial(friction: friction),
    ),
  );
  return result;
}

T _create<T extends BodyComponent>(Forge2DWorld world, T prop) {
  prop.world = world;
  prop.body = prop.createBody();
  return prop;
}

CharacterInteractions _interactions(Forge2DWorld world, Body player) =>
    CharacterInteractions(
      world: world,
      playerBody: player,
      width: _width,
      height: _height,
    );

void _input(
  CharacterInteractions system, {
  double axis = 0,
  bool grounded = true,
  bool pressed = false,
  bool held = false,
  bool jump = false,
  bool down = false,
}) => system.update(
  _step,
  axis: axis,
  facing: 1,
  grounded: grounded,
  interactPressed: pressed,
  interactHeld: held,
  jumpPressed: jump,
  downHeld: down,
);

/// A shoulder of the rig standing upright in [player], and the arm's reach.
Vector2 _shoulder(Body player, {bool front = true}) =>
    player.position + CharacterRig.restShoulder(front: front) * _height;
const double _reach = CharacterRig.armReach * _height;

void _drive(Body player, double speed) {
  final force = ((speed - player.linearVelocity.x) * player.mass * 18).clamp(
    -300.0,
    300.0,
  );
  player.applyForce(Vector2(force, 0));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeForge2D);

  test(
    'the same bounded push moves a light crate farther than a heavy crate',
    () {
      double push(double mass, double friction) {
        final world = _world();
        _box(world, Vector2(0, 4), Vector2(20, 1));
        final player = _player(world, Vector2(0, 3.5 - _height / 2));
        final crate = _create(
          world,
          PhysicsCrate(
            position: Vector2(0.85, 3),
            size: Vector2(1, 1),
            massKg: mass,
            friction: friction,
          ),
        );
        final system = _interactions(world, player);
        var touched = false;
        for (var i = 0; i < 180; i++) {
          _input(system, axis: 1);
          touched |= system.mode == InteractionMode.pushing;
          _drive(player, 1.8);
          world.update(_step);
        }
        expect(touched, isTrue);
        expect(crate.body.mass, closeTo(mass, 0.01));
        return crate.body.position.x - 0.85;
      }

      final lightDistance = push(8, 0.25);
      final heavyDistance = push(35, 0.15);
      expect(lightDistance, greaterThan(heavyDistance + 0.25));
      expect(heavyDistance, greaterThan(0.02));
    },
  );

  test('a blocked crate prevents the physical player from passing through', () {
    final world = _world();
    _box(world, Vector2(0, 4), Vector2(20, 1));
    _box(world, Vector2(1.85, 2.5), Vector2(1, 2));
    final player = _player(world, Vector2(0, 3.5 - _height / 2));
    final crate = _create(
      world,
      PhysicsCrate(position: Vector2(0.85, 3), size: Vector2(1, 1), massKg: 8),
    );
    final system = _interactions(world, player);
    for (var i = 0; i < 240; i++) {
      _input(system, axis: 1);
      _drive(player, 1.8);
      world.update(_step);
    }
    expect(system.mode, InteractionMode.pushing);
    expect(player.position.x, lessThan(0.2));
    expect(crate.body.position.x, closeTo(0.85, 0.04));
    expect(system.gripWorld, isNotNull);
  });

  test(
    'grab and backward pull use a force-limited constraint, then release',
    () {
      final world = _world();
      _box(world, Vector2(0, 4), Vector2(20, 1));
      final player = _player(world, Vector2(0, 3.5 - _height / 2));
      final crate = _create(
        world,
        PhysicsCrate(
          position: Vector2(0.68, 3.1),
          size: Vector2(0.8, 0.8),
          massKg: 8,
        ),
      );
      final system = _interactions(world, player);
      for (var i = 0; i < 30; i++) {
        world.update(_step);
      }
      _input(system, pressed: true, held: true);
      expect(system.mode, InteractionMode.pulling);
      final startX = crate.body.position.x;
      for (var i = 0; i < 150; i++) {
        _input(system, axis: -1, held: true);
        _drive(player, -1.6);
        world.update(_step);
        expect(system.mode, InteractionMode.pulling);
        expect(
          (system.gripWorld! - _shoulder(player)).length,
          lessThan(_reach + 0.08),
        );
      }
      expect(crate.body.position.x, lessThan(startX - 0.6));
      expect(crate.body.angle.abs(), lessThan(0.02));
      final hand = system.gripWorld!;
      expect((hand - crate.body.position).length, lessThan(0.7));
      final velocity = crate.body.linearVelocity.clone();
      _input(system, held: false);
      expect(system.mode, InteractionMode.none);
      expect((crate.body.linearVelocity - velocity).length, lessThan(1e-8));
    },
  );

  test(
    'a rope is caught without the action button, swings, and jump kicks off',
    () {
      final world = _world();
      final rope = _create(world, SwingRope(anchor: Vector2.zero(), length: 2));
      final player = _player(world, Vector2(0, 2 + _height * 0.37 + 0.025));
      final system = _interactions(world, player);
      final entryPosition = player.position.clone();
      final entryVelocity = player.linearVelocity.clone();
      _input(system, grounded: false);
      expect(system.mode, InteractionMode.swinging);
      expect(system.controlsMotion, isTrue);
      expect((player.position - entryPosition).length, lessThan(1e-8));
      expect((player.linearVelocity - entryVelocity).length, lessThan(1e-8));
      var peakSwingSpeed = 0.0;
      for (var i = 0; i < 240; i++) {
        _input(system, axis: 1, grounded: false);
        world.update(_step);
        peakSwingSpeed = math.max(
          peakSwingSpeed,
          player.linearVelocity.x.abs(),
        );
        expect(rope.constraint.currentLength, closeTo(2, 0.035));
        for (final front in [true, false]) {
          expect(
            (system.gripWorld! - _shoulder(player, front: front)).length,
            lessThan(_reach + 0.02),
          );
        }
      }
      expect(peakSwingSpeed, greaterThan(0.3));
      final velocity = player.linearVelocity.clone();
      _input(system, grounded: false, jump: true);
      expect(system.mode, InteractionMode.none);
      expect(system.releasedThisStep, isTrue);
      // The swing's momentum is kept, plus the legs' kick upwards.
      expect(
        (player.linearVelocity -
                velocity -
                Vector2(0, -GameConfig.ropeJumpSpeed))
            .length,
        lessThan(1e-5),
      );
      // And it is not caught again on the way past.
      for (var i = 0; i < 6; i++) {
        _input(system, grounded: false);
        world.update(_step);
        expect(system.mode, InteractionMode.none);
      }
      expect(player.linearVelocity.x, closeTo(velocity.x, 0.05));
    },
  );

  test(
    'horizontal and vertical platforms move through velocities and carry riders',
    () {
      for (final vertical in [false, true]) {
        final world = _world();
        final platform = _create(
          world,
          MovingPlatform(
            from: Vector2(0, 3),
            to: vertical ? Vector2(0, 2) : Vector2(2, 3),
            size: Vector2(2, 0.25),
            speed: 0.6,
          ),
        );
        final rider = _player(
          world,
          Vector2(0, 3 - 0.125 - _height / 2),
          friction: 0.8,
        );
        final offset = rider.position - platform.body.position;
        for (var i = 0; i < 120; i++) {
          platform.update(_step);
          world.update(_step);
        }
        expect(platform.body.linearVelocity.length, closeTo(0.6, 0.001));
        expect(
          (rider.position - platform.body.position - offset).length,
          lessThan(vertical ? 0.04 : 0.10),
        );
        expect(
          vertical ? rider.position.y : rider.position.x,
          vertical ? lessThan(2) : greaterThan(0.45),
        );
      }
    },
  );

  test(
    'ledge hanging climbs around a solid corner into a clear standing pose',
    () {
      final world = _world();
      _box(world, Vector2(1.5, 4), Vector2(2, 2)); // left0.5, top3
      final player = _player(world, Vector2(0.23, 3.5));
      final system = _interactions(world, player);
      // Caught automatically, no action button.
      _input(system, grounded: false);
      expect(system.mode, InteractionMode.hanging);
      for (var i = 0; i < 50; i++) {
        _input(system, grounded: false);
        world.update(_step);
      }
      _input(system, grounded: false, jump: true);
      expect(system.mode, InteractionMode.climbing);
      var climbed = false;
      var largestStep = 0.0;
      for (var i = 0; i < 360; i++) {
        final previous = player.position;
        _input(system, grounded: false);
        world.update(_step);
        largestStep = math.max(
          largestStep,
          (player.position - previous).length,
        );
        if (system.mode == InteractionMode.none) {
          climbed = true;
          break;
        }
      }
      expect(climbed, isTrue);
      expect(player.position.x, greaterThan(0.7));
      expect(player.position.y + _height / 2, lessThan(3.05));
      expect(largestStep, lessThan(0.05), reason: 'climbing must not teleport');
    },
  );

  test('a low ceiling above the ledge rejects an unsafe climb', () {
    final world = _world();
    _box(world, Vector2(1.5, 4), Vector2(2, 2));
    _box(world, Vector2(1.5, 2.2), Vector2(2, 0.3));
    final player = _player(world, Vector2(0.23, 3.5));
    final system = _interactions(world, player);
    _input(system, grounded: false);
    expect(system.mode, InteractionMode.none);
    expect(system.controlsMotion, isFalse);
  });

  test('down or steering away lets go of a ledge, and it is not re-caught', () {
    for (final letGo in ['down', 'away']) {
      final world = _world();
      _box(world, Vector2(1.5, 4), Vector2(2, 2));
      final player = _player(world, Vector2(0.23, 3.5));
      final system = _interactions(world, player);
      _input(system, grounded: false);
      expect(system.mode, InteractionMode.hanging);
      _input(
        system,
        grounded: false,
        down: letGo == 'down',
        axis: letGo == 'away' ? -1 : 0,
      );
      expect(system.mode, InteractionMode.none, reason: letGo);
      for (var i = 0; i < 12; i++) {
        _input(system, grounded: false);
        world.update(_step);
        expect(system.mode, InteractionMode.none, reason: letGo);
      }
    }
  });

  test('steering away from a wall does not catch its ledge', () {
    final world = _world();
    _box(world, Vector2(1.5, 4), Vector2(2, 2));
    final player = _player(world, Vector2(0.23, 3.5));
    final system = _interactions(world, player);
    _input(system, grounded: false, axis: -1);
    expect(system.mode, InteractionMode.none);
  });

  test('objects beyond arm reach cannot create a disconnected grab', () {
    final world = _world();
    _box(world, Vector2(0, 4), Vector2(20, 1));
    final player = _player(world, Vector2(0, 3.5 - _height / 2));
    _create(
      world,
      PhysicsCrate(
        position: Vector2(0.96, 3.1),
        size: Vector2(0.8, 0.8),
        massKg: 8,
      ),
    );
    final system = _interactions(world, player);
    _input(system, pressed: true, held: true);
    expect(system.mode, InteractionMode.none);
    expect(system.gripWorld, isNull);
  });
}
