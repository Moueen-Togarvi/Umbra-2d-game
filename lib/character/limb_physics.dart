import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart' show Vector2;

import 'character_rig.dart';
import 'ground_probe.dart';

/// What drives a leg this step.
enum LegMode {
  /// The foot is on the ground: ankle and toe are pinned to the contact.
  planted,

  /// The foot is swinging to its next step: it follows its path closely.
  swing,

  /// The body is in the air: the legs follow their pose more softly, so
  /// they trail a little on take-off and settle on landing.
  air,

  /// Hanging from a ledge or rope: softest of all, so the legs dangle.
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

/// The legs and arms as small physical limbs, so they move with weight
/// rather than like an animation, and calmly: nothing in them ever wobbles.
///
/// Each hand and each foot follows the pose relative to its shoulder or
/// hip on a critically damped spring. It lags a little and settles, but
/// never overshoots. Torso motion carries the limbs along instead of
/// shaking them, and a small, capped share of the body's jolts is felt as
/// inertia — a hand or foot trails a sudden take-off and comes back.
/// Elbows and knees are solved from shoulder and hand, hip and ankle, so
/// they always bend the right way and the bones never stretch.
///
/// A planted foot or a gripping hand is pinned where it stands or holds.
/// A foot's sole and a hand's palm can come down onto the ground but not
/// through it; the ground is looked for only along the way they moved this
/// step, so one that swings into the side of a ledge is never lifted onto
/// its top. The ground is the real Box2D world, so a foot rests on the
/// surface that is actually there.
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

  /// How quickly a foot follows its pose, by mode: the natural frequency of
  /// its critically damped spring, in hertz.
  static const Map<LegMode, double> _legHertz = {
    LegMode.planted: 12,
    LegMode.swing: 10,
    LegMode.air: 4.5,
    LegMode.hang: 3,
  };

  /// How quickly a hand follows its pose, by mode, in hertz.
  static const Map<ArmMode, double> _armHertz = {
    ArmMode.grip: 12,
    ArmMode.ground: 6,
    ArmMode.air: 3.5,
  };

  /// The share of the shoulder's or hip's change of speed a hand or foot
  /// feels as inertia, and the most it can be kicked by in one step, metres
  /// a second: a little weight on take-off and landing, never a flap.
  static const double _armInertia = 0.15, _armKick = 0.3;

  /// In the air the hands stay a little short of the arm's full length,
  /// so the elbows stay bent and the arms never look stretched out long.
  static const double _airArmReach = 0.86;
  static const double _legInertia = 0.2, _legKick = 0.5;

  /// The fastest a pose is followed (a pose that jumps is caught up with
  /// smoothly, not snapped to), and the fastest a hand or foot moves
  /// relative to the body, metres a second. A running foot swings fast.
  static const double _armGoalSpeed = 3, _armSpeed = 5;
  static const double _swingGoalSpeed = 9, _legGoalSpeed = 4, _legSpeed = 10;

  /// The fastest the foot's angle follows its pose, radians a second.
  static const double _footTurnSpeed = 20;

  /// The ankle's range, as the foot's angle from the shin: the toes can
  /// point down a long way (push-off, dangling) but only come up a little.
  static const double _toesUp = -math.pi / 2 - 0.45;
  static const double _toesDown = -math.pi / 2 + 1.15;

  /// How far above and below a palm or sole's path the ground is looked
  /// for, metres.
  static const double _contactWindow = 0.04;

  double _squeeze = 1;

  /// [joint], bent out from the straight line between [a] and [b], as seen
  /// mid-turn: its sideways reach off that line shortened by [_squeeze].
  Vector2 _turned(Vector2 joint, Vector2 a, Vector2 b) {
    if (_squeeze >= 0.999) return joint;
    final Vector2 ab = b - a;
    final double len2 = ab.length2;
    final double t = len2 < 1e-9 ? 0 : (joint - a).dot(ab) / len2;
    final double onX = a.x + ab.x * t;
    return Vector2(onX + (joint.x - onX) * _squeeze, joint.y);
  }

  /// Starts again from the animated pose, e.g. after a teleport.
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
  }) {
    // Mid-turn the pose is squeezed towards side-on; the joints still bend
    // the way the body faces, but a knee or elbow bent out sideways then
    // points partly at the camera, and is seen squeezed as well (else it
    // would flip from one side to the other as he passes face-on).
    final double facing = target.side;
    _squeeze = target.facing.abs().clamp(0.0, 1.0);
    _stepArms(dt, target, armModes, ground, facing);
    _stepLegs(dt, target, modes, ground, facing);
    _ready = true;
    return target;
  }

  /// One exact step of a critically damped spring that carries [position]
  /// and [velocity] towards a [goal] moving from [lastGoal]. The goal is
  /// followed no faster than [maxGoalSpeed]; further than that, the spring
  /// catches up. It closes in without ever overshooting.
  static void _follow(
    Vector2 position,
    Vector2 velocity,
    Vector2 lastGoal,
    Vector2 goal,
    double omega,
    double dt,
    double maxGoalSpeed,
  ) {
    final Vector2 goalVelocity = (goal - lastGoal) / dt;
    if (goalVelocity.length > maxGoalSpeed) {
      goalVelocity.scale(maxGoalSpeed / goalVelocity.length);
    }
    final double decay = math.exp(-omega * dt);
    final Vector2 x = position - lastGoal;
    final Vector2 u = velocity - goalVelocity;
    final Vector2 c = u + x * omega;
    final Vector2 nextX = (x + c * dt)..scale(decay);
    final Vector2 nextU = (u - c * (omega * dt))..scale(decay);
    position
      ..setFrom(lastGoal)
      ..addScaled(goalVelocity, dt)
      ..add(nextX);
    velocity
      ..setFrom(nextU)
      ..add(goalVelocity);
    lastGoal.setFrom(goal);
  }

  /// [_follow] for a single number: returns the new value and velocity.
  static (double, double) _followScalar(
    double value,
    double velocity,
    double lastGoal,
    double goal,
    double omega,
    double dt,
    double maxGoalSpeed,
  ) {
    final double goalVelocity = ((goal - lastGoal) / dt).clamp(
      -maxGoalSpeed,
      maxGoalSpeed,
    );
    final double decay = math.exp(-omega * dt);
    final double x = value - lastGoal;
    final double u = velocity - goalVelocity;
    final double c = u + x * omega;
    return (
      lastGoal + goalVelocity * dt + (x + c * dt) * decay,
      (u - c * omega * dt) * decay + goalVelocity,
    );
  }

  /// A small, capped share of the body point's change of speed, felt by a
  /// limb as inertia; updates the body point's remembered place and speed.
  static void _inertia(
    Vector2 velocity,
    Vector2 body,
    Vector2 lastBody,
    Vector2 bodyVelocity,
    double dt,
    double share,
    double cap,
  ) {
    final Vector2 now = (body - lastBody) / dt;
    final Vector2 kick = (now - bodyVelocity)..scale(share);
    if (kick.length > cap) kick.scale(cap / kick.length);
    velocity.sub(kick);
    bodyVelocity.setFrom(now);
    lastBody.setFrom(body);
  }

  /// The ground under [x] between where something was last step
  /// ([lastBottom], world y, or [fallback] just after a snap) and where it
  /// is now ([bottom]), as (surface y at x, slope), or null.
  static (double, double)? _contact(
    GroundQuery ground,
    double x,
    double bottom,
    double lastBottom,
    double fallback,
  ) {
    final double from =
        math.min(lastBottom.isFinite ? lastBottom : fallback, bottom) -
        _contactWindow;
    final contact = ground(x, from, bottom - from + _contactWindow);
    if (contact == null) return null;
    final double slope = contact.normal.y.abs() < 1e-6
        ? 0
        : -contact.normal.x / contact.normal.y;
    return (contact.point.y + slope * (x - contact.point.x), slope);
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

      _inertia(
        arm.velocity,
        shoulder,
        arm.lastShoulder,
        arm.shoulderVelocity,
        dt,
        _armInertia,
        _armKick,
      );
      arm.omega += (2 * math.pi * hertz - arm.omega) * ease;
      final Vector2 goalVelocity = (goal - arm.lastGoal) / dt;
      _follow(
        arm.hand,
        arm.velocity,
        arm.lastGoal,
        goal,
        arm.omega,
        dt,
        _armGoalSpeed,
      );

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
      final double reach =
          (upper + fore) * (mode == ArmMode.air ? _airArmReach : 0.999);
      if (arm.hand.length > reach) arm.hand.scale(reach / arm.hand.length);

      // A hand below the hips can be put down on the ground, not through,
      // and one swung into the side of a ledge is not lifted onto its top.
      final Vector2 hand = shoulder + arm.hand;
      final double bottom = hand.y + palm;
      final double lastBottom = arm.lastBottom;
      arm.lastBottom = bottom;
      if (arm.pin < 1 && hand.y > target[RigJoint.pelvis].y) {
        final contact = _contact(
          ground,
          hand.x,
          bottom,
          lastBottom,
          shoulder.y,
        );
        if (contact != null) {
          final double depth = bottom - contact.$1;
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
      target.joints[front ? RigJoint.frontElbow : RigJoint.backElbow] = _turned(
        solved.joint,
        shoulder,
        solved.end,
      );
      target.joints[handJoint] = solved.end;
    }
  }

  void _stepLegs(
    double dt,
    CharacterRigPose target,
    List<LegMode> modes,
    GroundQuery ground,
    double facing,
  ) {
    final double h = height;
    final double thigh = CharacterRig.thigh * h;
    final double shin = CharacterRig.shin * h;
    final double reach = (thigh + shin) * 0.999;
    final double ease = 1 - math.exp(-dt / 0.08);
    final joints = target.joints;
    for (var i = 0; i < 2; i++) {
      final bool front = i == 0;
      final leg = _legs[i];
      final mode = modes[i];
      final hip = target[front ? RigJoint.frontHip : RigJoint.backHip];
      final ankleGoalWorld =
          target[front ? RigJoint.frontAnkle : RigJoint.backAnkle];
      final toeGoalWorld = target[front ? RigJoint.frontToe : RigJoint.backToe];
      // Relative to the hip, so the body's bob and lean carry the leg.
      final Vector2 goal = ankleGoalWorld - hip;
      final double goalAngle = _footAngle(
        toeGoalWorld - ankleGoalWorld,
        facing,
      );
      final double hertz = _legHertz[mode]!;
      if (!_ready || !leg.isFinite) leg.snap(goal, goalAngle, hip, hertz);

      _inertia(
        leg.velocity,
        hip,
        leg.lastHip,
        leg.hipVelocity,
        dt,
        _legInertia,
        _legKick,
      );
      leg.omega += (2 * math.pi * hertz - leg.omega) * ease;
      final Vector2 goalVelocity = (goal - leg.lastGoal) / dt;
      _follow(
        leg.ankle,
        leg.velocity,
        leg.lastGoal,
        goal,
        leg.omega,
        dt,
        mode == LegMode.swing || mode == LegMode.planted
            ? _swingGoalSpeed
            : _legGoalSpeed,
      );
      // The foot's angle, unwrapped to the nearest turn of the goal.
      final double unwrapped = leg.angle + _wrap(goalAngle - leg.angle);
      final double lastAngleGoal =
          unwrapped - _wrap(unwrapped - leg.lastAngleGoal);
      final double angleGoalVelocity = (unwrapped - lastAngleGoal) / dt;
      final (angle, angleVelocity) = _followScalar(
        leg.angle,
        leg.angleVelocity,
        lastAngleGoal,
        unwrapped,
        leg.omega,
        dt,
        _footTurnSpeed,
      );
      leg.angle = angle;
      leg.angleVelocity = angleVelocity;
      leg.lastAngleGoal = unwrapped;

      // A planted foot is pinned where it stands, eased in over a few
      // steps so a dangling leg reaches down onto the ground.
      leg.pin = mode == LegMode.planted ? math.min(1, leg.pin + dt / 0.06) : 0;
      if (leg.pin > 0) {
        leg.ankle.add((goal - leg.ankle)..scale(leg.pin));
        leg.angle += (unwrapped - leg.angle) * leg.pin;
        if (leg.pin >= 1) {
          leg.velocity.setFrom(goalVelocity);
          leg.angleVelocity = angleGoalVelocity.clamp(
            -_footTurnSpeed,
            _footTurnSpeed,
          );
        }
      }
      if (leg.velocity.length > _legSpeed) {
        leg.velocity.scale(_legSpeed / leg.velocity.length);
      }

      // Twice: the ground lifts the foot or turns it, which moves the shin,
      // which moves the ankle's range; then settle the soles once more.
      final double lastHeel = leg.lastHeel, lastToe = leg.lastToe;
      for (var pass = 0; pass < 2; pass++) {
        if (leg.ankle.length > reach) leg.ankle.scale(reach / leg.ankle.length);
        final solved = solveTwoBone(
          hip,
          hip + leg.ankle,
          thigh,
          shin,
          bendDirection: facing,
        );
        if (leg.pin < 1) {
          leg.angle = _withinAnkle(
            leg.angle,
            solved.end - solved.joint,
            facing,
          );
          _ground(leg, hip, facing, ground, lastHeel, lastToe);
        }
        if (pass == 1 || leg.pin >= 1) {
          if (leg.ankle.length > reach) {
            leg.ankle.scale(reach / leg.ankle.length);
          }
          final placed = solveTwoBone(
            hip,
            hip + leg.ankle,
            thigh,
            shin,
            bendDirection: facing,
          );
          final Vector2 along = _along(leg.angle, facing);
          joints[front ? RigJoint.frontKnee : RigJoint.backKnee] = _turned(
            placed.joint,
            hip,
            placed.end,
          );
          // The foot, too, points partly at the camera mid-turn.
          final Vector2 seen = Vector2(along.x * _squeeze, along.y);
          joints[front ? RigJoint.frontAnkle : RigJoint.backAnkle] = placed.end;
          joints[front ? RigJoint.frontToe : RigJoint.backToe] =
              placed.end + seen * (CharacterRig.toeOffset * h);
          joints[front ? RigJoint.frontHeel : RigJoint.backHeel] =
              placed.end - seen * (CharacterRig.heelOffset * h);
          final (heel, toe) = _soles(placed.end, along, facing);
          leg.lastHeel = heel.y;
          leg.lastToe = toe.y;
          break;
        }
      }
    }
  }

  /// The heel and toe soles' lowest points, for an ankle at [ankle] with
  /// the foot pointing along [along].
  (Vector2, Vector2) _soles(Vector2 ankle, Vector2 along, double facing) {
    final Vector2 down = Vector2(-along.y * facing, along.x * facing);
    final double sole = CharacterRig.ankleHeight * height;
    return (
      ankle - along * (CharacterRig.heelReach * height) + down * sole,
      ankle + along * (CharacterRig.toeOffset * height) + down * sole,
    );
  }

  /// Keeps a swinging foot's heel and toe on or above the ground under
  /// them: a toe that would go into it turns the foot up as far as the
  /// ankle allows, and whatever is left lifts the ankle, as does a heel.
  void _ground(
    _LegChain leg,
    Vector2 hip,
    double facing,
    GroundQuery ground,
    double lastHeel,
    double lastToe,
  ) {
    final double footLength = CharacterRig.toeOffset * height;
    Vector2 ankle = hip + leg.ankle;
    Vector2 along = _along(leg.angle, facing);
    var (heel, toe) = _soles(ankle, along, facing);
    final double toeX = toe.x;
    final toeGround = _contact(ground, toeX, toe.y, lastToe, hip.y);
    if (toeGround != null && toe.y > toeGround.$1) {
      final (surface, slope) = toeGround;
      // Turn the toes up towards the surface, about the ankle.
      final double turn = math.asin(
        ((toe.y - surface) / footLength).clamp(0.0, 1.0),
      );
      final double turned = _clampAngle(leg.angle - turn);
      if (turned != leg.angle) {
        leg.angle = turned;
        if (leg.angleVelocity > 0) leg.angleVelocity = 0;
        along = _along(leg.angle, facing);
        (heel, toe) = _soles(ankle, along, facing);
      }
      // The same ground, where the toe is now.
      final double rest = toe.y - (surface + slope * (toe.x - toeX));
      if (rest > 0) _lift(leg, rest);
    }
    ankle = hip + leg.ankle;
    (heel, toe) = _soles(ankle, along, facing);
    final heelGround = _contact(ground, heel.x, heel.y, lastHeel, hip.y);
    if (heelGround != null && heel.y > heelGround.$1) {
      _lift(leg, heel.y - heelGround.$1);
    }
  }

  static void _lift(_LegChain leg, double by) {
    leg.ankle.y -= by;
    if (leg.velocity.y > 0) leg.velocity.y = 0;
  }

  /// The foot's angle in facing-local terms: 0 points straight ahead,
  /// positive turns the toes down.
  static double _footAngle(Vector2 along, double facing) =>
      math.atan2(along.y, along.x * facing);

  static Vector2 _along(double angle, double facing) =>
      Vector2(math.cos(angle) * facing, math.sin(angle));

  static double _wrap(double angle) =>
      (angle + math.pi) % (2 * math.pi) - math.pi;

  /// Clamps a foot angle to the ankle's range around a typical shin
  /// (straight down): used where the shin is not to hand.
  static double _clampAngle(double angle) =>
      angle.clamp(_toesUp + math.pi / 2, _toesDown + math.pi / 2);

  /// Keeps the foot's [angle] within the ankle's range of the [shinLine]
  /// (knee to ankle).
  static double _withinAnkle(double angle, Vector2 shinLine, double facing) {
    final double shinAngle = math.atan2(shinLine.y, shinLine.x * facing);
    final double relative = _wrap(angle - shinAngle);
    final double clamped = relative.clamp(_toesUp, _toesDown);
    return clamped == relative ? angle : shinAngle + clamped;
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
  /// The ankle and its velocity, relative to the hip.
  final Vector2 ankle = Vector2.zero();
  final Vector2 velocity = Vector2.zero();

  /// The foot's angle (see [LimbPhysics._footAngle]) and its rate.
  double angle = 0;
  double angleVelocity = 0;

  /// Last step's pose (ankle relative to the hip, foot angle), and the
  /// hip's place and velocity.
  final Vector2 lastGoal = Vector2.zero();
  double lastAngleGoal = 0;
  final Vector2 lastHip = Vector2.zero();
  final Vector2 hipVelocity = Vector2.zero();

  /// The spring's natural frequency, radians a second, eased between modes.
  double omega = 0;
  double pin = 0;

  /// Where the heel and toe soles were last step, world y.
  double lastHeel = double.nan, lastToe = double.nan;

  bool get isFinite =>
      ankle.x.isFinite &&
      ankle.y.isFinite &&
      velocity.x.isFinite &&
      velocity.y.isFinite &&
      angle.isFinite &&
      angleVelocity.isFinite &&
      omega.isFinite;

  void snap(Vector2 goal, double goalAngle, Vector2 hip, double hertz) {
    ankle.setFrom(goal);
    velocity.setZero();
    angle = goalAngle;
    angleVelocity = 0;
    lastGoal.setFrom(goal);
    lastAngleGoal = goalAngle;
    lastHip.setFrom(hip);
    hipVelocity.setZero();
    omega = 2 * math.pi * hertz;
    lastHeel = lastToe = double.nan;
  }
}
