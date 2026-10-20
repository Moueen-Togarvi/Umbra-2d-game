import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart' show Vector2;

import '../config/game_config.dart';

/// What the controller wants the body to look like this frame.
///
/// Targets are normalized by character height, in its facing-local space:
/// x points the way the child faces, y points down, the origin is the
/// capsule's centre and the soles rest at y = 0.5. A controller can supply
/// planted world feet and real interaction handles; everything else is
/// procedural.
class CharacterPose {
  const CharacterPose({
    this.facing = 1,
    this.gaitPhase = 0,
    this.gait = 0,
    this.air = 0,
    this.fallLean = 0,
    this.blink = false,
    this.limp = 0,
    this.groundY = 0.5,
    this.groundSlope = 0,
    this.landing = 0,
    this.hardLanding = 0,
    this.takeoff = 0,
    this.bodyLean = 0,
    this.push = 0,
    this.hanging = 0,
    this.hangLow = 0,
    this.anticipation = 0,
    this.interactionWeight = 1,
    this.clock = 0,
    this.pelvisDrop = 0,
    this.frontFoot,
    this.backFoot,
    this.frontFootNormal,
    this.backFootNormal,
    this.frontRoll = 0,
    this.backRoll = 0,
    this.frontHand,
    this.backHand,
    this.lookUp = 0,
    this.headTurn = 0,
    this.pull = 0,
    this.effort = 0,
    this.slide = 0,
    this.armAir,
    this.hipFloor,
    this.teeter = 0,
    this.teeterTime = 0,
    this.swingKick = 0,
    this.climb = 0,
    this.crouch = 0,
    this.sit = 0,
  });

  /// +1 facing right, -1 facing left; in between while turning round,
  /// through a front view at 0.
  final double facing;

  /// Position in the run cycle, radians. One turn is two steps.
  final double gaitPhase;

  /// 0 standing, 1 at full running speed.
  final double gait;

  /// 0 on the ground, 1 fully airborne.
  final double air;

  /// Vertical speed, -1 rising fast to +1 falling fast.
  final double fallLean;

  final bool blink;

  /// 1 for a lifeless body (eyes out).
  final double limp;
  final double groundY, groundSlope;

  /// Knee dip after an ordinary landing, and the deep fold after a long drop.
  final double landing, hardLanding;
  final double takeoff;

  /// Extra forward lean from acceleration, radians. Negative leans back.
  final double bodyLean;

  /// 1 while leaning into a crate, pushing or pulling.
  final double push;

  /// 1 while pulling: the body leans back from the crate instead of into
  /// it. [effort] is how hard it is, 0 for a light crate sliding easily to
  /// 1 for a heavy or stuck one.
  final double pull, effort;

  /// 1 while sliding down a steep slope on his feet: upright, leaning back
  /// a little, knees soft, arms out for balance.
  final double slide;

  /// How far the arms are in their airborne pose, if not simply [air]: a
  /// moment's hop over a bump while running should not throw them up.
  final double? armAir;

  /// The lowest the hips are allowed to sit, as a fraction of height, so
  /// planted feet can be reached. A controller passes it smoothed (see
  /// [CharacterRig.hipHeights]) so the hips sink to a new foothold instead
  /// of dropping to it in one frame; when null the rig works it out.
  final double? hipFloor;

  /// 1 while balancing at an edge he has just stopped at: arms out,
  /// rocking over the drop and looking down into it. [teeterTime] is how
  /// long he has been at it, seconds.
  final double teeter, teeterTime;

  /// Swinging on a rope with the feet free: +1 kicking the legs forward on
  /// the forward swing, −1 tucking them back on the back swing.
  final double swingKick;

  /// How far through climbing up onto a ledge, 0 to 1: the body bends
  /// forward over the edge in the middle of it.
  final double climb;

  /// 1 crouched low, creeping: knees deep, back bent over them.
  final double crouch;

  /// 1 sitting on the ground: seat down, knees up, arms round the shins.
  /// The controller puts the feet out in front.
  final double sit;

  /// 1 while hanging from a ledge or rope.
  final double hanging;

  /// 1 to hang with the whole body below the hands, as from a rope, so the
  /// hands hold above the head rather than inside it.
  final double hangLow;
  final double anticipation, interactionWeight;

  /// Seconds, for breathing and idle glances.
  final double clock;

  /// How far the pelvis has sunk on its spring, as a fraction of height:
  /// landings and footstrikes push it down and the legs fold under it.
  final double pelvisDrop;

  /// Where each sole touches the ground.
  final Offset? frontFoot, backFoot;

  /// The ground's normal under each foot (pointing up), so soles lie flat
  /// on slopes, logs and crates. Null for level ground.
  final Offset? frontFootNormal, backFootNormal;

  /// Heel-to-toe roll of each foot, radians: positive lifts the toe, as at
  /// heel strike; negative lifts the heel, as at push-off.
  final double frontRoll, backRoll;
  final Offset? frontHand, backHand;

  /// Idle life: 1 lifts the head to look up; [headTurn] 1 turns the face
  /// round to the camera.
  final double lookUp, headTurn;
}

enum RigJoint {
  head,
  neck,
  chest,
  waist,
  pelvis,
  frontShoulder,
  frontElbow,
  frontHand,
  backShoulder,
  backElbow,
  backHand,
  frontHip,
  frontKnee,
  frontAnkle,
  frontHeel,
  frontToe,
  backHip,
  backKnee,
  backAnkle,
  backHeel,
  backToe,
}

/// Solved joints are actual metres, already mirrored by facing. Translating
/// the pose into world space is the complete ragdoll handoff.
class CharacterRigPose {
  CharacterRigPose({
    required this.joints,
    required this.height,
    required this.facing,
    this.blink = false,
    this.headAngle = 0,
    this.headTurn = 0,
    this.ragdoll = false,
  });

  final Map<RigJoint, Vector2> joints;

  /// [facing] is 1 side-on to the right and −1 to the left; in between,
  /// mid-turn, the body is seen from the front at 0. [headAngle] is a world
  /// rotation in radians, clockwise on screen. [headTurn] turns just the
  /// face towards the camera, from 0 (profile) to 1.
  final double height, facing, headAngle, headTurn;
  final bool blink, ragdoll;

  /// Which way the body faces, ±1, even mid-turn: the way knees and elbows
  /// bend.
  double get side => facing >= 0 ? 1 : -1;
  Vector2 operator [](RigJoint joint) => joints[joint]!;
  Vector2 get pelvis => this[RigJoint.pelvis];
  Vector2 get head => this[RigJoint.head];

  CharacterRigPose translated(Vector2 offset) => CharacterRigPose(
    joints: {
      for (final entry in joints.entries) entry.key: entry.value + offset,
    },
    height: height,
    facing: facing,
    blink: blink,
    headAngle: headAngle,
    headTurn: headTurn,
    ragdoll: ragdoll,
  );

  CharacterRigPose lerp(CharacterRigPose other, double t) {
    final double weight = t.clamp(0.0, 1.0);
    final double angleDelta =
        (other.headAngle - headAngle + math.pi) % (math.pi * 2) - math.pi;
    return CharacterRigPose(
      joints: {
        for (final joint in RigJoint.values)
          joint: this[joint] + (other[joint] - this[joint]) * weight,
      },
      height: height + (other.height - height) * weight,
      facing: other.facing,
      blink: other.blink,
      headAngle: headAngle + angleDelta * weight,
      headTurn: headTurn + (other.headTurn - headTurn) * weight,
      ragdoll: weight < 1 && ragdoll,
    );
  }
}

class TwoBoneSolution {
  const TwoBoneSolution(this.joint, this.end);
  final Vector2 joint, end;
}

/// Reach-clamped two-bone IK. Fixed lengths and a signed bend keep a knee
/// or elbow from stretching or flipping through its anatomical direction.
TwoBoneSolution solveTwoBone(
  Vector2 root,
  Vector2 target,
  double upper,
  double lower, {
  double bendDirection = 1,
}) {
  final Vector2 difference = target - root;
  final double requested = difference.length;
  final Vector2 direction = requested < 1e-7
      ? Vector2(0, 1)
      : difference / requested;
  final double distance = requested.clamp(
    (upper - lower).abs() + 1e-5,
    upper + lower - 1e-5,
  );
  final double along =
      (upper * upper - lower * lower + distance * distance) / (2 * distance);
  final double bend = math.sqrt(math.max(0, upper * upper - along * along));
  return TwoBoneSolution(
    root +
        direction * along +
        Vector2(direction.y, -direction.x) * bend * bendDirection,
    root + direction * distance,
  );
}

/// Timing of the run, shared by the rig (which draws it) and the foot
/// placement (which plants it in the world), so the two never disagree.
///
/// Matched to LIMBO's boy, measured frame by frame: about 4.3 steps a second
/// at full speed, each foot down for about a third of the cycle, so there is
/// a short moment with both feet off the ground, and a high heel kick behind
/// the body before the knee swings through.
abstract final class Gait {
  /// Fraction of a cycle each foot spends planted. Below half, both feet
  /// are briefly in the air: a run, not a walk.
  static double stanceFraction(double gait) =>
      0.56 - 0.24 * gait.clamp(0.0, 1.0);

  /// Distance travelled in one full cycle (two steps), in metres.
  static double strideMeters(double speed) => 0.55 + 0.30 * speed.abs();

  /// How far ahead of the hips a foot lands, in metres: half the distance
  /// the body covers while that foot is down.
  static double reachMeters(double speed, double gait) =>
      stanceFraction(gait) * strideMeters(speed) / 2;

  /// Forward progress of a swinging foot, 0 at toe-off to 1 at contact. It
  /// lingers behind first (the heel kick), then sweeps through.
  static double swingProgress(double t) {
    final double e = math.pow(t.clamp(0.0, 1.0), 1.35).toDouble();
    return e * e * (3 - 2 * e);
  }

  /// Height of a swinging foot, as a fraction of body height. Peaks early,
  /// behind the body, and falls away into the next contact.
  static double swingLift(double t, double gait) =>
      math.sin(math.pi * math.pow(t.clamp(0.0, 1.0), 0.65)) *
      (0.045 + 0.15 * gait.clamp(0.0, 1.0));
}

/// The child's skeleton. All lengths are fractions of total height.
///
/// Proportions follow LIMBO's boy rather than an adult: a very large head
/// (about a third of his height), a short torso and short legs.
class CharacterRig {
  CharacterRig({required this.height});
  final double height;

  static const double thigh = 0.155;
  static const double shin = 0.15;

  /// How high the ankle joint sits above the sole: the boot's height.
  static const double ankleHeight = 0.03;

  /// Along the sole from the point under the ankle to where the heel and
  /// the ball of the foot touch down: the pivots of the foot's roll.
  static const double heelReach = 0.036;
  static const double toeReach = 0.075;

  /// Ankle-height points behind and ahead of the ankle that the heel and
  /// toe joints sit at.
  static const double heelOffset = 0.03;
  static const double toeOffset = 0.072;
  static const double hipSpacing = 0.022;
  static const double torsoLength = 0.29;
  static const double upperArm = 0.17;
  static const double forearm = 0.16;
  static const double headRadius = 0.155;

  /// Total arm reach from shoulder to hand.
  static const double armReach = upperArm + forearm;

  /// Where a shoulder sits when standing upright, relative to the capsule
  /// centre. Interactions use it to decide what the hands can reach.
  static Vector2 restShoulder({required bool front}) =>
      Vector2(front ? 0.012 : -0.012, _standingHipY - torsoLength + 0.025);

  /// A child at rest stands on softly bent knees, never locked straight.
  static const double _standingHipY = 0.195;

  /// How far the hips come down crouched, and sitting (the seat on the
  /// ground), as fractions of height.
  static const double crouchDrop = 0.20, sitDrop = 0.27;

  /// Where the shoulder line (top of the torso) is for a given lean.
  static Vector2 _rotate(Vector2 v, double angle) {
    final double c = math.cos(angle), s = math.sin(angle);
    return Vector2(v.x * c - v.y * s, v.x * s + v.y * c);
  }

  /// Hanging, the shoulders shrug up beside the head, which is what lets
  /// short arms hold on above it.
  static const double hangShrug = 0.08;

  static Vector2 _shoulder(
    double hipY,
    double lean,
    bool front, {
    double shrug = 0,
    double sway = 0,
  }) =>
      Vector2(sway, hipY) +
      _rotate(
        Vector2(front ? 0.012 : -0.012, -torsoLength + 0.025 - shrug),
        lean,
      );

  /// The hips' height before reaching for the feet, and the height they
  /// must come down to so every planted foot can be reached
  /// (`double.negativeInfinity` when no foot is planted), both as fractions
  /// of height. [solve] uses the larger.
  (double, double) hipHeights(CharacterPose pose) {
    final double gait = pose.gait.clamp(0.0, 1.0);
    final double air = pose.air.clamp(0.0, 1.0);
    final double grounded = 1 - air;
    final double stance = Gait.stanceFraction(gait);
    final double cycle = (pose.gaitPhase / (2 * math.pi)) % 1;
    final double breath = math.sin(pose.clock * 2.1);
    final double idle = (1 - gait) * grounded * (1 - pose.push);
    // The body is lowest as each foot takes the weight, highest in the
    // flight between steps: two dips per cycle. The pelvis spring adds the
    // physical bounce of each footstrike on top.
    final double bob =
        gait * grounded * 0.012 * math.cos(4 * math.pi * (cycle - stance / 2));
    // Hanging from a rope, the whole body drops below the hands.
    final double base =
        pose.hangLow * 0.08 +
        _standingHipY +
        gait * grounded * 0.024 +
        bob +
        pose.pelvisDrop +
        pose.hardLanding * 0.10 +
        pose.takeoff * 0.02 +
        pose.anticipation * 0.04 +
        pose.push * (0.025 + 0.035 * pose.effort) +
        pose.slide * 0.045 +
        pose.teeter * 0.012 +
        pose.crouch * crouchDrop +
        pose.sit * sitDrop +
        breath * 0.0018 * idle;
    final double sway = idle * 0.011 * math.sin(pose.clock * 1.55);
    double floor = double.negativeInfinity;
    const double leg = (thigh + shin) * 0.995;
    for (final front in const [false, true]) {
      final target = front ? pose.frontFoot : pose.backFoot;
      if (target == null) continue;
      final normal = front ? pose.frontFootNormal : pose.backFootNormal;
      final (ankle, _) = footOnGround(
        Vector2(target.dx, target.dy),
        normal == null ? Vector2(0, -1) : Vector2(normal.dx, normal.dy),
        front ? pose.frontRoll : pose.backRoll,
      );
      final double horizontal =
          ankle.x - (sway + (front ? hipSpacing : -hipSpacing));
      final double verticalReach = math.sqrt(
        math.max(0, leg * leg - horizontal * horizontal),
      );
      floor = math.max(floor, ankle.y - verticalReach);
    }
    return (base, floor);
  }

  CharacterRigPose solve(CharacterPose pose) {
    final points = <RigJoint, Vector2>{};
    final double gait = pose.gait.clamp(0.0, 1.0);
    final double air = pose.air.clamp(0.0, 1.0);
    final double grounded = 1 - air;
    final double stance = Gait.stanceFraction(gait);
    final double cycle = (pose.gaitPhase / (2 * math.pi)) % 1;
    final double rising = air * (-pose.fallLean).clamp(0.0, 1.0);
    final double falling = air * pose.fallLean.clamp(0.0, 1.0);
    final double descend = _smooth(-0.35, 0.45, pose.fallLean);
    final double breath = math.sin(pose.clock * 2.1);
    final double idle = (1 - gait) * grounded * (1 - pose.push);
    final double speed = gait * GameConfig.moveSpeedMetersPerSecond;
    final double reach = Gait.reachMeters(speed, gait) / height;

    // Hanging from a rope, the whole body drops below the hands, so they
    // hold it above the head rather than inside it.
    final double hang = pose.hangLow * 0.08;
    final double shrug = pose.hanging * hangShrug;
    final (double baseHipY, double footFloor) = hipHeights(pose);
    double hipY = baseHipY;

    // Where each foot stands: the ankle above its sole, rolled about the
    // heel or the ball of the foot and tilted to the ground under it.
    final groundFeet = <bool, (Vector2, Vector2)>{};
    for (final front in const [false, true]) {
      final target = front ? pose.frontFoot : pose.backFoot;
      if (target == null) continue;
      final normal = front ? pose.frontFootNormal : pose.backFootNormal;
      groundFeet[front] = footOnGround(
        Vector2(target.dx, target.dy),
        normal == null ? Vector2(0, -1) : Vector2(normal.dx, normal.dy),
        front ? pose.frontRoll : pose.backRoll,
      );
    }

    // A slow shift of weight from foot to foot while standing still.
    final double sway = idle * 0.011 * math.sin(pose.clock * 1.55);

    // Lower the pelvis enough to reach a planted foot on a slope, a stone or
    // at toe-off (see [hipHeights]). Moving the root with every target
    // would fight the controller.
    hipY = math.max(hipY, pose.hipFloor ?? footFloor);
    // Standing, the knees never fold past this; crouched or sitting, the
    // seat comes right down.
    hipY = math.min(hipY, 0.36 + math.max(pose.crouch * 0.07, pose.sit * 0.11));

    // Forward lean, in radians: into the run, into a push, over bent knees
    // on landing, and back against a skid (a negative bodyLean).
    double lean =
        gait * grounded * (0.07 + 0.11 * gait) * (1 - pose.push) +
        pose.bodyLean +
        // Into a push, back from a pull — further back, the arms straight
        // to the crate — more the heavier it is.
        pose.push *
            ((0.08 + 0.22 * pose.effort) * (1 - pose.pull) -
                (0.12 + 0.25 * pose.effort) * pose.pull) -
        pose.slide * 0.2 +
        pose.landing * 0.14 +
        pose.hardLanding * 0.45 +
        pose.anticipation * 0.12 +
        rising * 0.06 -
        falling * 0.03 -
        pose.hanging * 0.05 +
        // Balancing at an edge: peering over, rocking back and forth.
        pose.teeter * (0.03 + 0.07 * _rock(pose.teeterTime)) +
        // Climbing onto a ledge: over the edge, then upright to stand.
        0.32 * math.sin(math.pi * pose.climb.clamp(0.0, 1.0)) +
        // Hunched over the knees, crouched or sitting.
        pose.crouch * 0.45 +
        pose.sit * 0.10;

    // Hands on a crate or rope must not be dragged away by the lean. Find
    // the lean nearest the desired one that keeps both shoulders within
    // reach of their targets; hips and planted soles are unaffected.
    final double weight = pose.interactionWeight.clamp(0.0, 1.0);
    if ((pose.frontHand != null || pose.backHand != null) && weight > 0) {
      bool reachable(double candidate) {
        for (final front in const [false, true]) {
          final target = front ? pose.frontHand : pose.backHand;
          if (target == null) continue;
          final shoulder = _shoulder(
            hipY,
            candidate,
            front,
            shrug: shrug,
            sway: sway,
          );
          final double dx = target.dx - shoulder.x;
          final double dy = target.dy - shoulder.y;
          if (dx * dx + dy * dy > armReach * armReach * 0.995) return false;
        }
        return true;
      }

      if (!reachable(lean)) {
        double? best;
        for (var i = 1; i <= 140 && best == null; i++) {
          for (final sign in const [-1.0, 1.0]) {
            final double candidate = lean + sign * i * 0.01;
            if (reachable(candidate)) {
              best = candidate;
              break;
            }
          }
        }
        if (best != null) lean += (best - lean) * weight;
      }
    }

    final pelvis = Vector2(sway, hipY);
    Vector2 spine(double x, double y) => pelvis + _rotate(Vector2(x, y), lean);
    points[RigJoint.pelvis] = pelvis;
    points[RigJoint.waist] = spine(0.004, -0.085);
    points[RigJoint.chest] = spine(0.006, -torsoLength);
    final neck = spine(0.010, -torsoLength - 0.035);
    points[RigJoint.neck] = neck;

    // The head counters most of the body's lean, which keeps the eyes
    // level through the run: the steadiness LIMBO's boy has. An idle child
    // sometimes lifts his head to look up, or round at the camera.
    final double headTilt =
        lean * 0.42 -
        rising * 0.10 +
        falling * 0.05 -
        pose.hanging * 0.18 -
        pose.push * (0.12 - 0.22 * pose.effort * (1 - pose.pull)) -
        pose.lookUp * 0.42 +
        pose.headTurn * 0.06 +
        pose.teeter * 0.22 +
        pose.hardLanding * 0.2 +
        pose.sit * 0.05;
    points[RigJoint.head] = neck + _rotate(Vector2(0.026, -0.14), headTilt);

    for (final front in const [false, true]) {
      // --- Legs ---------------------------------------------------------
      final hip = Vector2(sway + (front ? hipSpacing : -hipSpacing), hipY);
      final double legCycle = (cycle + (front ? 0 : 0.5)) % 1;
      Vector2 ankle;
      Vector2 footDirection;
      final ground = groundFeet[front];
      if (ground != null) {
        (ankle, footDirection) = ground;
      } else {
        double x, lift;
        double toeTilt;
        if (legCycle < stance) {
          final double t = legCycle / stance;
          x = reach * (1 - 2 * t);
          lift = 0;
          toeTilt = 0;
        } else {
          final double t = (legCycle - stance) / (1 - stance);
          x = -reach + 2 * reach * Gait.swingProgress(t);
          lift = Gait.swingLift(t, gait);
          toeTilt = lift * 3.2;
        }
        x = _mix(front ? 0.07 : -0.06, x, gait);
        Vector2 sole = Vector2(x, pose.groundY + x * pose.groundSlope - lift);

        // In the air the knees tuck up on the way up, then the legs hang
        // and reach for the ground on the way down.
        final tuck = front ? Vector2(0.12, 0.30) : Vector2(0.025, 0.355);
        final dangle = front ? Vector2(0.075, 0.475) : Vector2(-0.05, 0.455);
        final airSole = tuck + (dangle - tuck) * descend;
        airSole.y += hang;
        // Pumping a rope swing: legs out ahead going forward, tucked back
        // underneath coming back.
        final double kick = pose.swingKick.clamp(-1.0, 1.0) * pose.hangLow;
        airSole.x += kick > 0 ? kick * 0.15 : kick * 0.07;
        airSole.y -= kick > 0 ? kick * 0.07 : -kick * 0.04;
        sole += (airSole - sole) * air;
        sole.x += (front ? 0.05 : -0.05) * pose.hardLanding;
        final double footAngle = _mix(
          math.atan(pose.groundSlope) + toeTilt,
          _mix(-0.25, 0.55, descend),
          air,
        );
        footDirection = Vector2(math.cos(footAngle), math.sin(footAngle));
        ankle = sole - Vector2(0, ankleHeight);
      }
      final legSolution = solveTwoBone(hip, ankle, thigh, shin);
      points[front ? RigJoint.frontHip : RigJoint.backHip] = hip;
      points[front ? RigJoint.frontKnee : RigJoint.backKnee] =
          legSolution.joint;
      points[front ? RigJoint.frontAnkle : RigJoint.backAnkle] =
          legSolution.end;
      points[front ? RigJoint.frontHeel : RigJoint.backHeel] =
          legSolution.end - footDirection * heelOffset;
      points[front ? RigJoint.frontToe : RigJoint.backToe] =
          legSolution.end + footDirection * toeOffset;

      // --- Arms ---------------------------------------------------------
      final shoulder = _shoulder(hipY, lean, front, shrug: shrug, sway: sway);
      // Opposite to the same-side leg: back when that foot strikes. Elbows
      // bend to about a right angle and the arms pump close to the body,
      // further back than forward.
      final double armAir = (pose.armAir ?? air).clamp(0.0, 1.0);
      final double run = gait * (1 - armAir) * (1 - pose.push);
      final double swing =
          -run * (0.17 + 0.34 * gait) * math.cos(2 * math.pi * legCycle);
      double angle = 0.05 + 0.025 * breath * idle + swing - run * 0.14;
      double bend = 0.28 + run * 1.25;
      // Airborne, the elbows stay bent and the arms never point straight
      // ahead. Going up, the front arm lifts with the hand near the face and
      // the back arm trails; coming down, both go up and out for balance,
      // drifting a little in a long fall. The limb physics adds the weight.
      final double flail =
          math.sin(pose.clock * 3.5 + (front ? 0 : 2.1)) *
          0.06 *
          armAir *
          pose.fallLean.clamp(0.0, 1.0);
      // The elbows stay well bent so the arms never stretch out long:
      // going up, the front hand comes up by the face and the back one
      // stays by the hip; coming down, the front arm rises with the hand
      // by the head and the back one trails behind, bent. (Raised behind,
      // the back arm would hide behind the head and leave only a forearm
      // sticking out of it.)
      final double airAngle = _mix(
        front ? 1.4 : -0.45,
        front ? 2.0 + flail : -0.9 - flail,
        descend,
      );
      angle = _mix(angle, airAngle, armAir);
      bend = _mix(
        bend,
        _mix(front ? 1.6 : 1.3, front ? 1.3 : 1.3, descend),
        armAir,
      );
      // Landing: arms forward; a hard landing puts the hands to the ground.
      angle = _mix(angle, 0.55, pose.landing * 0.7);
      angle = _mix(angle, 0.30, pose.hardLanding);
      bend = _mix(bend, 0.15, pose.hardLanding);
      // Sliding: arms out to both sides for balance.
      angle = _mix(angle, front ? 1.3 : -1.1, pose.slide);
      bend = _mix(bend, front ? 0.55 : 0.35, pose.slide);
      // Balancing at an edge: arms out to both sides, circling a little.
      final double circle = 0.12 * _rock(pose.teeterTime + (front ? 0 : 0.11));
      angle = _mix(angle, (front ? 1.55 : -1.35) + circle, pose.teeter);
      bend = _mix(bend, 0.35, pose.teeter);
      // Hanging with nothing to hold: reach straight up.
      angle = _mix(angle, math.pi - 0.12, pose.hanging);
      bend = _mix(bend, 0.08, pose.hanging);
      // Crouched: the arms hang forward, low, by the knees.
      angle = _mix(angle, 0.30, pose.crouch * (1 - armAir));
      bend = _mix(bend, 0.70, pose.crouch * (1 - armAir));

      final elbow =
          shoulder + Vector2(math.sin(angle), math.cos(angle)) * upperArm;
      Vector2 hand =
          elbow +
          Vector2(math.sin(angle + bend), math.cos(angle + bend)) * forearm;
      final Offset? handTarget = front ? pose.frontHand : pose.backHand;
      if (handTarget != null) {
        hand += (Vector2(handTarget.dx, handTarget.dy) - hand) * weight;
      } else if (pose.sit > 0) {
        // Sitting: the arms round the shins, hands just below the knee.
        final Vector2 shin = legSolution.end - legSolution.joint;
        final Vector2 hold =
            legSolution.joint + shin * 0.35 + Vector2(front ? 0.03 : 0.015, 0);
        hand += (hold - hand) * pose.sit.clamp(0.0, 1.0);
      }
      final arm = solveTwoBone(
        shoulder,
        hand,
        upperArm,
        forearm,
        bendDirection: -1,
      );
      points[front ? RigJoint.frontShoulder : RigJoint.backShoulder] = shoulder;
      points[front ? RigJoint.frontElbow : RigJoint.backElbow] = arm.joint;
      points[front ? RigJoint.frontHand : RigJoint.backHand] = arm.end;
    }
    return CharacterRigPose(
      joints: {
        for (final entry in points.entries)
          entry.key: Vector2(
            entry.value.x * height * pose.facing,
            entry.value.y * height,
          ),
      },
      height: height,
      facing: pose.facing,
      blink: pose.blink || pose.limp > 0.5,
      headAngle: headTilt * 0.7 * pose.facing,
      headTurn: pose.headTurn,
    );
  }

  /// The ankle and heel-to-toe direction of a foot whose sole touches
  /// [sole] on ground with the upward [normal], rolled by [roll] radians.
  /// The roll pivots about the heel (positive, toe up) or the ball of the
  /// foot (negative, heel up), so the touching part stays on the ground.
  /// Facing-local, height-normalized coordinates.
  static (Vector2, Vector2) footOnGround(
    Vector2 sole,
    Vector2 normal,
    double roll,
  ) {
    final Vector2 up = normal.normalized();
    final Vector2 along = Vector2(-up.y, up.x);
    final Vector2 rolledAlong = _rotate(along, -roll);
    final Vector2 rolledUp = _rotate(up, -roll);
    final Vector2 underAnkle = roll >= 0
        ? sole - along * heelReach + rolledAlong * heelReach
        : sole + along * toeReach - rolledAlong * toeReach;
    return (underAnkle + rolledUp * ankleHeight, rolledAlong);
  }

  static double _mix(double a, double b, double t) => a + (b - a) * t;

  /// The rocking of a boy balancing at an edge: about 2.5 times a second,
  /// dying away as he finds his balance.
  static double _rock(double t) =>
      math.sin(2 * math.pi * 2.5 * t) * math.exp(-1.6 * t);

  static double _smooth(double edge0, double edge1, double x) {
    final double t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}
