import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart' show Vector2;

import '../config/game_config.dart';
import 'character_preset.dart';

/// Targets are normalized by character height, in its facing-local space.
/// A controller can supply planted world feet and real interaction handles.
class RaincoatPose {
  const RaincoatPose({
    this.facing = 1,
    this.walkPhase = 0,
    this.walk = 0,
    this.air = 0,
    this.fallLean = 0,
    this.blink = false,
    this.limp = 0,
    this.groundY = 0.5,
    this.groundSlope = 0,
    this.landing = 0,
    this.takeoff = 0,
    this.bodyLean = 0,
    this.run = 0,
    this.crouch = 0,
    this.hanging = 0,
    this.anticipation = 0,
    this.interactionWeight = 1,
    this.frontFoot,
    this.backFoot,
    this.frontHand,
    this.backHand,
  });

  final double facing, walkPhase, walk, air, fallLean, limp;
  final bool blink;
  final double groundY, groundSlope, landing, takeoff, bodyLean;
  final double run, crouch, hanging, anticipation, interactionWeight;
  final Offset? frontFoot, backFoot, frontHand, backHand;
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
    required this.preset,
    this.blink = false,
    this.headAngle = 0,
    this.lanternSwing = 0,
    this.lanternVisible = true,
    this.ragdoll = false,
  });

  final Map<RigJoint, Vector2> joints;
  final double height, facing, headAngle, lanternSwing;
  final CharacterPreset preset;
  final bool blink, lanternVisible, ragdoll;
  Vector2 operator [](RigJoint joint) => joints[joint]!;
  Vector2 get pelvis => this[RigJoint.pelvis];
  Vector2 get head => this[RigJoint.head];

  CharacterRigPose translated(Vector2 offset) => CharacterRigPose(
    joints: {
      for (final entry in joints.entries) entry.key: entry.value + offset,
    },
    height: height,
    facing: facing,
    preset: preset,
    blink: blink,
    headAngle: headAngle,
    lanternSwing: lanternSwing,
    lanternVisible: lanternVisible,
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
      preset: other.preset,
      blink: other.blink,
      headAngle: headAngle + angleDelta * weight,
      lanternSwing: lanternSwing + (other.lanternSwing - lanternSwing) * weight,
      lanternVisible: other.lanternVisible,
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

class CharacterRig {
  CharacterRig({required this.height, this.preset = CharacterPreset.raincoat});
  final double height;
  final CharacterPreset preset;
  double clock = 0;

  CharacterRigPose solve(RaincoatPose pose) {
    final points = <RigJoint, Vector2>{};
    final double strideDip =
        pose.walk *
        (1 - math.sin(pose.walkPhase).abs()) *
        (0.05 + pose.run * 0.02);
    final double compression =
        pose.landing * 0.070 + pose.takeoff * 0.030 + pose.anticipation * 0.035;
    final double bob =
        -pose.walk * math.sin(pose.walkPhase * 2).abs() * 0.012 +
        (1 - pose.walk) * math.sin(clock * 1.6) * 0.002;
    double hipY = 0.085 + strideDip + compression + pose.crouch * 0.23 + bob;
    double shoulderY =
        -0.145 +
        compression +
        bob +
        strideDip * 0.55 +
        pose.crouch * 0.37 -
        pose.hanging * 0.05;
    // Lower the pelvis enough to reach a planted sole on a slope or at
    // toe-off. Moving the root with every target would fight the controller.
    final double unadjustedHip = hipY;
    for (final front in const [false, true]) {
      final target = front ? pose.frontFoot : pose.backFoot;
      if (target == null) continue;
      final double horizontal = target.dx - (front ? 0.035 : -0.035);
      final double verticalReach = math.sqrt(
        math.max(0, 0.399 * 0.399 - horizontal * horizontal),
      );
      hipY = math.max(hipY, target.dy - 0.022 - verticalReach);
    }
    hipY = math.min(hipY, 0.33);
    shoulderY += (hipY - unadjustedHip) * 0.55;
    double lean =
        pose.walk * (0.045 + pose.run * 0.035) +
        pose.bodyLean +
        pose.air * pose.fallLean * 0.02 +
        pose.crouch * 0.15;
    // Braking must not drag a shoulder away from a held object. Intersect
    // both arms' horizontal reach intervals and keep the chest inside them.
    // Hips and planted soles remain independent of this upper-body correction.
    var minimumLean = double.negativeInfinity;
    var maximumLean = double.infinity;
    var hasHandTarget = false;
    for (final front in const [false, true]) {
      final target = front ? pose.frontHand : pose.backHand;
      if (target == null) continue;
      final double vertical = target.dy - (shoulderY + 0.015);
      const double reach = 0.29999;
      if (vertical.abs() >= reach) continue;
      final double horizontal = math.sqrt(reach * reach - vertical * vertical);
      final double shoulderOffset = front ? 0.050 : -0.050;
      minimumLean = math.max(
        minimumLean,
        target.dx - horizontal - shoulderOffset,
      );
      maximumLean = math.min(
        maximumLean,
        target.dx + horizontal - shoulderOffset,
      );
      hasHandTarget = true;
    }
    if (hasHandTarget && minimumLean <= maximumLean) {
      lean +=
          (lean.clamp(minimumLean, maximumLean) - lean) *
          pose.interactionWeight.clamp(0.0, 1.0);
    }
    points[RigJoint.pelvis] = Vector2(0, hipY);
    points[RigJoint.waist] = Vector2(lean * 0.3, hipY - 0.075);
    points[RigJoint.chest] = Vector2(lean, shoulderY);
    points[RigJoint.neck] = Vector2(lean * 0.8 + 0.015, shoulderY - 0.06);
    points[RigJoint.head] = Vector2(
      lean * 0.7 + 0.018 - pose.hanging * 0.085,
      shoulderY - 0.180 + pose.hanging * 0.10,
    );

    for (final front in const [false, true]) {
      final hip = Vector2(front ? 0.035 : -0.035, hipY);
      final double phase =
          (pose.walkPhase / (2 * math.pi) + (front ? 0 : 0.5)) % 1;
      final bool stance = phase < 0.5;
      final double t = stance ? phase * 2 : (phase - 0.5) * 2;
      final double reach = GameConfig.walkStrideMeters / (4 * height);
      final double gaitX = stance
          ? reach * (1 - 2 * t)
          : -reach + 2 * reach * _ease(t);
      final double x = _mix(front ? 0.045 : -0.045, gaitX, pose.walk);
      final double lift = stance
          ? 0
          : math.sin(t * math.pi) * (0.10 + pose.run * 0.045) * pose.walk;
      Vector2 sole = Vector2(x, pose.groundY + x * pose.groundSlope - lift);
      final double descending = pose.fallLean.clamp(0.0, 1.0);
      final airSole = front
          ? Vector2(0.11 - descending * 0.06, 0.40 + descending * 0.09)
          : Vector2(-0.10 + descending * 0.04, 0.38 + descending * 0.10);
      sole += (airSole - sole) * pose.air;
      final Offset? target = front ? pose.frontFoot : pose.backFoot;
      if (target != null) sole = Vector2(target.dx, target.dy);
      final leg = solveTwoBone(hip, sole - Vector2(0, 0.022), 0.20, 0.20);
      final slope = pose.air > 0.4 ? -0.10 : math.atan(pose.groundSlope);
      final Vector2 footDirection = Vector2(math.cos(slope), math.sin(slope));
      points[front ? RigJoint.frontHip : RigJoint.backHip] = hip;
      points[front ? RigJoint.frontKnee : RigJoint.backKnee] = leg.joint;
      points[front ? RigJoint.frontAnkle : RigJoint.backAnkle] = leg.end;
      points[front ? RigJoint.frontHeel : RigJoint.backHeel] =
          leg.end - footDirection * 0.035;
      points[front ? RigJoint.frontToe : RigJoint.backToe] =
          leg.end + footDirection * 0.061;

      final shoulder = Vector2(
        (front ? 0.050 : -0.050) + lean,
        shoulderY + 0.015,
      );
      final double swing = math.sin(pose.walkPhase + (front ? math.pi : 0));
      double angle = pose.walk * swing * (0.32 + pose.run * 0.30);
      angle = _mix(angle, -0.25 + pose.fallLean * 0.10, pose.air);
      final double bend =
          0.22 + pose.walk * (0.22 + pose.run * 0.30) + pose.air * 0.35;
      final elbow = shoulder + Vector2(math.sin(angle), math.cos(angle)) * 0.16;
      Vector2 hand =
          elbow +
          Vector2(math.sin(angle + bend), math.cos(angle + bend)) * 0.14;
      // Fold the arms ahead of the knees while squatting. A hanging idle
      // arm would pass through the floor, taking the lantern with it.
      hand +=
          (Vector2(front ? 0.24 : 0.20, front ? 0.35 : 0.40) - hand) *
          pose.crouch;
      final Offset? handTarget = front ? pose.frontHand : pose.backHand;
      if (handTarget != null) {
        hand +=
            (Vector2(handTarget.dx, handTarget.dy) - hand) *
            pose.interactionWeight.clamp(0.0, 1.0);
      } else if (pose.hanging > 0) {
        hand +=
            (Vector2(front ? 0.03 : -0.03, shoulderY - 0.29) - hand) *
            pose.hanging;
      }
      final arm = solveTwoBone(shoulder, hand, 0.16, 0.14, bendDirection: -1);
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
      preset: preset,
      blink: pose.blink || pose.limp > 0.5,
      headAngle: pose.fallLean * pose.air * 0.045,
      lanternSwing: math.sin(pose.walkPhase) * pose.walk * 0.07,
      lanternVisible:
          pose.hanging < 0.2 && pose.frontHand == null && pose.limp < 0.5,
    );
  }

  static double _mix(double a, double b, double t) => a + (b - a) * t;
  static double _ease(double t) => t * t * (3 - 2 * t);
}
