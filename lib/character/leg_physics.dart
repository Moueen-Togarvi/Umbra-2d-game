import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart' show Vector2;

import 'character_rig.dart';
import 'ground_probe.dart';

/// What drives a leg this step.
enum LegMode {
  /// The foot is on the ground: ankle and toe are pinned to the contact,
  /// and only the knee is free.
  planted,

  /// The foot is swinging to its next step: pulled firmly along its path,
  /// with a little lag and overshoot from its own momentum.
  swing,

  /// The body is in the air: the legs follow their pose loosely, so they
  /// trail on take-off and swing with the body's motion.
  air,

  /// Hanging from a ledge or rope: gravity does most of the work.
  hang,
}

/// The legs as two small physical chains, so they move like legs rather
/// than like an animation: they have weight, they lag and swing, they fold
/// under a landing, and they cannot pass through the ground.
///
/// Each leg is hip → knee → ankle → toe. The hip is carried by the body;
/// knee, ankle and toe are point masses integrated with Verlet (position
/// based) dynamics under gravity, pulled towards the animated pose by a
/// spring whose strength depends on [LegMode], and held together by
/// constraints: fixed bone lengths, a knee that only bends forwards, an
/// ankle that only bends so far, and the ground. The ground is queried
/// from the real Box2D world, so a foot rests on the surface that is
/// actually there.
///
/// This is the visual body's physics; the capsule stays the gameplay
/// authority, so these legs never push the player or a crate. When the boy
/// dies, these simulated joints are what the Box2D ragdoll starts from.
class LegPhysics {
  LegPhysics({required this.height});

  final double height;
  final List<_LegChain> _legs = [_LegChain(), _LegChain()];
  bool _ready = false;

  static const int _iterations = 6;

  /// Fraction of the remaining distance to its pose a point closes per
  /// 1/120 s step, by mode.
  static const Map<LegMode, double> _drive = {
    LegMode.planted: 0.6,
    LegMode.swing: 0.45,
    LegMode.air: 0.11,
    LegMode.hang: 0.035,
  };

  /// Velocity kept per second: swinging legs settle rather than ring.
  static const double _damping = 3.5;

  /// Starts again from the animated pose, e.g. after a teleport or a turn.
  void reset() => _ready = false;

  /// Advances both legs by [dt] seconds towards [target], a solved pose in
  /// world metres, and writes the simulated legs into it (in place: this
  /// runs at 120 Hz and copying whole poses shows up on the web).
  CharacterRigPose step({
    required double dt,
    required CharacterRigPose target,
    required List<LegMode> modes,
    required GroundQuery ground,
    required double gravity,
  }) {
    final double h = height;
    final double thigh = CharacterRig.thigh * h;
    final double shin = CharacterRig.shin * h;
    final double footLength = CharacterRig.toeOffset * h;
    final double facing = target.facing;
    final joints = target.joints;
    for (var i = 0; i < 2; i++) {
      final bool front = i == 0;
      final leg = _legs[i];
      final mode = modes[i];
      final hip = target[front ? RigJoint.frontHip : RigJoint.backHip];
      final kneeGoal = target[front ? RigJoint.frontKnee : RigJoint.backKnee];
      final ankleGoal =
          target[front ? RigJoint.frontAnkle : RigJoint.backAnkle];
      final toeGoal = target[front ? RigJoint.frontToe : RigJoint.backToe];
      if (!_ready || !leg.isFinite) {
        leg.snap(kneeGoal, ankleGoal, toeGoal);
      }

      // Pinning a foot is eased in over a few steps, so a dangling leg
      // reaches down onto the ground instead of snapping onto it.
      leg.pin = mode == LegMode.planted ? math.min(1, leg.pin + dt / 0.06) : 0;

      // Integrate: keep momentum, lose a little to damping, fall.
      final double keep = math.exp(-_damping * dt);
      final Vector2 fall = Vector2(0, gravity * dt * dt);
      for (final point in leg.points) {
        point.integrate(keep, fall);
      }

      // Drive towards the pose. The knee is only nudged: its place is
      // mostly decided by the bones on either side of it.
      final double drive = 1 - math.pow(1 - _drive[mode]!, dt * 120).toDouble();
      leg.knee.pull(kneeGoal, drive * 0.5);
      leg.ankle.pull(ankleGoal, drive);
      leg.toe.pull(toeGoal, drive);
      if (leg.pin > 0) {
        leg.ankle.pull(ankleGoal, leg.pin);
        leg.toe.pull(toeGoal, leg.pin);
      }

      // The ground under heel and toe, looked up once per step and then
      // treated as a plane: the feet move millimetres between iterations.
      final planes = leg.pin < 1 ? _groundPlanes(leg, ground, facing) : null;

      for (var iteration = 0; iteration < _iterations; iteration++) {
        // Bones keep their length. The hip is carried by the body; a
        // pinned ankle is held by the ground.
        _hold(hip, leg.knee.p, thigh, 0, 1);
        _hold(leg.knee.p, leg.ankle.p, shin, 0.5, leg.pin >= 1 ? 0 : 0.5);
        if (leg.pin < 1) {
          _hold(leg.ankle.p, leg.toe.p, footLength, 0.5, 0.5);
        }
        _kneeForward(hip, leg.knee.p, leg.ankle.p, facing);
        if (planes != null) {
          _ankleLimit(leg, facing);
          _ground(leg, planes, facing);
        }
      }
      // Lifting the toe off the ground tips the heel down a little, and
      // the other way round: settle both against the ground once more.
      if (planes != null) {
        _ground(leg, planes, facing);
        _ground(leg, planes, facing);
      }

      final Vector2 along = (leg.toe.p - leg.ankle.p).normalized();
      joints[front ? RigJoint.frontKnee : RigJoint.backKnee] = leg.knee.p
          .clone();
      joints[front ? RigJoint.frontAnkle : RigJoint.backAnkle] = leg.ankle.p
          .clone();
      joints[front ? RigJoint.frontToe : RigJoint.backToe] = leg.toe.p.clone();
      joints[front ? RigJoint.frontHeel : RigJoint.backHeel] =
          leg.ankle.p - along * (CharacterRig.heelOffset * h);
    }
    _ready = true;
    return target;
  }

  /// Restores the distance between [a] and [b] to [length], moving each by
  /// its share of the error ([wa] + [wb] need not be 1; 0 holds a point).
  static void _hold(Vector2 a, Vector2 b, double length, double wa, double wb) {
    final Vector2 d = b - a;
    final double distance = d.length;
    if (distance < 1e-9 || wa + wb == 0) return;
    final double error = (distance - length) / distance;
    final double share = 1 / (wa + wb);
    a.add(d * (error * wa * share));
    b.sub(d * (error * wb * share));
  }

  /// A knee only bends forwards. If it has swung behind the hip–ankle line
  /// it is mirrored back across it.
  static void _kneeForward(
    Vector2 hip,
    Vector2 knee,
    Vector2 ankle,
    double facing,
  ) {
    final Vector2 d = ankle - hip;
    final double lengthSquared = d.length2;
    if (lengthSquared < 1e-12) return;
    final Vector2 k = knee - hip;
    final double side = d.x * k.y - d.y * k.x;
    if (side * facing <= 0) return;
    final Vector2 onLine = d * (k.dot(d) / lengthSquared);
    knee.setFrom(hip + onLine * 2 - k);
  }

  /// Keeps the foot within the ankle's range: the toes can point down a
  /// long way (push-off, dangling) but only come up a little.
  static void _ankleLimit(_LegChain leg, double facing) {
    final Vector2 shin = leg.ankle.p - leg.knee.p;
    final Vector2 foot = leg.toe.p - leg.ankle.p;
    final double sx = shin.x * facing, fx = foot.x * facing;
    final double angle = math.atan2(
      sx * foot.y - shin.y * fx,
      sx * fx + shin.y * foot.y,
    );
    const double lowest = -math.pi / 2 - 0.45; // toes up
    const double highest = -math.pi / 2 + 1.15; // toes down
    final double clamped = angle.clamp(lowest, highest);
    if (clamped == angle) return;
    final double length = foot.length;
    final double shinAngle = math.atan2(shin.y, sx);
    // The foot is the shin's direction turned by the (clamped) ankle angle.
    final double footAngle = shinAngle + clamped;
    leg.toe.p.setValues(
      leg.ankle.p.x + math.cos(footAngle) * length * facing,
      leg.ankle.p.y + math.sin(footAngle) * length,
    );
  }

  /// Where the heel and toe soles of [leg] are, given its current pose.
  (Vector2, Vector2) _soles(_LegChain leg, double facing) {
    final Vector2 along = leg.toe.p - leg.ankle.p;
    if (along.length2 < 1e-12) along.setValues(facing, 0);
    along.normalize();
    final Vector2 down = Vector2(-along.y * facing, along.x * facing);
    final double sole = CharacterRig.ankleHeight * height;
    return (
      leg.ankle.p - along * (CharacterRig.heelReach * height) + down * sole,
      leg.toe.p + down * sole,
    );
  }

  /// The ground under the heel and toe as (point, slope) planes, or null
  /// where there is none.
  List<(Vector2, double)?> _groundPlanes(
    _LegChain leg,
    GroundQuery ground,
    double facing,
  ) {
    final (heel, toe) = _soles(leg, facing);
    return [
      for (final sole in [heel, toe])
        switch (ground(sole.x, sole.y - 0.3, 0.6)) {
          null => null,
          final contact => (
            contact.point,
            contact.normal.y.abs() < 1e-6
                ? 0.0
                : -contact.normal.x / contact.normal.y,
          ),
        },
    ];
  }

  /// Heel and toe soles stay on or above the ground, sliding with friction
  /// where they touch it. The heel sole hangs off the ankle point, the toe
  /// sole off the toe point.
  void _ground(_LegChain leg, List<(Vector2, double)?> planes, double facing) {
    for (var i = 0; i < 2; i++) {
      final plane = planes[i];
      if (plane == null) continue;
      final (heel, toe) = _soles(leg, facing);
      final Vector2 sole = i == 0 ? heel : toe;
      final (anchor, slope) = plane;
      final double surface = anchor.y + slope * (sole.x - anchor.x);
      final double depth = sole.y - surface;
      if (depth <= 0) continue;
      final point = i == 0 ? leg.ankle : leg.toe;
      point.p.y -= depth;
      // Friction: a foot touching the ground mostly stops sliding.
      point.previous.x += (point.p.x - point.previous.x) * 0.6;
      point.previous.y = point.p.y;
    }
  }
}

class _Point {
  final Vector2 p = Vector2.zero();
  final Vector2 previous = Vector2.zero();

  void place(Vector2 at) {
    p.setFrom(at);
    previous.setFrom(at);
  }

  void integrate(double keep, Vector2 fall) {
    final Vector2 velocity = (p - previous) * keep;
    previous.setFrom(p);
    p.add(velocity + fall);
  }

  void pull(Vector2 goal, double amount) {
    p.add((goal - p) * amount);
  }
}

class _LegChain {
  final _Point knee = _Point(), ankle = _Point(), toe = _Point();
  double pin = 0;
  late final List<_Point> points = [knee, ankle, toe];

  bool get isFinite =>
      points.every((point) => point.p.x.isFinite && point.p.y.isFinite);

  void snap(Vector2 kneeAt, Vector2 ankleAt, Vector2 toeAt) {
    knee.place(kneeAt);
    ankle.place(ankleAt);
    toe.place(toeAt);
  }
}
