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

/// What drives an arm this step.
enum ArmMode {
  /// The hand holds something — a crate, a rope, a ledge — and is pinned
  /// to it.
  grip,

  /// On the ground: the hands follow their swing closely and smoothly.
  ground,

  /// In the air: softer, so the hands trail a little on take-off and
  /// settle on landing.
  air,
}

/// The legs and arms as small physical chains, so they move like limbs
/// rather than like an animation: they have weight, they lag and swing, the
/// legs fold under a landing, and nothing passes through the ground.
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
/// Each arm is calmer than a leg: the hand, relative to its shoulder,
/// follows the pose on a critically damped spring — it lags a little and
/// settles, but never overshoots or wobbles — and the elbow is solved from
/// shoulder and hand, so it always bends backwards and the bones never
/// stretch. A gripping hand is pinned to what it holds, and a hand can be
/// put down on the ground but not through it.
///
/// This is the visual body's physics; the capsule stays the gameplay
/// authority, so these limbs never push the player or a crate. When the boy
/// dies, these simulated joints are what the Box2D ragdoll starts from.
class LimbPhysics {
  LimbPhysics({required this.height});

  final double height;
  final List<_LegChain> _legs = [_LegChain(), _LegChain()];
  final List<_ArmChain> _arms = [_ArmChain(), _ArmChain()];
  bool _ready = false;
  final Vector2 _lastPelvis = Vector2.zero();
  final Vector2 _carry = Vector2.zero();

  static const int _iterations = 6;

  /// Fraction of the remaining distance to its pose a point closes per
  /// 1/120 s step, by mode.
  static const Map<LegMode, double> _drive = {
    LegMode.planted: 0.6,
    LegMode.swing: 0.45,
    LegMode.air: 0.11,
    LegMode.hang: 0.035,
  };

  /// How quickly a hand follows its pose, by mode: the natural frequency
  /// of its critically damped spring, in hertz.
  static const Map<ArmMode, double> _armHertz = {
    ArmMode.grip: 12,
    ArmMode.ground: 6,
    ArmMode.air: 3.5,
  };

  /// The share of the shoulder's change of speed a hand feels as inertia,
  /// and the most it can be kicked by in one step, metres a second: enough
  /// for a little weight on take-off and landing, never enough to flap.
  static const double _armInertia = 0.25, _armKick = 0.6;

  /// The fastest a hand's pose is followed, and the fastest a hand moves
  /// relative to its shoulder, metres a second. A pose that jumps is caught
  /// up with smoothly instead of snapped to.
  static const double _armGoalSpeed = 3, _armSpeed = 5;

  /// Velocity kept per second: swinging limbs settle rather than ring.
  static const double _damping = 3.5;

  /// Starts again from the animated pose, e.g. after a teleport or a turn.
  void reset() => _ready = false;

  /// Advances the limbs by [dt] seconds towards [target], a solved pose in
  /// world metres, and writes the simulated joints into it (in place: this
  /// runs at 120 Hz and copying whole poses shows up on the web).
  CharacterRigPose step({
    required double dt,
    required CharacterRigPose target,
    required List<LegMode> modes,
    List<ArmMode> armModes = const [ArmMode.ground, ArmMode.ground],
    required GroundQuery ground,
    required double gravity,
  }) {
    final double h = height;
    final double thigh = CharacterRig.thigh * h;
    final double shin = CharacterRig.shin * h;
    final double footLength = CharacterRig.toeOffset * h;
    // Mid-turn the pose is squeezed towards side-on; the joints still bend
    // the way the body faces.
    final double facing = target.side;
    final joints = target.joints;
    final double keep = math.exp(-_damping * dt);
    final Vector2 fall = Vector2(0, gravity * dt * dt);
    final Vector2 pelvis = target[RigJoint.pelvis];
    if (_ready) {
      _carry
        ..setFrom(pelvis)
        ..sub(_lastPelvis);
    } else {
      _carry.setZero();
    }
    _lastPelvis.setFrom(pelvis);
    _stepArms(dt, target, armModes, ground, facing);
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
      for (final point in leg.points) {
        point.integrate(keep, fall, _carry);
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

  void _stepArms(
    double dt,
    CharacterRigPose target,
    List<ArmMode> modes,
    GroundQuery ground,
    double facing,
  ) {
    final double upper = CharacterRig.upperArm * height;
    final double fore = CharacterRig.forearm * height;
    final double reach = (upper + fore) * 0.999;
    final double palm = 0.025 * height;
    final double ease = 1 - math.exp(-dt / 0.1);
    for (var i = 0; i < 2; i++) {
      final bool front = i == 0;
      final arm = _arms[i];
      final mode = modes[i];
      final shoulder =
          target[front ? RigJoint.frontShoulder : RigJoint.backShoulder];
      final RigJoint handJoint = front ? RigJoint.frontHand : RigJoint.backHand;
      // Everything is relative to the shoulder, so the torso's bob, lean
      // and shrug carry the arm along instead of shaking it.
      final Vector2 goal = target[handJoint] - shoulder;
      final double hertz = _armHertz[mode]!;
      if (!_ready || !arm.isFinite) arm.snap(goal, shoulder, hertz);

      // A little of the shoulder's change of speed is felt as inertia.
      final Vector2 shoulderVelocity = (shoulder - arm.lastShoulder) / dt;
      final Vector2 kick = (shoulderVelocity - arm.shoulderVelocity)
        ..scale(_armInertia);
      if (kick.length > _armKick) kick.scale(_armKick / kick.length);
      arm.velocity.sub(kick);
      arm.shoulderVelocity.setFrom(shoulderVelocity);
      arm.lastShoulder.setFrom(shoulder);

      // How fast the pose itself moves, within reason.
      final Vector2 goalVelocity = (goal - arm.lastGoal) / dt;
      if (goalVelocity.length > _armGoalSpeed) {
        goalVelocity.scale(_armGoalSpeed / goalVelocity.length);
      }

      // One step of a critically damped spring towards the moving pose,
      // solved exactly: it closes in without ever overshooting.
      arm.omega += (2 * math.pi * hertz - arm.omega) * ease;
      final double w = arm.omega;
      final double decay = math.exp(-w * dt);
      final Vector2 x = arm.hand - arm.lastGoal;
      final Vector2 u = arm.velocity - goalVelocity;
      final Vector2 c = u + x * w;
      final Vector2 nextX = (x + c * dt)..scale(decay);
      final Vector2 nextU = (u - c * (w * dt))..scale(decay);
      // The pose is followed only as fast as [goalVelocity]: a pose that
      // jumps further than that is caught up with by the spring.
      arm.hand
        ..setFrom(arm.lastGoal)
        ..addScaled(goalVelocity, dt)
        ..add(nextX);
      arm.velocity
        ..setFrom(nextU)
        ..add(goalVelocity);
      arm.lastGoal.setFrom(goal);

      // A gripping hand is pinned to its grip, eased in over a moment.
      arm.pin = mode == ArmMode.grip ? math.min(1, arm.pin + dt / 0.06) : 0;
      if (arm.pin > 0) {
        arm.hand.add((goal - arm.hand)..scale(arm.pin));
        if (arm.pin >= 1) arm.velocity.setFrom(goalVelocity);
      }

      // Never too fast, never out of reach. (Never far behind the pose
      // either: the spring cannot run away from it.)
      if (arm.velocity.length > _armSpeed) {
        arm.velocity.scale(_armSpeed / arm.velocity.length);
      }
      if (arm.hand.length > reach) arm.hand.scale(reach / arm.hand.length);

      // A hand below the hips can be put down on the ground, not through.
      // The ground is looked for between where the palm was last step and
      // where it is now: a hand coming down onto it is stopped, but one
      // that has swung into the side of a ledge or a platform is not
      // lifted onto its top.
      final Vector2 hand = shoulder + arm.hand;
      final double bottom = hand.y + palm;
      // (Just snapped to the pose, look all the way down from the shoulder.)
      final double from =
          math.min(
            arm.lastBottom.isFinite ? arm.lastBottom : shoulder.y,
            bottom,
          ) -
          0.04;
      arm.lastBottom = bottom;
      if (arm.pin < 1 && hand.y > target[RigJoint.pelvis].y) {
        final contact = ground(hand.x, from, bottom - from + 0.04);
        if (contact != null) {
          final double slope = contact.normal.y.abs() < 1e-6
              ? 0
              : -contact.normal.x / contact.normal.y;
          final double surface =
              contact.point.y + slope * (hand.x - contact.point.x);
          final double depth = hand.y + palm - surface;
          if (depth > 0) {
            arm.hand.y -= depth;
            hand.y -= depth;
            arm.lastBottom -= depth;
            if (arm.velocity.y > 0) arm.velocity.y = 0;
          }
        }
      }

      // The elbow follows from shoulder and hand: always bent backwards,
      // the bones always their length.
      final solved = solveTwoBone(
        shoulder,
        hand,
        upper,
        fore,
        bendDirection: -facing,
      );
      target.joints[front ? RigJoint.frontElbow : RigJoint.backElbow] =
          solved.joint;
      target.joints[handJoint] = solved.end;
    }
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

  /// Keeps momentum, falls, and loses a little of its speed relative to
  /// the body, which moved by [carry] since the last step: damping is the
  /// limb's own drag, not the air's, so a long fall doesn't blow the arms
  /// and legs up over the head.
  void integrate(double keep, Vector2 fall, Vector2 carry) {
    final double vx = carry.x + (p.x - previous.x - carry.x) * keep;
    final double vy = carry.y + (p.y - previous.y - carry.y) * keep;
    previous.setFrom(p);
    p.x += vx + fall.x;
    p.y += vy + fall.y;
  }

  void pull(Vector2 goal, double amount) {
    p.add((goal - p) * amount);
  }
}

class _ArmChain {
  /// The hand and its velocity, relative to the shoulder.
  final Vector2 hand = Vector2.zero();
  final Vector2 velocity = Vector2.zero();

  /// The pose's hand, relative to the shoulder, and the shoulder's place
  /// and velocity, last step.
  final Vector2 lastGoal = Vector2.zero();
  final Vector2 lastShoulder = Vector2.zero();
  final Vector2 shoulderVelocity = Vector2.zero();

  /// The spring's natural frequency, radians a second, eased between modes.
  double omega = 0;
  double pin = 0;

  /// Where the bottom of the palm was last step, world y.
  double lastBottom = double.nan;

  bool get isFinite =>
      hand.x.isFinite &&
      hand.y.isFinite &&
      velocity.x.isFinite &&
      velocity.y.isFinite &&
      omega.isFinite;

  void snap(Vector2 goal, Vector2 shoulder, double hertz) {
    hand.setFrom(goal);
    velocity.setZero();
    lastGoal.setFrom(goal);
    lastShoulder.setFrom(shoulder);
    shoulderVelocity.setZero();
    omega = 2 * math.pi * hertz;
    lastBottom = double.nan;
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
