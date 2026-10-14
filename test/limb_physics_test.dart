import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/character/character_rig.dart';
import 'package:umbra/character/foot_placement.dart';
import 'package:umbra/character/ground_probe.dart';
import 'package:umbra/character/limb_physics.dart';

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
      final legs = LimbPhysics(height: _h);
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
        );
        expectLegsHeldTogether(out, facing);
      }
    }
  });

  void expectArmsHeldTogether(CharacterRigPose pose, double facing) {
    for (final front in const [true, false]) {
      final shoulder =
          pose[front ? RigJoint.frontShoulder : RigJoint.backShoulder];
      final elbow = pose[front ? RigJoint.frontElbow : RigJoint.backElbow];
      final hand = pose[front ? RigJoint.frontHand : RigJoint.backHand];
      for (final v in [elbow, hand]) {
        expect(v.x.isFinite && v.y.isFinite, isTrue);
      }
      expect(
        (elbow - shoulder).length,
        closeTo(CharacterRig.upperArm * _h, 0.012),
      );
      expect((hand - elbow).length, closeTo(CharacterRig.forearm * _h, 0.012));
      // The elbow bends backwards: the mirror of the knee.
      final d = hand - shoulder;
      final e = elbow - shoulder;
      expect((d.x * e.y - d.y * e.x) * facing, greaterThanOrEqualTo(-1e-6));
    }
  }

  test('arm bones keep their length and elbows bend backwards', () {
    for (final facing in const [1.0, -1.0]) {
      final limbs = LimbPhysics(height: _h);
      final random = math.Random(9);
      var mode = ArmMode.ground;
      for (var step = 0; step < 1200; step++) {
        if (step % 90 == 0) {
          mode = const [ArmMode.ground, ArmMode.air][random.nextInt(2)];
        }
        final pose = rig
            .solve(
              CharacterPose(
                facing: facing,
                gait: random.nextDouble(),
                gaitPhase: step * 0.09,
                air: mode == ArmMode.ground ? 0 : 1,
                fallLean: math.sin(step * 0.03),
                clock: step * _dt,
              ),
            )
            .translated(offset + Vector2(0, math.sin(step * 0.07) * 0.5));
        final out = limbs.step(
          dt: _dt,
          target: pose,
          modes: const [LegMode.air, LegMode.air],
          armModes: [mode, mode],
          ground: _ground(100),
        );
        expectArmsHeldTogether(out, facing);
      }
    }
  });

  test('falling, the front arm rises, the back one trails, elbows bent', () {
    for (final facing in const [1.0, -1.0]) {
      final limbs = LimbPhysics(height: _h);
      late CharacterRigPose out;
      for (var step = 0; step < 90; step++) {
        final pose = rig
            .solve(
              CharacterPose(
                facing: facing,
                air: 1,
                fallLean: 1,
                clock: step * _dt,
              ),
            )
            // Falling freely, as the body does: 18 m/s² × 1.2.
            .translated(
              offset + Vector2(0, 0.5 * 21.6 * math.pow(step * _dt, 2)),
            );
        out = limbs.step(
          dt: _dt,
          target: pose,
          modes: const [LegMode.air, LegMode.air],
          armModes: const [ArmMode.air, ArmMode.air],
          ground: _ground(100),
        );
      }
      const double full = (CharacterRig.upperArm + CharacterRig.forearm) * _h;
      for (final front in const [true, false]) {
        final shoulder =
            out[front ? RigJoint.frontShoulder : RigJoint.backShoulder];
        final hand = out[front ? RigJoint.frontHand : RigJoint.backHand];
        // Never a straight, pointing arm.
        expect((hand - shoulder).length, lessThan(full * 0.88));
      }
      final chest = out[RigJoint.chest].x;
      expect(
        out[RigJoint.frontHand].y,
        lessThan(out[RigJoint.frontShoulder].y),
        reason: 'the front hand is raised',
      );
      expect((out[RigJoint.frontHand].x - chest) * facing, greaterThan(0));
      expect(
        (out[RigJoint.backHand].x - chest) * facing,
        lessThan(0),
        reason: 'the back hand trails behind',
      );
    }
  });

  test('a gripping hand stays on what it holds', () {
    final limbs = LimbPhysics(height: _h);
    final grip = Vector2(5 + 0.25, 5 - 0.12);
    for (var step = 0; step < 120; step++) {
      // The body shakes about under a hand fixed to a crate.
      final shake = Vector2(math.sin(step * 0.3) * 0.03, 0);
      final local = grip - offset - shake;
      final pose = rig
          .solve(
            CharacterPose(
              push: 1,
              frontHand: Offset(local.x / _h, local.y / _h),
              interactionWeight: 1,
            ),
          )
          .translated(offset + shake);
      final out = limbs.step(
        dt: _dt,
        target: pose,
        modes: const [LegMode.swing, LegMode.swing],
        armModes: const [ArmMode.grip, ArmMode.ground],
        ground: _ground(100),
      );
      if (step > 10) {
        expect((out[RigJoint.frontHand] - grip).length, lessThan(0.01));
      }
    }
  });

  /// Steps [limbs] once on [pose] translated by [at], returning the hand
  /// goals (front, back) the pose asked for and the simulated pose.
  (List<Vector2>, CharacterRigPose) stepArms(
    LimbPhysics limbs,
    CharacterPose pose,
    Vector2 at, {
    ArmMode mode = ArmMode.ground,
  }) {
    final target = rig.solve(pose).translated(at);
    final goals = [
      target[RigJoint.frontHand].clone(),
      target[RigJoint.backHand].clone(),
    ];
    final out = limbs.step(
      dt: _dt,
      target: target,
      modes: const [LegMode.swing, LegMode.swing],
      armModes: [mode, mode],
      ground: _ground(100),
    );
    return (goals, out);
  }

  test('a free arm trails a sudden take-off a little, without bouncing', () {
    final limbs = LimbPhysics(height: _h);
    const pose = CharacterPose(air: 1, fallLean: -1);
    for (var step = 0; step < 60; step++) {
      stepArms(limbs, pose, offset, mode: ArmMode.air);
    }
    var trail = 0.0, above = 0.0;
    for (var step = 1; step <= 60; step++) {
      // The body shoots upwards at 6 m/s.
      final (goals, out) = stepArms(
        limbs,
        pose,
        offset - Vector2(0, 6 * step * _dt),
        mode: ArmMode.air,
      );
      final double lag = out[RigJoint.backHand].y - goals[1].y;
      trail = math.max(trail, lag);
      above = math.max(above, -lag);
    }
    expect(trail, inInclusiveRange(0.004, 0.06), reason: 'a little weight');
    expect(above, lessThan(0.002), reason: 'and no bounce back past it');
  });

  test('arms settle after a jolt without wobbling', () {
    final limbs = LimbPhysics(height: _h);
    for (var step = 0; step < 60; step++) {
      stepArms(limbs, const CharacterPose(), offset);
    }
    // The arms' pose jumps (a landing throws them forward), the body drops
    // on its spring, and the mode flips to the air and back on the way.
    final errors = <double>[];
    Vector2? along;
    for (var step = 0; step < 72; step++) {
      final (goals, out) = stepArms(
        limbs,
        const CharacterPose(landing: 1, pelvisDrop: 0.04),
        offset,
        mode: step >= 12 && step < 24 ? ArmMode.air : ArmMode.ground,
      );
      final Vector2 error = out[RigJoint.frontHand] - goals[0];
      along ??= error.normalized();
      errors.add(error.dot(along));
      if (step >= 48) {
        expect(error.length, lessThan(0.004), reason: 'settled by 0.4 s');
      }
    }
    final double first = errors.first;
    expect(first, greaterThan(0.02), reason: 'the hand lags the jump');
    var flips = 0;
    for (var i = 1; i < errors.length; i++) {
      if (errors[i] * errors[i - 1] < 0 && errors[i].abs() > 1e-4) flips++;
    }
    expect(flips, lessThanOrEqualTo(1));
    expect(
      -errors.reduce(math.min),
      lessThan(first * 0.1),
      reason: 'overshoot',
    );
  });

  test('running arms add no jitter to the swing', () {
    final limbs = LimbPhysics(height: _h);
    final hands = <List<Vector2>>[[], []];
    final goals = <List<Vector2>>[[], []];
    // Full speed: 2π per stride of about 1.5 m at 3.2 m/s.
    const double phaseRate = 2 * math.pi * 3.2 / 1.51;
    for (var step = 0; step < 240; step++) {
      final double t = step * _dt;
      final (goal, out) = stepArms(
        limbs,
        CharacterPose(
          gait: 1,
          gaitPhase: phaseRate * t,
          clock: t,
          pelvisDrop: 0.01 * math.sin(phaseRate * 2 * t).abs(),
        ),
        offset + Vector2(3.2 * t, 0),
      );
      for (var h = 0; h < 2; h++) {
        final shoulder =
            out[h == 0 ? RigJoint.frontShoulder : RigJoint.backShoulder];
        final hand = out[h == 0 ? RigJoint.frontHand : RigJoint.backHand];
        hands[h].add(hand - shoulder);
        goals[h].add(goal[h] - shoulder);
        if (step > 36) {
          expect((hand - goal[h]).length, lessThan(0.03));
        }
      }
    }
    double roughness(List<Vector2> path) {
      var sum = 0.0;
      for (var i = 37; i + 1 < path.length; i++) {
        sum += (path[i + 1] - path[i] * 2 + path[i - 1]).length;
      }
      return sum;
    }

    for (var h = 0; h < 2; h++) {
      expect(roughness(hands[h]), lessThan(roughness(goals[h]) * 1.15));
    }
  });

  test('standing, the hands are still', () {
    final limbs = LimbPhysics(height: _h);
    Vector2? last;
    for (var step = 0; step < 240; step++) {
      final double t = step * _dt;
      final (_, out) = stepArms(
        limbs,
        CharacterPose(
          clock: t,
          // The pelvis spring settling after a landing.
          pelvisDrop: 0.03 * math.exp(-4 * t) * math.cos(20 * t),
        ),
        offset,
      );
      final hand = out[RigJoint.frontHand] - out[RigJoint.frontShoulder];
      if (step > 60) {
        expect((hand - last!).length, lessThan(0.001));
      }
      last = hand;
    }
  });

  test('a hand put down on the ground stays on top of it', () {
    final limbs = LimbPhysics(height: _h);
    final surface = offset.y + 0.40 * _h;
    for (var step = 0; step < 120; step++) {
      final pose = rig
          .solve(const CharacterPose(hardLanding: 1, pelvisDrop: 0.12))
          .translated(offset);
      final out = limbs.step(
        dt: _dt,
        target: pose,
        modes: const [LegMode.swing, LegMode.swing],
        armModes: const [ArmMode.ground, ArmMode.ground],
        ground: _ground(surface),
      );
      for (final hand in [out[RigJoint.frontHand], out[RigJoint.backHand]]) {
        expect(hand.y + 0.025 * _h, lessThanOrEqualTo(surface + 0.004));
      }
    }
  });

  test('a planted foot stays exactly where it was put', () {
    final legs = LimbPhysics(height: _h);
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
      );
      if (step == 20) planted = out[RigJoint.frontAnkle].clone();
      if (step > 20) {
        expect((out[RigJoint.frontAnkle] - planted!).length, lessThan(1e-3));
      }
      expectLegsHeldTogether(out, 1);
    }
  });

  test('swinging soles cannot sink into a slope', () {
    final legs = LimbPhysics(height: _h);
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

  test('in the air the legs trail a sudden take-off a little, then settle', () {
    final legs = LimbPhysics(height: _h);
    const pose = CharacterPose(air: 1, fallLean: -1);
    for (var step = 0; step < 60; step++) {
      legs.step(
        dt: _dt,
        target: rig.solve(pose).translated(offset),
        modes: const [LegMode.air, LegMode.air],
        ground: _ground(100),
      );
    }
    var trail = 0.0, above = 0.0;
    for (var step = 1; step <= 60; step++) {
      // The body shoots upwards at 6 m/s, as on take-off.
      final target = rig
          .solve(pose)
          .translated(offset - Vector2(0, 6 * step * _dt));
      // The step writes into the pose it is given; keep the goal.
      final goal = target[RigJoint.frontAnkle].clone();
      final out = legs.step(
        dt: _dt,
        target: target,
        modes: const [LegMode.air, LegMode.air],
        ground: _ground(100),
      );
      final double lag = out[RigJoint.frontAnkle].y - goal.y;
      trail = math.max(trail, lag);
      above = math.max(above, -lag);
      expectLegsHeldTogether(out, 1);
    }
    expect(trail, inInclusiveRange(0.003, 0.06), reason: 'a little weight');
    expect(above, lessThan(0.002), reason: 'and no bounce back past it');
  });

  test('legs settle after a jolt without wobbling', () {
    final legs = LimbPhysics(height: _h);
    for (var step = 0; step < 60; step++) {
      legs.step(
        dt: _dt,
        target: rig
            .solve(const CharacterPose(air: 1, fallLean: -1))
            .translated(offset),
        modes: const [LegMode.air, LegMode.air],
        ground: _ground(100),
      );
    }
    // The pose jumps from knees tucked to legs hanging.
    final errors = <double>[];
    Vector2? along;
    for (var step = 0; step < 90; step++) {
      final target = rig
          .solve(const CharacterPose(air: 1, fallLean: 1))
          .translated(offset);
      final goal = target[RigJoint.frontAnkle].clone();
      final out = legs.step(
        dt: _dt,
        target: target,
        modes: const [LegMode.air, LegMode.air],
        ground: _ground(100),
      );
      final error = out[RigJoint.frontAnkle] - goal;
      along ??= error.normalized();
      errors.add(error.dot(along));
      if (step >= 60) {
        expect(error.length, lessThan(0.004), reason: 'settled by 0.5 s');
      }
    }
    expect(errors.first, greaterThan(0.02), reason: 'the foot lags the jump');
    var flips = 0;
    for (var i = 1; i < errors.length; i++) {
      if (errors[i] * errors[i - 1] < 0 && errors[i].abs() > 1e-4) flips++;
    }
    expect(flips, lessThanOrEqualTo(1));
    expect(-errors.reduce(math.min), lessThan(errors.first * 0.1));
  });

  test('running legs add no jitter to the stride', () {
    final legs = LimbPhysics(height: _h);
    final ankles = <Vector2>[], goals = <Vector2>[];
    const double phaseRate = 2 * math.pi * 3.2 / 1.51;
    for (var step = 0; step < 240; step++) {
      final double t = step * _dt;
      final target = rig
          .solve(CharacterPose(gait: 1, gaitPhase: phaseRate * t, clock: t))
          .translated(offset + Vector2(3.2 * t, 0));
      final hip = target[RigJoint.frontHip].clone();
      final goal = target[RigJoint.frontAnkle] - hip;
      final out = legs.step(
        dt: _dt,
        target: target,
        modes: const [LegMode.swing, LegMode.swing],
        ground: _ground(100),
      );
      ankles.add(out[RigJoint.frontAnkle] - hip);
      goals.add(goal);
      if (step > 36) {
        expect((ankles.last - goal).length, lessThan(0.04));
      }
    }
    double roughness(List<Vector2> path) {
      var sum = 0.0;
      for (var i = 37; i + 1 < path.length; i++) {
        sum += (path[i + 1] - path[i] * 2 + path[i - 1]).length;
      }
      return sum;
    }

    expect(roughness(ankles), lessThan(roughness(goals) * 1.15));
  });

  test('a foot swung into the side of a ledge is not lifted onto it', () {
    final legs = LimbPhysics(height: _h);
    final floor = offset.y + 0.5 * _h;
    // A ledge 30 cm high to the right of x = 5.15: its top is only found
    // by a probe that starts above it.
    const double wall = 5.15;
    final double ledgeTop = floor - 0.3;
    GroundContact? ground(double x, double fromY, double depth) {
      final double y = x >= wall ? ledgeTop : floor;
      if (y < fromY || y > fromY + depth) return null;
      return GroundContact(Vector2(x, y), Vector2(0, -1), _dummyBody!);
    }

    var biggestLift = 0.0;
    double? lastY;
    for (var step = 0; step < 120; step++) {
      // The swinging foot is driven forwards through where the ledge is.
      final target = rig
          .solve(CharacterPose(gait: 1, gaitPhase: 3.6 + step * 0.03))
          .translated(offset);
      final out = legs.step(
        dt: _dt,
        target: target,
        modes: const [LegMode.swing, LegMode.swing],
        ground: ground,
      );
      final y = out[RigJoint.frontAnkle].y;
      if (lastY != null) biggestLift = math.max(biggestLift, lastY - y);
      lastY = y;
    }
    expect(biggestLift, lessThan(0.04));
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
