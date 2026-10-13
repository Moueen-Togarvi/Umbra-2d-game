import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/character/character_rig.dart';
import 'package:umbra/character/foot_placement.dart';
import 'package:umbra/character/ground_probe.dart';
import 'package:umbra/character/leg_physics.dart';

const double _h = 1.3;
const double _dt = 1 / 120;

/// Flat or sloped analytic ground: y = [y0] + [slope] * (x - 5).
GroundQuery _ground(double y0, {double slope = 0}) => (x, fromY, depth) {
  final double y = y0 + slope * (x - 5);
  if (y < fromY || y > fromY + depth) return null;
  return GroundContact(
    Vector2(x, y),
    Vector2(slope, -1)..normalize(),
    _dummyBody!,
  );
};

Body? _dummyBody;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    initializeForge2D();
    final world = World(gravity: Vector2.zero());
    _dummyBody = world.createBody(BodyDef());
  });

  final rig = CharacterRig(height: _h);
  final offset = Vector2(5, 5);

  void expectLegsHeldTogether(CharacterRigPose pose, double facing) {
    for (final front in const [true, false]) {
      final hip = pose[front ? RigJoint.frontHip : RigJoint.backHip];
      final knee = pose[front ? RigJoint.frontKnee : RigJoint.backKnee];
      final ankle = pose[front ? RigJoint.frontAnkle : RigJoint.backAnkle];
      for (final v in [knee, ankle]) {
        expect(v.x.isFinite && v.y.isFinite, isTrue);
      }
      expect((knee - hip).length, closeTo(CharacterRig.thigh * _h, 0.012));
      expect((ankle - knee).length, closeTo(CharacterRig.shin * _h, 0.012));
      // The knee is in front of the hip–ankle line, never behind it.
      final d = ankle - hip;
      final k = knee - hip;
      expect((d.x * k.y - d.y * k.x) * facing, lessThanOrEqualTo(1e-6));
    }
  }

  test('bones keep their length and knees bend forwards under any drive', () {
    for (final facing in const [1.0, -1.0]) {
      final legs = LegPhysics(height: _h);
      final random = math.Random(4);
      var mode = LegMode.swing;
      for (var step = 0; step < 1200; step++) {
        if (step % 90 == 0) {
          mode = const [
            LegMode.swing,
            LegMode.air,
            LegMode.hang,
          ][random.nextInt(3)];
        }
        final pose = rig
            .solve(
              CharacterPose(
                facing: facing,
                gait: random.nextDouble(),
                gaitPhase: step * 0.09,
                air: mode == LegMode.swing ? 0 : 1,
                fallLean: math.sin(step * 0.03),
              ),
            )
            .translated(offset + Vector2(math.sin(step * 0.05) * 0.4, 0));
        final out = legs.step(
          dt: _dt,
          target: pose,
          modes: [mode, mode],
          ground: _ground(100),
          gravity: 18,
        );
        expectLegsHeldTogether(out, facing);
      }
    }
  });

  test('a planted foot stays exactly where it was put', () {
    final legs = LegPhysics(height: _h);
    Vector2? planted;
    for (var step = 0; step < 240; step++) {
      // The pelvis bobs on its spring above a foot that must not move.
      final pose = rig
          .solve(
            CharacterPose(
              pelvisDrop: 0.03 * math.sin(step * 0.2).abs(),
              frontFoot: const Offset(0.07, 0.5),
              backFoot: const Offset(-0.06, 0.5),
            ),
          )
          .translated(offset);
      final out = legs.step(
        dt: _dt,
        target: pose,
        modes: const [LegMode.planted, LegMode.planted],
        ground: _ground(offset.y + 0.5 * _h),
        gravity: 18,
      );
      if (step == 20) planted = out[RigJoint.frontAnkle].clone();
      if (step > 20) {
        expect((out[RigJoint.frontAnkle] - planted!).length, lessThan(1e-3));
      }
      expectLegsHeldTogether(out, 1);
    }
  });

  test('swinging soles cannot sink into a slope', () {
    final legs = LegPhysics(height: _h);
    const slope = -0.3;
    final ground = _ground(offset.y + 0.5 * _h, slope: slope);
    for (var step = 0; step < 360; step++) {
      // Targets deliberately pushed below the ground.
      final pose = rig
          .solve(CharacterPose(gait: 1, gaitPhase: step * 0.12, groundY: 0.6))
          .translated(offset);
      final out = legs.step(
        dt: _dt,
        target: pose,
        modes: const [LegMode.swing, LegMode.swing],
        ground: ground,
        gravity: 18,
      );
      for (final front in const [true, false]) {
        final ankle = out[front ? RigJoint.frontAnkle : RigJoint.backAnkle];
        final toe = out[front ? RigJoint.frontToe : RigJoint.backToe];
        final along = (toe - ankle).normalized();
        final down = Vector2(-along.y, along.x);
        final sole = CharacterRig.ankleHeight * _h;
        for (final soleAt in [
          ankle - along * (CharacterRig.heelReach * _h) + down * sole,
          toe + down * sole,
        ]) {
          final surface = offset.y + 0.5 * _h + slope * (soleAt.x - 5);
          expect(soleAt.y, lessThanOrEqualTo(surface + 0.004));
        }
      }
    }
  });

  test('a planted sole lies flat along the ground under it', () {
    for (final slope in const [-0.4, 0.0, 0.35]) {
      final normal = Vector2(slope, -1)..normalize();
      final (ankle, along) = CharacterRig.footOnGround(
        Vector2(0.05, 0.5),
        normal,
        0,
      );
      expect(along.dot(normal).abs(), lessThan(1e-6));
      expect(along.x, greaterThan(0), reason: 'toes point forwards');
      expect(
        (ankle - Vector2(0.05, 0.5)).dot(-normal),
        lessThan(0),
        reason: 'the ankle is above the ground',
      );
      expect(
        (ankle - Vector2(0.05, 0.5)).length,
        closeTo(CharacterRig.ankleHeight, 1e-6),
      );
    }
  });

  test('in the air the legs trail and hang under their own weight', () {
    final legs = LegPhysics(height: _h);
    var largestLag = 0.0;
    for (var step = 0; step < 60; step++) {
      // The body shoots upwards at 6 m/s, as on take-off.
      final lift = Vector2(0, -6 * step * _dt);
      final pose = rig
          .solve(const CharacterPose(air: 1, fallLean: -1))
          .translated(offset + lift);
      // The step writes into the pose it is given; keep the goal.
      final goal = pose[RigJoint.frontAnkle].clone();
      final out = legs.step(
        dt: _dt,
        target: pose,
        modes: const [LegMode.air, LegMode.air],
        ground: _ground(100),
        gravity: 18,
      );
      largestLag = math.max(largestLag, out[RigJoint.frontAnkle].y - goal.y);
      expectLegsHeldTogether(out, 1);
    }
    expect(
      largestLag,
      greaterThan(0.04),
      reason: 'the feet trail below the body as it leaves the ground',
    );
  });

  test('at a pit edge both feet stand on the lip, not over the gap', () {
    final world = Forge2DWorld(gravity: Vector2(0, 18));
    addTearDown(() => world.physicsWorld.destroy());
    // Ground from x = 0 to 2, top at y = 3; a pit beyond it.
    world
        .createBody(BodyDef(position: Vector2(1, 3.5)))
        .createShape(Polygon.box(1, 0.5), ShapeDef());
    final player = world.createBody(
      BodyDef(type: BodyType.dynamic, position: Vector2(2.06, 3 - _h / 2)),
    );
    for (final facing in const [1.0, -1.0]) {
      final feet = FootPlacement();
      feet.update(
        world: world,
        body: player,
        height: _h,
        phase: 0,
        gait: 0,
        facing: facing,
        grounded: true,
        speed: 0,
        dt: _dt,
      );
      for (final foot in feet.targets) {
        expect(foot.x, lessThanOrEqualTo(2.0 + 1e-6), reason: 'over the gap');
        expect(foot.y, closeTo(3, 1e-4), reason: 'not on the ground');
      }
    }
  });
}
